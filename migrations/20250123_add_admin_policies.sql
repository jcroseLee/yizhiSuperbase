-- Add admin policies for CMS management
-- Allow admins to manage all data

-- Create admin policies if they don't exist
do $$
begin
  -- Masters admin policies
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'masters' 
    and policyname = 'masters_admin_all'
  ) then
    create policy "masters_admin_all"
      on public.masters for all
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      )
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;

  -- Posts admin policies
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'posts' 
    and policyname = 'posts_admin_all'
  ) then
    create policy "posts_admin_all"
      on public.posts for all
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      )
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;

  -- Comments admin policies
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'comments' 
    and policyname = 'comments_admin_all'
  ) then
    create policy "comments_admin_all"
      on public.comments for all
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      )
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;

  -- Divination records admin policies
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'divination_records' 
    and policyname = 'records_admin_all'
  ) then
    create policy "records_admin_all"
      on public.divination_records for all
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      )
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;

  -- Master reviews admin policies
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'master_reviews' 
    and policyname = 'master_reviews_admin_all'
  ) then
    create policy "master_reviews_admin_all"
      on public.master_reviews for all
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      )
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;

  -- Profiles admin read policy (admins can read all profiles)
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'profiles' 
    and policyname = 'profiles_admin_select_all'
  ) then
    create policy "profiles_admin_select_all"
      on public.profiles for select
      using (
        exists (
          select 1 from public.profiles p
          where p.id = auth.uid()
          and p.role = 'admin'
        )
      );
  end if;
end $$;

