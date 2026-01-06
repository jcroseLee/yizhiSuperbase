-- Fix draft status constraint
-- 修复草稿状态约束

-- 如果 status 字段已存在但约束不正确，需要先删除旧约束再添加新约束
-- 检查并删除可能存在的旧约束
DO $$
BEGIN
  -- 删除可能存在的旧约束
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'posts_status_check' 
    AND conrelid = 'public.posts'::regclass
  ) THEN
    ALTER TABLE public.posts DROP CONSTRAINT posts_status_check;
  END IF;
END $$;

-- 确保 status 字段存在
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'published';

-- 设置现有行的默认值
UPDATE public.posts SET status = 'published' WHERE status IS NULL;

-- 添加正确的约束
ALTER TABLE public.posts
  ADD CONSTRAINT posts_status_check 
  CHECK (status IN ('published', 'draft', 'archived'));

-- 创建索引（如果不存在）
CREATE INDEX IF NOT EXISTS idx_posts_status_user_created 
  ON public.posts(user_id, status, created_at DESC);

-- 更新 RLS 策略
DROP POLICY IF EXISTS "posts_select_all" ON public.posts;
DROP POLICY IF EXISTS "posts_select_published_or_own" ON public.posts;

CREATE POLICY "posts_select_published_or_own"
  ON public.posts FOR SELECT
  USING (
    status = 'published' 
    OR (auth.uid() = user_id AND status = 'draft')
  );

-- 添加注释
COMMENT ON COLUMN public.posts.status IS 'Post status: published (已发布), draft (草稿), archived (已归档)';

