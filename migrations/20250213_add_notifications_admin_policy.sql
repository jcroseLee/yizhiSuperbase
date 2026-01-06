-- Add admin policy for notifications to allow admins to insert system messages
-- This allows CMS admins to send system notifications to users

do $$
begin
  -- Allow admins to insert notifications (for system messages)
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'notifications' 
    and policyname = 'notifications_admin_insert'
  ) then
    create policy "notifications_admin_insert"
      on public.notifications for insert
      with check (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;
  
  -- Allow admins to select all notifications (for viewing system messages in CMS)
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'notifications' 
    and policyname = 'notifications_admin_select'
  ) then
    create policy "notifications_admin_select"
      on public.notifications for select
      using (
        exists (
          select 1 from public.profiles
          where profiles.id = auth.uid()
          and profiles.role = 'admin'
        )
      );
  end if;
end $$;

