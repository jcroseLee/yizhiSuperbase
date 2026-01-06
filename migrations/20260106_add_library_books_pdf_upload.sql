ALTER TABLE public.library_books
ADD COLUMN IF NOT EXISTS pdf_url TEXT;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'library_pdfs',
  'library_pdfs',
  true,
  52428800,
  ARRAY['application/pdf']
)
on conflict (id) do nothing;

drop policy if exists "library_pdfs_upload_own" on storage.objects;
drop policy if exists "library_pdfs_update_own" on storage.objects;
drop policy if exists "library_pdfs_delete_own" on storage.objects;
drop policy if exists "library_pdfs_select_public" on storage.objects;

create policy "library_pdfs_upload_own"
on storage.objects for insert
with check (
  bucket_id = 'library_pdfs'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "library_pdfs_update_own"
on storage.objects for update
using (
  bucket_id = 'library_pdfs'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'library_pdfs'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "library_pdfs_delete_own"
on storage.objects for delete
using (
  bucket_id = 'library_pdfs'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "library_pdfs_select_public"
on storage.objects for select
using (bucket_id = 'library_pdfs');
