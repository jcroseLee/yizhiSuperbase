-- Unify posts.status model and add view count RPC
-- 1. Unify posts.status check constraints
-- 2. Add atomic increment function for view_count

-- 1. Unify posts.status check constraints
DO $$
BEGIN
  -- Drop existing check constraints if they exist
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'posts_status_check' 
    AND conrelid = 'public.posts'::regclass
  ) THEN
    ALTER TABLE public.posts DROP CONSTRAINT posts_status_check;
  END IF;
END $$;

-- Add unified check constraint
ALTER TABLE public.posts
  ADD CONSTRAINT posts_status_check 
  CHECK (status IN ('published', 'draft', 'archived', 'pending', 'hidden', 'rejected'));

-- Update column comment
COMMENT ON COLUMN public.posts.status IS 'Post status: published (已发布), draft (草稿), archived (已归档), pending (待审核), hidden (隐藏/审核不通过), rejected (已拒绝)';

-- 2. Add atomic increment function for view_count
CREATE OR REPLACE FUNCTION public.increment_post_view_count(post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Increment view_count atomically
  UPDATE public.posts
  SET view_count = COALESCE(view_count, 0) + 1
  WHERE id = post_id;
END;
$$;

COMMENT ON FUNCTION public.increment_post_view_count(uuid) IS 'Atomically increment the view_count of a post by 1';

-- Grant execute permission to everyone (since viewing is public usually, or at least authenticated)
GRANT EXECUTE ON FUNCTION public.increment_post_view_count(uuid) TO anon, authenticated;
