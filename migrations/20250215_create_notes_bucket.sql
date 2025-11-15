-- Create notes storage bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'notes',
  'notes',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do nothing;

-- Storage policies for notes bucket
-- Drop existing policies if they exist (to allow re-running this migration)
drop policy if exists "notes_upload_own" on storage.objects;
drop policy if exists "notes_update_own" on storage.objects;
drop policy if exists "notes_delete_own" on storage.objects;
drop policy if exists "notes_select_public" on storage.objects;

-- Allow authenticated users to upload their own notes images
-- File path format: {userId}/{recordId}/{timestamp}.jpg
-- PostgreSQL array index starts at 1, so [1] is the first folder (userId)
create policy "notes_upload_own"
on storage.objects for insert
with check (
  bucket_id = 'notes' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to update their own notes images
create policy "notes_update_own"
on storage.objects for update
using (
  bucket_id = 'notes' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'notes' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to delete their own notes images
create policy "notes_delete_own"
on storage.objects for delete
using (
  bucket_id = 'notes' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read access (since bucket is public)
create policy "notes_select_public"
on storage.objects for select
using (bucket_id = 'notes');

