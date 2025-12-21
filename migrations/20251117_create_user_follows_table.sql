-- User follows table for user following other users
CREATE TABLE IF NOT EXISTS public.user_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  following_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(follower_id, following_id),
  -- Prevent users from following themselves
  CHECK (follower_id != following_id)
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_follows_follower_id ON public.user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_following_id ON public.user_follows(following_id);

-- Enable RLS
ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_follows
DO $$
BEGIN
  -- Allow users to view their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'user_follows' 
    AND policyname = 'user_follows_select_own'
  ) THEN
    CREATE POLICY "user_follows_select_own"
      ON public.user_follows FOR SELECT
      USING (auth.uid() = follower_id OR auth.uid() = following_id);
  END IF;
  
  -- Allow users to view follow counts (for public display)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'user_follows' 
    AND policyname = 'user_follows_select_public'
  ) THEN
    CREATE POLICY "user_follows_select_public"
      ON public.user_follows FOR SELECT
      USING (true);
  END IF;
  
  -- Allow users to insert their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'user_follows' 
    AND policyname = 'user_follows_insert_own'
  ) THEN
    CREATE POLICY "user_follows_insert_own"
      ON public.user_follows FOR INSERT
      WITH CHECK (auth.uid() = follower_id);
  END IF;
  
  -- Allow users to delete their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'user_follows' 
    AND policyname = 'user_follows_delete_own'
  ) THEN
    CREATE POLICY "user_follows_delete_own"
      ON public.user_follows FOR DELETE
      USING (auth.uid() = follower_id);
  END IF;
END $$;

-- Comments
COMMENT ON TABLE public.user_follows IS '用户关注用户表';
COMMENT ON COLUMN public.user_follows.follower_id IS '关注者用户ID';
COMMENT ON COLUMN public.user_follows.following_id IS '被关注者用户ID';

