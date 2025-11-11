-- Add missing login-related fields to profiles table

-- Ensure wechat_openid exists (in case previous migration wasn't run)
alter table public.profiles add column if not exists wechat_openid text;

-- Ensure phone exists (in case previous migration wasn't run)
alter table public.profiles add column if not exists phone text;

-- Add wechat_unionid (微信 unionid，用于跨应用识别同一用户)
alter table public.profiles add column if not exists wechat_unionid text;

-- Add updated_at timestamp for tracking record updates
alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Create function to automatically update updated_at timestamp
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

-- Sync existing wechat_unionid from auth.users to profiles
update public.profiles p
set wechat_unionid = (
  select au.raw_user_meta_data->>'wechat_unionid'
  from auth.users au
  where au.id = p.id
  and au.raw_user_meta_data->>'wechat_unionid' is not null
)
where exists (
  select 1
  from auth.users au
  where au.id = p.id
  and au.raw_user_meta_data->>'wechat_unionid' is not null
);

-- Create index on wechat_openid for faster lookups
create index if not exists idx_profiles_wechat_openid on public.profiles(wechat_openid) where wechat_openid is not null;

-- Create index on wechat_unionid for faster lookups
create index if not exists idx_profiles_wechat_unionid on public.profiles(wechat_unionid) where wechat_unionid is not null;

-- Create index on phone for faster lookups
create index if not exists idx_profiles_phone on public.profiles(phone) where phone is not null;

