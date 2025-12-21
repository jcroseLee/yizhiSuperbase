-- Function to create notification when user is followed
create or replace function public.create_follow_notification()
returns trigger as $$
declare
  follower_id uuid;
  following_id uuid;
begin
  -- Get follower and following IDs
  follower_id := NEW.follower_id;
  following_id := NEW.following_id;
  
  -- Don't notify if user is following themselves (shouldn't happen due to CHECK constraint, but just in case)
  if follower_id is not null and following_id is not null and follower_id != following_id then
    insert into public.notifications (
      user_id,
      type,
      related_id,
      related_type,
      actor_id,
      content,
      metadata
    ) values (
      following_id, -- Notify the user who is being followed
      'follow',
      following_id, -- related_id is the user being followed
      'user', -- related_type is 'user' for follow notifications
      follower_id, -- actor_id is the user who followed
      null,
      jsonb_build_object(
        'follower_id', follower_id,
        'following_id', following_id
      )
    )
    on conflict do nothing; -- Avoid duplicate notifications if function is called multiple times
  end if;
  
  return NEW;
end;
$$ language plpgsql security definer;

-- Trigger for follow notifications
drop trigger if exists trigger_create_follow_notification on public.user_follows;
create trigger trigger_create_follow_notification
  after insert on public.user_follows
  for each row
  execute function public.create_follow_notification();

-- Comment
comment on function public.create_follow_notification() is 'Creates a notification when a user is followed';

