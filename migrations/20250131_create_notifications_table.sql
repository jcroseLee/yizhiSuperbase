-- Notifications table for system notifications (likes, comments, etc.)
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  type text not null, -- 'comment', 'like', 'reply', etc.
  related_id uuid not null, -- post_id or comment_id depending on type
  related_type text not null, -- 'post', 'comment' to indicate what related_id refers to
  actor_id uuid references auth.users(id) on delete cascade, -- user who triggered the notification
  content text, -- notification message/content
  metadata jsonb, -- additional data like post title, comment preview, etc.
  is_read boolean default false,
  created_at timestamptz default now()
);

-- Create index for efficient querying
create index if not exists idx_notifications_user_id on public.notifications(user_id);
create index if not exists idx_notifications_user_unread on public.notifications(user_id, is_read) where is_read = false;
create index if not exists idx_notifications_created_at on public.notifications(created_at desc);

alter table public.notifications enable row level security;

-- Create notifications policies
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'notifications' 
    and policyname = 'notifications_select_own'
  ) then
    create policy "notifications_select_own"
      on public.notifications for select
      using (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'notifications' 
    and policyname = 'notifications_update_own'
  ) then
    create policy "notifications_update_own"
      on public.notifications for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'notifications' 
    and policyname = 'notifications_insert_service'
  ) then
    -- Allow service role to insert notifications (via Edge Function or trigger)
    create policy "notifications_insert_service"
      on public.notifications for insert
      with check (true); -- This will be restricted by RLS, but allows backend functions to insert
  end if;
end $$;

-- Function to create notification when comment is created
create or replace function public.create_comment_notification()
returns trigger as $$
declare
  post_owner_id uuid;
  commenter_id uuid;
  parent_comment_user_id uuid;
  target_user_id uuid;
begin
  -- Get commenter
  commenter_id := NEW.user_id;
  
  -- If this is a reply to another comment
  if NEW.parent_id is not null then
    -- Get the parent comment's author
    select user_id into parent_comment_user_id
    from public.comments
    where id = NEW.parent_id;
    
    -- Notify the parent comment's author (if not replying to yourself)
    if parent_comment_user_id is not null and parent_comment_user_id != commenter_id then
      insert into public.notifications (
        user_id,
        type,
        related_id,
        related_type,
        actor_id,
        content,
        metadata
      ) values (
        parent_comment_user_id,
        'reply',
        NEW.post_id,
        'post',
        commenter_id,
        null,
        jsonb_build_object(
          'post_id', NEW.post_id,
          'comment_id', NEW.id,
          'parent_comment_id', NEW.parent_id,
          'comment_content', left(NEW.content, 100)
        )
      );
    end if;
  else
    -- This is a top-level comment, notify the post owner
    select user_id into post_owner_id
    from public.posts
    where id = NEW.post_id;
    
    -- Don't notify if user is commenting on their own post
    if post_owner_id is not null and post_owner_id != commenter_id then
      insert into public.notifications (
        user_id,
        type,
        related_id,
        related_type,
        actor_id,
        content,
        metadata
      ) values (
        post_owner_id,
        'comment',
        NEW.post_id,
        'post',
        commenter_id,
        null,
        jsonb_build_object(
          'post_id', NEW.post_id,
          'comment_id', NEW.id,
          'comment_content', left(NEW.content, 100)
        )
      );
    end if;
  end if;
  
  return NEW;
end;
$$ language plpgsql security definer;

-- Trigger for comment notifications
drop trigger if exists trigger_create_comment_notification on public.comments;
create trigger trigger_create_comment_notification
  after insert on public.comments
  for each row
  execute function public.create_comment_notification();

-- Function to create notification when post is liked
create or replace function public.create_like_notification()
returns trigger as $$
declare
  post_owner_id uuid;
  liker_id uuid;
begin
  -- Get post owner
  select user_id into post_owner_id
  from public.posts
  where id = NEW.post_id;
  
  -- Get liker
  liker_id := NEW.user_id;
  
  -- Don't notify if user is liking their own post
  if post_owner_id is not null and post_owner_id != liker_id then
    insert into public.notifications (
      user_id,
      type,
      related_id,
      related_type,
      actor_id,
      content,
      metadata
    ) values (
      post_owner_id,
      'like',
      NEW.post_id,
      'post',
      liker_id,
      null,
      jsonb_build_object('post_id', NEW.post_id)
    )
    on conflict do nothing; -- Avoid duplicate notifications if function is called multiple times
  end if;
  
  return NEW;
end;
$$ language plpgsql security definer;

-- Trigger for like notifications
drop trigger if exists trigger_create_like_notification on public.post_likes;
create trigger trigger_create_like_notification
  after insert on public.post_likes
  for each row
  execute function public.create_like_notification();

-- Comment: Add helpful comments
comment on table public.notifications is 'System notifications for users (likes, comments, replies)';
comment on column public.notifications.type is 'Type of notification: comment, like, reply';
comment on column public.notifications.related_type is 'Type of related entity: post, comment';
comment on column public.notifications.metadata is 'Additional JSON data about the notification';

