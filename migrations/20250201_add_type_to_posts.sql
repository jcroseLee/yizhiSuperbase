-- Add type column to posts table for post categorization
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS type text CHECK (type IN ('theory', 'help', 'debate', 'chat')) DEFAULT 'theory';

-- Add comment
COMMENT ON COLUMN public.posts.type IS '帖子类型：theory(论道), help(悬卦), debate(争鸣), chat(茶寮)';

