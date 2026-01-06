-- Modules table for feature module management
create table if not exists public.modules (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  display_name text not null,
  description text,
  is_enabled boolean default true,
  order_index integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.modules enable row level security;

-- Create modules policies if they don't exist
do $$
begin
  -- Allow all authenticated users to read modules
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'modules' 
    and policyname = 'modules_select_all'
  ) then
    create policy "modules_select_all"
      on public.modules for select
      using (true);
  end if;

  -- Only admins can manage modules
  if not exists (
    select 1 from pg_policies 
    where schemaname = 'public' 
    and tablename = 'modules' 
    and policyname = 'modules_admin_all'
  ) then
    create policy "modules_admin_all"
      on public.modules for all
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
end $$;

-- Function to update updated_at
create or replace function update_module_updated_at()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;

-- Trigger to update updated_at when module is updated
drop trigger if exists update_module_updated_at_trigger on public.modules;
create trigger update_module_updated_at_trigger
  before update on public.modules
  for each row execute function update_module_updated_at();

-- Insert default modules
insert into public.modules (name, display_name, description, is_enabled, order_index) values
  ('divination', '推演功能', '六爻推演核心功能', true, 1),
  ('community', '社区功能', '论坛社区功能', true, 2),
  ('masters', '卦师功能', '卦师展示和预约功能', true, 3),
  ('messages', '消息功能', '用户消息功能', true, 4),
  ('records', '记录功能', '推演记录查看功能', true, 5)
on conflict (name) do nothing;

