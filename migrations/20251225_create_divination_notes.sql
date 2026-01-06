
-- Create divination_notes table for multiple notes per record
create table if not exists public.divination_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  divination_record_id uuid references public.divination_records(id) on delete cascade not null,
  content text not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Enable RLS
alter table public.divination_notes enable row level security;

-- Policies
create policy "Users can view their own notes"
  on public.divination_notes for select
  using (auth.uid() = user_id);

create policy "Users can create their own notes"
  on public.divination_notes for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own notes"
  on public.divination_notes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own notes"
  on public.divination_notes for delete
  using (auth.uid() = user_id);

-- Index for faster queries
create index if not exists idx_divination_notes_record_id on public.divination_notes(divination_record_id);
create index if not exists idx_divination_notes_user_id on public.divination_notes(user_id);

-- Add trigger for updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_updated_at
  before update on public.divination_notes
  for each row
  execute procedure public.handle_updated_at();
