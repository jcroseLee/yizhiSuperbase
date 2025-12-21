-- Set default nickname and avatar for first-time login users
-- Default nickname format: '易知用户001', '易知用户002', etc.
-- Numbers are assigned based on user creation time (created_at)

-- Function to get the next available default nickname number
-- This function finds the highest number used in '易知用户XXX' format and returns the next one
create or replace function public.get_next_default_nickname_number()
returns integer as $$
declare
  max_number integer;
  next_number integer;
begin
  -- Find the maximum number used in default nicknames
  -- Extract number from nickname like '易知用户001', '易知用户002', etc.
  select coalesce(
    max(
      case 
        when nickname ~ '^易知用户[0-9]+$' then
          cast(substring(nickname from '易知用户([0-9]+)$') as integer)
        else 0
      end
    ), 0
  ) into max_number
  from public.profiles
  where nickname ~ '^易知用户[0-9]+$';
  
  -- Return the next number
  next_number := max_number + 1;
  
  return next_number;
end;
$$ language plpgsql security definer;

-- Function to generate default nickname
create or replace function public.generate_default_nickname()
returns text as $$
declare
  next_number integer;
  formatted_number text;
begin
  next_number := public.get_next_default_nickname_number();
  -- Format number with leading zeros (001, 002, etc.)
  formatted_number := lpad(next_number::text, 3, '0');
  return '易知用户' || formatted_number;
end;
$$ language plpgsql security definer;

-- Function to get default avatar URL
-- You can customize this URL to point to your default avatar image
create or replace function public.get_default_avatar_url()
returns text as $$
begin
  -- Return a default avatar URL
  -- You can change this to your actual default avatar URL
  return 'https://api.dicebear.com/7.x/avataaars/svg?seed=易知用户';
end;
$$ language plpgsql security definer;

-- Function to ensure user has default nickname and avatar if missing
create or replace function public.ensure_default_profile_fields(user_id uuid)
returns void as $$
declare
  current_profile record;
  default_nickname text;
  default_avatar text;
  needs_update boolean := false;
begin
  -- Get current profile
  select nickname, avatar_url into current_profile
  from public.profiles
  where id = user_id;
  
  -- If profile doesn't exist, return (should be created by trigger)
  if not found then
    return;
  end if;
  
  -- Check if nickname needs to be set
  if current_profile.nickname is null or current_profile.nickname = '' then
    default_nickname := public.generate_default_nickname();
    needs_update := true;
  else
    default_nickname := current_profile.nickname;
  end if;
  
  -- Check if avatar needs to be set
  if current_profile.avatar_url is null or current_profile.avatar_url = '' then
    default_avatar := public.get_default_avatar_url();
    needs_update := true;
  else
    default_avatar := current_profile.avatar_url;
  end if;
  
  -- Update profile if needed
  if needs_update then
    update public.profiles
    set 
      nickname = default_nickname,
      avatar_url = default_avatar,
      updated_at = now()
    where id = user_id;
  end if;
end;
$$ language plpgsql security definer;

-- Update the handle_new_user trigger to use default nickname and avatar
create or replace function public.handle_new_user()
returns trigger as $$
declare
  default_nickname text;
  default_avatar text;
begin
  -- Use provided nickname from metadata if available
  if new.raw_user_meta_data->>'nickname' is not null 
     and new.raw_user_meta_data->>'nickname' != '' then
    default_nickname := new.raw_user_meta_data->>'nickname';
  else
    -- Generate default nickname: '易知用户001', '易知用户002', etc.
    default_nickname := public.generate_default_nickname();
  end if;
  
  -- Use provided avatar from metadata if available
  if new.raw_user_meta_data->>'avatar_url' is not null 
     and new.raw_user_meta_data->>'avatar_url' != '' then
    default_avatar := new.raw_user_meta_data->>'avatar_url';
  else
    -- Use default avatar
    default_avatar := public.get_default_avatar_url();
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
    email,
    created_at
  )
  values (
    new.id,
    default_nickname,
    default_avatar,
    'user',
    coalesce(new.raw_user_meta_data->>'wechat_openid', null),
    coalesce(new.raw_user_meta_data->>'wechat_unionid', null),
    coalesce(new.phone, null),
    coalesce(new.email, null),
    new.created_at
  )
  on conflict (id) do nothing;

  return new;
end;
$$ language plpgsql security definer;

-- Create function to update last_login_at and ensure default fields
-- This should be called when user logs in
create or replace function public.on_user_login(user_id uuid)
returns void as $$
begin
  -- Update last_login_at
  update public.profiles
  set last_login_at = now()
  where id = user_id;
  
  -- Ensure default nickname and avatar are set
  perform public.ensure_default_profile_fields(user_id);
end;
$$ language plpgsql security definer;

-- Grant execute permissions
grant execute on function public.get_next_default_nickname_number() to authenticated, anon;
grant execute on function public.generate_default_nickname() to authenticated, anon;
grant execute on function public.get_default_avatar_url() to authenticated, anon;
grant execute on function public.ensure_default_profile_fields(uuid) to authenticated, anon;
grant execute on function public.on_user_login(uuid) to authenticated, anon;

-- Add comments for documentation
comment on function public.get_next_default_nickname_number() is 'Gets the next available number for default nickname (易知用户XXX)';
comment on function public.generate_default_nickname() is 'Generates a default nickname in format 易知用户001, 易知用户002, etc.';
comment on function public.get_default_avatar_url() is 'Returns the default avatar URL for new users';
comment on function public.ensure_default_profile_fields(uuid) is 'Ensures user has default nickname and avatar if missing';
comment on function public.on_user_login(uuid) is 'Updates last_login_at and ensures default profile fields are set';

-- Update existing users who don't have nickname or avatar
-- This will assign default nicknames based on their creation time
do $$
declare
  user_record record;
  default_nickname text;
  default_avatar text;
  user_count integer := 0;
  current_number integer;
  max_existing_number integer;
begin
  -- Find the maximum number already used in default nicknames
  select coalesce(
    max(
      case 
        when nickname ~ '^易知用户[0-9]+$' then
          cast(substring(nickname from '易知用户([0-9]+)$') as integer)
        else 0
      end
    ), 0
  ) into max_existing_number
  from public.profiles
  where nickname ~ '^易知用户[0-9]+$';
  
  current_number := max_existing_number;
  
  -- Process users without nickname or avatar, ordered by created_at
  -- This ensures users get numbers based on their creation time
  for user_record in 
    select id, nickname, avatar_url, created_at
    from public.profiles
    where (nickname is null or nickname = '' or avatar_url is null or avatar_url = '')
      -- Don't update users who already have a custom nickname (not default format)
      and (nickname is null or nickname = '' or nickname ~ '^易知用户[0-9]+$')
    order by created_at asc
  loop
    -- Generate default nickname if missing
    if user_record.nickname is null or user_record.nickname = '' then
      current_number := current_number + 1;
      default_nickname := '易知用户' || lpad(current_number::text, 3, '0');
    else
      -- Keep existing nickname if it's already in default format
      default_nickname := user_record.nickname;
    end if;
    
    -- Set default avatar if missing
    if user_record.avatar_url is null or user_record.avatar_url = '' then
      default_avatar := public.get_default_avatar_url();
    else
      default_avatar := user_record.avatar_url;
    end if;
    
    -- Update the profile
    update public.profiles
    set 
      nickname = default_nickname,
      avatar_url = default_avatar,
      updated_at = now()
    where id = user_record.id;
    
    user_count := user_count + 1;
  end loop;
  
  raise notice 'Updated % users with default nickname and avatar', user_count;
end $$;

