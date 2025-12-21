-- Ensure type column exists in posts table
-- This migration ensures the type column is present even if 20250201_add_type_to_posts.sql wasn't applied

-- Add type column if it doesn't exist
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS type text;

-- Add check constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.table_constraints 
    WHERE table_schema = 'public' 
    AND table_name = 'posts' 
    AND constraint_name = 'posts_type_check'
  ) THEN
    ALTER TABLE public.posts
      ADD CONSTRAINT posts_type_check CHECK (type IN ('theory', 'help', 'debate', 'chat'));
  END IF;
END $$;

-- Set default value if column exists but doesn't have a default
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'posts' 
    AND column_name = 'type'
    AND column_default IS NULL
  ) THEN
    ALTER TABLE public.posts
      ALTER COLUMN type SET DEFAULT 'theory';
    
    -- Update existing rows that might be NULL
    UPDATE public.posts
    SET type = 'theory'
    WHERE type IS NULL;
  END IF;
END $$;

-- Add comment
COMMENT ON COLUMN public.posts.type IS '帖子类型：theory(论道), help(悬卦), debate(争鸣), chat(茶寮)';

