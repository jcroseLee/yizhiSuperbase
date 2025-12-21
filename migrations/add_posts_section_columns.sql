-- 快速添加 posts 表的分类和状态列
-- 这个脚本只添加必需的列，可以安全地多次运行

-- 添加分类列
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS section text CHECK (section IN ('study','help','casual','announcement')) DEFAULT 'study';

-- 添加状态列
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS status text CHECK (status IN ('published','pending','hidden','rejected')) DEFAULT 'published';

-- 添加置顶列
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS is_pinned boolean DEFAULT false;

-- 添加精选列
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS is_featured boolean DEFAULT false;

-- 更新现有帖子的默认值（如果列刚创建）
UPDATE public.posts 
SET 
  section = COALESCE(section, 'study'),
  status = COALESCE(status, 'published'),
  is_pinned = COALESCE(is_pinned, false),
  is_featured = COALESCE(is_featured, false)
WHERE section IS NULL OR status IS NULL OR is_pinned IS NULL OR is_featured IS NULL;

-- 注意：运行此脚本后，PostgREST schema cache 会自动刷新
-- 如果仍然看到列不存在的错误，请等待几秒钟让缓存更新

