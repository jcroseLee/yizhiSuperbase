-- Create posts storage bucket for post images
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'posts',
  'posts',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do nothing;

-- Storage policies for posts bucket
-- Drop existing policies if they exist (to allow re-running this migration)
drop policy if exists "posts_upload_own" on storage.objects;
drop policy if exists "posts_update_own" on storage.objects;
drop policy if exists "posts_delete_own" on storage.objects;
drop policy if exists "posts_select_public" on storage.objects;

-- Allow authenticated users to upload their own post images
-- Files should be in the format: {user_id}/{filename} (first folder must be user ID)
create policy "posts_upload_own"
on storage.objects for insert
with check (
  bucket_id = 'posts' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to update their own post images
create policy "posts_update_own"
on storage.objects for update
using (
  bucket_id = 'posts' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'posts' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to delete their own post images
create policy "posts_delete_own"
on storage.objects for delete
using (
  bucket_id = 'posts' 
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read access (since bucket is public)
create policy "posts_select_public"
on storage.objects for select
using (bucket_id = 'posts');

