-- Add phone column to profiles table
alter table public.profiles add column if not exists phone text;

-- Create a function to sync phone from auth.users to profiles
create or replace function public.sync_user_phone()
returns trigger as $$
begin
  -- Update profiles table when phone is updated in auth.users
  update public.profiles
  set phone = new.phone
  where id = new.id;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger to automatically sync phone from auth.users to profiles
-- Note: This trigger needs to be created in the auth schema
-- We'll handle this manually in the Edge Functions instead

-- Sync existing phone numbers from auth.users to profiles
update public.profiles p
set phone = (
  select au.phone
  from auth.users au
  where au.id = p.id
)
where exists (
  select 1
  from auth.users au
  where au.id = p.id
  and au.phone is not null
);

