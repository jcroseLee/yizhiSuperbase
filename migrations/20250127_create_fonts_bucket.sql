-- Create fonts storage bucket
-- Fonts are static assets that should be publicly accessible
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fonts',
  'fonts',
  true,
  10485760, -- 10MB limit (fonts can be larger)
  ARRAY['font/woff', 'font/woff2', 'application/font-woff', 'application/font-woff2']
)
on conflict (id) do nothing;

-- Storage policies for fonts bucket
-- Drop existing policies if they exist (to allow re-running this migration)
drop policy if exists "fonts_upload_public" on storage.objects;
drop policy if exists "fonts_update_public" on storage.objects;
drop policy if exists "fonts_delete_public" on storage.objects;
drop policy if exists "fonts_select_public" on storage.objects;

-- Allow authenticated users (admins) to upload fonts
-- In production, you might want to restrict this to service role only
create policy "fonts_upload_public"
on storage.objects for insert
with check (
  bucket_id = 'fonts' 
  and auth.role() = 'authenticated'
);

-- Allow authenticated users to update fonts
create policy "fonts_update_public"
on storage.objects for update
using (
  bucket_id = 'fonts' 
  and auth.role() = 'authenticated'
)
with check (
  bucket_id = 'fonts' 
  and auth.role() = 'authenticated'
);

-- Allow authenticated users to delete fonts
create policy "fonts_delete_public"
on storage.objects for delete
using (
  bucket_id = 'fonts' 
  and auth.role() = 'authenticated'
);

-- Allow public read access (fonts are static assets)
create policy "fonts_select_public"
on storage.objects for select
using (bucket_id = 'fonts');

