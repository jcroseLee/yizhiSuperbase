-- Masters table for divination masters (卦师)
create table if not exists public.masters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade unique not null,
  name text not null,
  title text,
  certification text default '实名认证',
  rating numeric(3, 2) default 0,
  reviews_count integer default 0,
  experience_years integer default 0,
  expertise text[] default '{}',
  avatar_url text,
  highlight text,
  description text,
  achievements text[] default '{}',
  service_types text[] default '{}',
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.masters enable row level security;

-- Create masters policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'masters' 
    and policyname = 'masters_select_all'
  ) then
    create policy "masters_select_all"
      on public.masters for select
      using (is_active = true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'masters' 
    and policyname = 'masters_select_own'
  ) then
    create policy "masters_select_own"
      on public.masters for select
      using (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'masters' 
    and policyname = 'masters_insert_own'
  ) then
    create policy "masters_insert_own"
      on public.masters for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'masters' 
    and policyname = 'masters_update_own'
  ) then
    create policy "masters_update_own"
      on public.masters for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

-- Function to update updated_at
create or replace function update_master_updated_at()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;

-- Trigger to update updated_at when master is updated
drop trigger if exists update_master_updated_at_trigger on public.masters;
create trigger update_master_updated_at_trigger
  before update on public.masters
  for each row execute function update_master_updated_at();

-- Master reviews table
create table if not exists public.master_reviews (
  id uuid primary key default gen_random_uuid(),
  master_id uuid references public.masters(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  rating integer not null check (rating >= 1 and rating <= 5),
  content text,
  tags text[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(master_id, user_id)
);

alter table public.master_reviews enable row level security;

-- Create master_reviews policies if they don't exist
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'master_reviews' 
    and policyname = 'master_reviews_select_all'
  ) then
    create policy "master_reviews_select_all"
      on public.master_reviews for select
      using (true);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'master_reviews' 
    and policyname = 'master_reviews_insert_own'
  ) then
    create policy "master_reviews_insert_own"
      on public.master_reviews for insert
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'master_reviews' 
    and policyname = 'master_reviews_update_own'
  ) then
    create policy "master_reviews_update_own"
      on public.master_reviews for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'master_reviews' 
    and policyname = 'master_reviews_delete_own'
  ) then
    create policy "master_reviews_delete_own"
      on public.master_reviews for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- Function to update master rating and reviews_count
create or replace function update_master_stats()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    update public.masters
    set 
      rating = (
        select coalesce(avg(rating)::numeric(3,2), 0)
        from public.master_reviews
        where master_id = NEW.master_id
      ),
      reviews_count = (
        select count(*)
        from public.master_reviews
        where master_id = NEW.master_id
      )
    where id = NEW.master_id;
    return NEW;
  elsif TG_OP = 'UPDATE' then
    update public.masters
    set 
      rating = (
        select coalesce(avg(rating)::numeric(3,2), 0)
        from public.master_reviews
        where master_id = NEW.master_id
      )
    where id = NEW.master_id;
    return NEW;
  elsif TG_OP = 'DELETE' then
    update public.masters
    set 
      rating = (
        select coalesce(avg(rating)::numeric(3,2), 0)
        from public.master_reviews
        where master_id = OLD.master_id
      ),
      reviews_count = (
        select count(*)
        from public.master_reviews
        where master_id = OLD.master_id
      )
    where id = OLD.master_id;
    return OLD;
  end if;
  return null;
end;
$$ language plpgsql;

-- Trigger to update master stats when reviews change
drop trigger if exists update_master_stats_trigger on public.master_reviews;
create trigger update_master_stats_trigger
  after insert or update or delete on public.master_reviews
  for each row execute function update_master_stats();

-- Function to update review updated_at
create or replace function update_master_review_updated_at()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;

-- Trigger to update updated_at when review is updated
drop trigger if exists update_master_review_updated_at_trigger on public.master_reviews;
create trigger update_master_review_updated_at_trigger
  before update on public.master_reviews
  for each row execute function update_master_review_updated_at();

