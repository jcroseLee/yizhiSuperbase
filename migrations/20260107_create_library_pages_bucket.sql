insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'library_pages',
  'library_pages',
  true,
  5242880,
  ARRAY['image/webp', 'image/jpeg', 'image/png', 'application/json']
)
on conflict (id) do nothing;

drop policy if exists "library_pages_select_public" on storage.objects;

create policy "library_pages_select_public"
on storage.objects for select
using (bucket_id = 'library_pages');

drop policy if exists "library_pages_upload_auth" on storage.objects;
drop policy if exists "library_pages_update_auth" on storage.objects;
drop policy if exists "library_pages_delete_auth" on storage.objects;

create policy "library_pages_upload_auth"
on storage.objects for insert
with check (
  bucket_id = 'library_pages'
  and auth.role() = 'authenticated'
);

create policy "library_pages_update_auth"
on storage.objects for update
using (
  bucket_id = 'library_pages'
  and auth.role() = 'authenticated'
)
with check (
  bucket_id = 'library_pages'
  and auth.role() = 'authenticated'
);

create policy "library_pages_delete_auth"
on storage.objects for delete
using (
  bucket_id = 'library_pages'
  and auth.role() = 'authenticated'
);
