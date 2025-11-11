-- Fix profiles policies to avoid recursive checks and ensure users can read their own profile
-- This migration fixes the 500 error when querying profiles

-- Drop the problematic recursive admin policy
drop policy if exists "profiles_admin_select_all" on public.profiles;

-- Ensure users can always read their own profile
-- This policy should already exist, but we ensure it's there
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
end $$;

-- Create a better admin policy that doesn't cause recursion
-- Admins can read all profiles, but we use a security definer function to avoid recursion
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
    and role = 'admin'
  );
$$;

-- Now create the admin policy using the function
create policy "profiles_admin_select_all"
  on public.profiles for select
  using (public.is_admin());

-- Also ensure users can insert their own profile (for auto-creation)
do $$
begin
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
end $$;

-- Ensure users can update their own profile
do $$
begin
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

