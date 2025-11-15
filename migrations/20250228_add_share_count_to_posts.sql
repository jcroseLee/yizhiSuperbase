-- Add share_count column to posts table
-- This column tracks how many times a post has been shared

-- Add share_count column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'posts' 
    AND column_name = 'share_count'
  ) THEN
    ALTER TABLE public.posts 
    ADD COLUMN share_count integer DEFAULT 0;
    
    -- Update existing posts to have share_count = 0
    UPDATE public.posts 
    SET share_count = 0 
    WHERE share_count IS NULL;
  END IF;
END $$;

-- Add comment to the column
COMMENT ON COLUMN public.posts.share_count IS 'Number of times this post has been shared to contacts';

-- Create an RPC function to increment share_count
-- This is safer than allowing direct updates, as it ensures only share_count is updated
CREATE OR REPLACE FUNCTION public.increment_post_share_count(post_id uuid)
RETURNS public.posts
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result public.posts;
BEGIN
  -- Only allow authenticated users
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  
  -- Increment share_count atomically
  UPDATE public.posts
  SET share_count = COALESCE(share_count, 0) + 1
  WHERE id = post_id
  RETURNING * INTO result;
  
  IF result IS NULL THEN
    RAISE EXCEPTION 'Post not found';
  END IF;
  
  RETURN result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.increment_post_share_count(uuid) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.increment_post_share_count(uuid) IS 'Increment the share_count of a post by 1. Can be called by any authenticated user.';

-- Add RLS policy to allow any authenticated user to update share_count
-- NOTE: This policy allows any authenticated user to update posts, but it's intended
-- to be used only for updating share_count. The RPC function increment_post_share_count
-- is the preferred method as it uses SECURITY DEFINER to bypass RLS and ensures
-- only share_count is updated atomically.
-- 
-- This policy is a fallback for when the RPC function is not yet available (e.g., 
-- before migrations are run). In production, the RPC function should be used.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'posts' 
    AND policyname = 'posts_update_share_count'
  ) THEN
    CREATE POLICY "posts_update_share_count"
      ON public.posts FOR UPDATE
      USING (auth.uid() IS NOT NULL)
      WITH CHECK (auth.uid() IS NOT NULL);
  END IF;
END $$;

COMMENT ON POLICY "posts_update_share_count" ON public.posts IS 
  'Allows any authenticated user to update posts. Intended for share_count updates only. The RPC function increment_post_share_count is the preferred method.';

