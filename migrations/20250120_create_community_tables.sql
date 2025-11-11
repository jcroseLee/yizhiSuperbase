-- Ensure profiles table exists (required for foreign key relationships)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  avatar_url text,
  role text default 'user',
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

-- Create profiles policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'profiles' 
    and policyname = 'profiles_select_own'
  ) then
    create policy "profiles_select_own"
      on public.profiles for select
      using (auth.uid() = id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'profiles' 
    and policyname = 'profiles_insert_own'
  ) then
    create policy "profiles_insert_own"
      on public.profiles for insert
      with check (auth.uid() = id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'profiles' 
    and policyname = 'profiles_update_own'
  ) then
    create policy "profiles_update_own"
      on public.profiles for update
      using (auth.uid() = id)
      with check (auth.uid() = id);
  end if;
end $$;

-- Posts table for BBS forum posts
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  content_html text,
  view_count integer default 0,
  like_count integer default 0,
  comment_count integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.posts enable row level security;

-- Create posts policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'posts' 
    and policyname = 'posts_select_all'
  ) then
    create policy "posts_select_all"
      on public.posts for select
      using (true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'posts' 
    and policyname = 'posts_insert_own'
  ) then
    create policy "posts_insert_own"
      on public.posts for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'posts' 
    and policyname = 'posts_update_own'
  ) then
    create policy "posts_update_own"
      on public.posts for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'posts' 
    and policyname = 'posts_delete_own'
  ) then
    create policy "posts_delete_own"
      on public.posts for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- Comments table for post comments and replies
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  content text not null,
  like_count integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.comments enable row level security;

-- Create comments policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comments' 
    and policyname = 'comments_select_all'
  ) then
    create policy "comments_select_all"
      on public.comments for select
      using (true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comments' 
    and policyname = 'comments_insert_own'
  ) then
    create policy "comments_insert_own"
      on public.comments for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comments' 
    and policyname = 'comments_update_own'
  ) then
    create policy "comments_update_own"
      on public.comments for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comments' 
    and policyname = 'comments_delete_own'
  ) then
    create policy "comments_delete_own"
      on public.comments for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- Messages table for user-to-user messages
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references auth.users(id) on delete cascade,
  receiver_id uuid references auth.users(id) on delete cascade,
  content text not null,
  is_read boolean default false,
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

-- Create messages policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'messages' 
    and policyname = 'messages_select_own'
  ) then
    create policy "messages_select_own"
      on public.messages for select
      using (auth.uid() = sender_id or auth.uid() = receiver_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'messages' 
    and policyname = 'messages_insert_own'
  ) then
    create policy "messages_insert_own"
      on public.messages for insert
      with check (auth.uid() = sender_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'messages' 
    and policyname = 'messages_update_received'
  ) then
    create policy "messages_update_received"
      on public.messages for update
      using (auth.uid() = receiver_id)
      with check (auth.uid() = receiver_id);
  end if;
end $$;

-- Post likes table
create table if not exists public.post_likes (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

alter table public.post_likes enable row level security;

-- Create post_likes policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'post_likes' 
    and policyname = 'post_likes_select_all'
  ) then
    create policy "post_likes_select_all"
      on public.post_likes for select
      using (true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'post_likes' 
    and policyname = 'post_likes_insert_own'
  ) then
    create policy "post_likes_insert_own"
      on public.post_likes for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'post_likes' 
    and policyname = 'post_likes_delete_own'
  ) then
    create policy "post_likes_delete_own"
      on public.post_likes for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- Comment likes table
create table if not exists public.comment_likes (
  user_id uuid references auth.users(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, comment_id)
);

alter table public.comment_likes enable row level security;

-- Create comment_likes policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comment_likes' 
    and policyname = 'comment_likes_select_all'
  ) then
    create policy "comment_likes_select_all"
      on public.comment_likes for select
      using (true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comment_likes' 
    and policyname = 'comment_likes_insert_own'
  ) then
    create policy "comment_likes_insert_own"
      on public.comment_likes for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comment_likes' 
    and policyname = 'comment_likes_delete_own'
  ) then
    create policy "comment_likes_delete_own"
      on public.comment_likes for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- Function to update post comment_count
create or replace function update_post_comment_count()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts
    set comment_count = comment_count + 1
    where id = NEW.post_id;
    return NEW;
  elsif TG_OP = 'DELETE' then
    update public.posts
    set comment_count = comment_count - 1
    where id = OLD.post_id;
    return OLD;
  end if;
  return null;
end;
$$ language plpgsql;

-- Trigger to update comment_count when comments are added/deleted
drop trigger if exists update_post_comment_count_trigger on public.comments;
create trigger update_post_comment_count_trigger
  after insert or delete on public.comments
  for each row execute function update_post_comment_count();

-- Function to update post like_count
create or replace function update_post_like_count()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts
    set like_count = like_count + 1
    where id = NEW.post_id;
    return NEW;
  elsif TG_OP = 'DELETE' then
    update public.posts
    set like_count = like_count - 1
    where id = OLD.post_id;
    return OLD;
  end if;
  return null;
end;
$$ language plpgsql;

-- Trigger to update like_count when post_likes are added/deleted
drop trigger if exists update_post_like_count_trigger on public.post_likes;
create trigger update_post_like_count_trigger
  after insert or delete on public.post_likes
  for each row execute function update_post_like_count();

-- Function to update comment like_count
create or replace function update_comment_like_count()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    update public.comments
    set like_count = like_count + 1
    where id = NEW.comment_id;
    return NEW;
  elsif TG_OP = 'DELETE' then
    update public.comments
    set like_count = like_count - 1
    where id = OLD.comment_id;
    return OLD;
  end if;
  return null;
end;
$$ language plpgsql;

-- Trigger to update like_count when comment_likes are added/deleted
drop trigger if exists update_comment_like_count_trigger on public.comment_likes;
create trigger update_comment_like_count_trigger
  after insert or delete on public.comment_likes
  for each row execute function update_comment_like_count();

-- Function to update post updated_at
create or replace function update_post_updated_at()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;

-- Trigger to update updated_at when post is updated
drop trigger if exists update_post_updated_at_trigger on public.posts;
create trigger update_post_updated_at_trigger
  before update on public.posts
  for each row execute function update_post_updated_at();

-- Function to update comment updated_at
create or replace function update_comment_updated_at()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;

-- Trigger to update updated_at when comment is updated
drop trigger if exists update_comment_updated_at_trigger on public.comments;
create trigger update_comment_updated_at_trigger
  before update on public.comments
  for each row execute function update_comment_updated_at();

-- Update profiles policy to allow reading other users' profiles for display
-- Only update if the table exists
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'profiles') then
    -- Drop old policy if it exists
    drop policy if exists "profiles_select_own" on public.profiles;
    
    -- Create new policy if it doesn't exist
    if not exists (
      select 1 from pg_policies 
      where schemaname = 'public' 
      and tablename = 'profiles' 
      and policyname = 'profiles_select_all'
    ) then
      create policy "profiles_select_all"
        on public.profiles for select
        using (true);
    end if;
  end if;
end $$;

