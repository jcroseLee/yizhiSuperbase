-- Auto-create profiles trigger when new user signs up
-- This trigger automatically creates a profile record when a new user is created in auth.users

-- Function to handle new user creation and create corresponding profile
create or replace function public.handle_new_user()
returns trigger as $$
declare
  default_nickname text;
begin
  -- Generate a default nickname from email if not provided
  if new.raw_user_meta_data->>'nickname' is not null then
    default_nickname := new.raw_user_meta_data->>'nickname';
  elsif new.email is not null then
    -- Extract username from email (part before @)
    default_nickname := split_part(new.email, '@', 1) || '_' || substring(new.id::text, 1, 8);
  else
    default_nickname := '用户_' || substring(new.id::text, 1, 8);
  end if;

  -- Insert new profile for the user
  insert into public.profiles (
    id,
    nickname,
    avatar_url,
    role,
    wechat_openid,
    wechat_unionid,
    phone,
    created_at
  )
  values (
    new.id,
    default_nickname,
    coalesce(new.raw_user_meta_data->>'avatar_url', null),
    'user',
    coalesce(new.raw_user_meta_data->>'wechat_openid', null),
    coalesce(new.raw_user_meta_data->>'wechat_unionid', null),
    coalesce(new.phone, null),
    new.created_at
  )
  on conflict (id) do nothing;

  return new;
end;
$$ language plpgsql security definer;

-- Drop trigger if exists and create new one
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- Grant execute permission to authenticated users
grant usage on schema public to authenticated;
grant execute on function public.handle_new_user() to authenticated;

