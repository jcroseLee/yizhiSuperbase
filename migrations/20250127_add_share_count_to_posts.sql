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

