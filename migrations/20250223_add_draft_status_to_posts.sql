-- Add draft status field to posts table
-- 添加草稿状态字段

-- Add status column
-- published: 已发布（默认）
-- draft: 草稿
-- archived: 已归档

-- 先删除可能存在的旧约束
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'posts_status_check' 
    AND conrelid = 'public.posts'::regclass
  ) THEN
    ALTER TABLE public.posts DROP CONSTRAINT posts_status_check;
  END IF;
END $$;

-- 添加 status 字段（如果不存在）
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'published';

-- 设置现有行的默认值
UPDATE public.posts SET status = 'published' WHERE status IS NULL;

-- 添加正确的约束
ALTER TABLE public.posts
  ADD CONSTRAINT posts_status_check 
  CHECK (status IN ('published', 'draft', 'archived'));

-- Set default value for existing rows
update public.posts set status = 'published' where status is null;

-- Create index for efficient draft queries
create index if not exists idx_posts_status_user_created 
  on public.posts(user_id, status, created_at desc);

-- Update RLS policies to handle drafts
-- Drop all existing select policies
drop policy if exists "posts_select_all" on public.posts;
drop policy if exists "posts_select_published_or_own" on public.posts;

-- Create new select policy: users can see published posts or their own drafts
create policy "posts_select_published_or_own"
  on public.posts for select
  using (
    status = 'published' 
    or (auth.uid() = user_id and status = 'draft')
  );

-- Comments: 草稿禁止添加评论说明
comment on column public.posts.status is 'Post status: published (已发布), draft (草稿), archived (已归档)';

