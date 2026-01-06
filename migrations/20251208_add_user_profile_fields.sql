-- Add comprehensive user profile fields to profiles table
-- This migration adds all user-related fields as requested

-- Add username field (unique identifier for users, different from nickname)
alter table public.profiles add column if not exists username text;

-- Add email field (user email address)
alter table public.profiles add column if not exists email text;

-- Add password_hash field (hashed password, though typically stored in auth.users)
alter table public.profiles add column if not exists password_hash text;

-- Add level field (user level from 1 to 10)
alter table public.profiles add column if not exists level smallint default 1;

-- Add check constraint for level field (1-10)
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'profiles_level_check'
  ) then
    alter table public.profiles add constraint profiles_level_check check (level >= 1 and level <= 10);
  end if;
end $$;

-- Add reputation field (user reputation points)
alter table public.profiles add column if not exists reputation integer default 0;

-- Add total_coins field (total coins/易币 balance)
alter table public.profiles add column if not exists total_coins bigint default 0;

-- Add is_certified_master field (whether user is a certified divination master)
alter table public.profiles add column if not exists is_certified_master boolean default false;

-- Add last_login_at field (last login timestamp)
alter table public.profiles add column if not exists last_login_at timestamptz;

-- Create unique index on username for faster lookups and uniqueness
create unique index if not exists idx_profiles_username_unique on public.profiles(username) where username is not null;

-- Create index on email for faster lookups
create index if not exists idx_profiles_email on public.profiles(email) where email is not null;

-- Create index on level for faster queries
create index if not exists idx_profiles_level on public.profiles(level);

-- Create index on reputation for sorting/ranking
create index if not exists idx_profiles_reputation on public.profiles(reputation desc);

-- Create index on is_certified_master for filtering certified masters
create index if not exists idx_profiles_is_certified_master on public.profiles(is_certified_master) where is_certified_master = true;

-- Create index on last_login_at for recent activity queries
create index if not exists idx_profiles_last_login_at on public.profiles(last_login_at desc) where last_login_at is not null;

-- Sync email from auth.users to profiles if not already set
update public.profiles p
set email = au.email
from auth.users au
where p.id = au.id
  and p.email is null
  and au.email is not null;

-- Add comments to columns for documentation
comment on column public.profiles.username is 'Unique username identifier for the user';
comment on column public.profiles.email is 'User email address';
comment on column public.profiles.password_hash is 'Hashed password (typically managed by auth.users)';
comment on column public.profiles.level is 'User level from 1 to 10';
comment on column public.profiles.reputation is 'User reputation points';
comment on column public.profiles.total_coins is 'Total coins/易币 balance';
comment on column public.profiles.is_certified_master is 'Whether the user is a certified divination master';
comment on column public.profiles.last_login_at is 'Last login timestamp';

