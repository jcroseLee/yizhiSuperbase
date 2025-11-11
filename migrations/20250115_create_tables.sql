-- Profiles table mirrors auth.users via 1:1 relationship
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  avatar_url text,
  role text default 'user',
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Main divination record store
create table if not exists public.divination_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  question text,
  divination_time timestamptz not null default now(),
  method smallint not null,
  lines text[] not null,
  changing_flags boolean[] not null,
  original_key text not null,
  changed_key text not null,
  original_json jsonb not null,
  changed_json jsonb not null,
  created_at timestamptz default now()
);

alter table public.divination_records enable row level security;

create policy "records_select_own"
  on public.divination_records for select
  using (auth.uid() = user_id);

create policy "records_insert_own"
  on public.divination_records for insert
  with check (auth.uid() = user_id);

create policy "records_update_own"
  on public.divination_records for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "records_delete_own"
  on public.divination_records for delete
  using (auth.uid() = user_id);

-- Favorites allow users to bookmark particular records
create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  record_id uuid references public.divination_records(id) on delete cascade,
  created_at timestamptz default now(),
  unique (user_id, record_id)
);

alter table public.favorites enable row level security;

create policy "favorites_select_own"
  on public.favorites for select
  using (auth.uid() = user_id);

create policy "favorites_insert_own"
  on public.favorites for insert
  with check (auth.uid() = user_id);

create policy "favorites_delete_own"
  on public.favorites for delete
  using (auth.uid() = user_id);

-- Membership tiers for premium experiences
create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  level text not null,
  started_at timestamptz not null default now(),
  expire_at timestamptz,
  status text default 'active'
);

alter table public.memberships enable row level security;

create policy "memberships_select_own"
  on public.memberships for select
  using (auth.uid() = user_id);

create policy "memberships_insert_own"
  on public.memberships for insert
  with check (auth.uid() = user_id);

create policy "memberships_update_admin"
  on public.memberships for update
  using (auth.jwt()->>'role' = 'admin')
  with check (auth.jwt()->>'role' = 'admin');