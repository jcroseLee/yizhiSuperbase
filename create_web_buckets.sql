-- Quick fix: Create avatars and posts buckets for web app
-- Run this in Supabase Dashboard > SQL Editor if you encounter "Bucket not found" errors

-- Create avatars storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880, -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Create posts storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'posts',
  'posts',
  true,
  5242880, -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Drop existing policies if they exist (to allow re-running this script)
DROP POLICY IF EXISTS "avatars_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_select_public" ON storage.objects;
DROP POLICY IF EXISTS "posts_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_update_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_select_public" ON storage.objects;

-- Create avatars policies
CREATE POLICY "avatars_upload_own"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'avatars' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'avatars' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'avatars' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'avatars' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- Create posts policies
CREATE POLICY "posts_upload_own"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "posts_update_own"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "posts_delete_own"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "posts_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'posts');

