-- Add bounty column to posts table for reward posts
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS bounty integer DEFAULT 0;

-- Add comment
COMMENT ON COLUMN public.posts.bounty IS '悬赏金额（易币），0表示无悬赏';

