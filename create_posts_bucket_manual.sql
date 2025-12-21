-- 手动执行此 SQL 脚本在 Supabase Dashboard 中创建 posts bucket
-- 路径：Supabase Dashboard > SQL Editor > 粘贴并执行此脚本

-- 创建 posts storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'posts',
  'posts',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- 删除已存在的策略（如果存在）
DROP POLICY IF EXISTS "posts_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_update_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "posts_select_public" ON storage.objects;

-- 允许已认证用户上传自己的帖子图片
-- 文件路径格式：{user_id}/{filename}（第一层文件夹必须是用户 ID）
CREATE POLICY "posts_upload_own"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 允许已认证用户更新自己的帖子图片
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

-- 允许已认证用户删除自己的帖子图片
CREATE POLICY "posts_delete_own"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'posts' 
  AND auth.role() = 'authenticated'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 允许公开读取（因为 bucket 是公开的）
CREATE POLICY "posts_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'posts');

