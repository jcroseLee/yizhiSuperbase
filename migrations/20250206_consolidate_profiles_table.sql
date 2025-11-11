-- Consolidate profiles table structure
-- This migration ensures the profiles table has all necessary fields
-- and removes any references to users_profiles (which doesn't exist as a table)

-- Ensure all columns exist in profiles table
alter table public.profiles add column if not exists wechat_openid text;
alter table public.profiles add column if not exists wechat_unionid text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Create or replace function to automatically update updated_at timestamp
create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Create trigger to automatically update updated_at
drop trigger if exists update_profiles_updated_at on public.profiles;
create trigger update_profiles_updated_at
  before update on public.profiles
  for each row
  execute function public.update_updated_at_column();

-- Create indexes for faster lookups
create index if not exists idx_profiles_wechat_openid on public.profiles(wechat_openid) where wechat_openid is not null;
create index if not exists idx_profiles_wechat_unionid on public.profiles(wechat_unionid) where wechat_unionid is not null;
create index if not exists idx_profiles_phone on public.profiles(phone) where phone is not null;

-- Ensure all auth.users have corresponding profiles
-- This syncs any missing profiles from auth.users
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
select 
  au.id,
  coalesce(au.raw_user_meta_data->>'nickname', '用户') as nickname,
  au.raw_user_meta_data->>'avatar_url' as avatar_url,
  'user' as role,
  au.raw_user_meta_data->>'wechat_openid' as wechat_openid,
  au.raw_user_meta_data->>'wechat_unionid' as wechat_unionid,
  au.phone,
  au.created_at
from auth.users au
where au.id not in (select id from public.profiles)
on conflict (id) do nothing;

-- Sync existing profiles with auth.users data
update public.profiles p
set
  phone = coalesce(p.phone, au.phone),
  wechat_openid = coalesce(p.wechat_openid, au.raw_user_meta_data->>'wechat_openid'),
  wechat_unionid = coalesce(p.wechat_unionid, au.raw_user_meta_data->>'wechat_unionid'),
  nickname = coalesce(p.nickname, au.raw_user_meta_data->>'nickname', '用户'),
  avatar_url = coalesce(p.avatar_url, au.raw_user_meta_data->>'avatar_url'),
  updated_at = now()
from auth.users au
where p.id = au.id
  and (
    p.phone is distinct from au.phone
    or p.wechat_openid is distinct from (au.raw_user_meta_data->>'wechat_openid')
    or p.wechat_unionid is distinct from (au.raw_user_meta_data->>'wechat_unionid')
    or p.nickname is distinct from coalesce(au.raw_user_meta_data->>'nickname', '用户')
    or p.avatar_url is distinct from (au.raw_user_meta_data->>'avatar_url')
  );

-- Note: The user_profiles_view was already removed in migration 20250205_remove_user_profiles_view.sql
-- All code should use the profiles table directly

