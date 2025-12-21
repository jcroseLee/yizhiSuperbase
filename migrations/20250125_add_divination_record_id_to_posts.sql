-- Add divination_record_id column to posts table
-- This allows posts to be associated with divination records

ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS divination_record_id uuid REFERENCES public.divination_records(id) ON DELETE SET NULL;

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_posts_divination_record_id ON public.posts(divination_record_id);

-- Add comment
COMMENT ON COLUMN public.posts.divination_record_id IS 'Associated divination record ID for posts that reference a divination';

