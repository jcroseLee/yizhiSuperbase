-- Allow reading divination records that are associated with public posts
-- This enables displaying divination records in post detail pages

-- Create policy to allow reading divination records associated with posts
-- Users can read divination records if:
-- 1. They own the record (existing policy), OR
-- 2. The record is associated with a public post

CREATE POLICY IF NOT EXISTS "records_select_associated_with_posts"
  ON public.divination_records
  FOR SELECT
  USING (
    -- Allow if user owns the record (covered by existing policy)
    auth.uid() = user_id
    OR
    -- Allow if record is associated with a public post
    EXISTS (
      SELECT 1
      FROM public.posts
      WHERE posts.divination_record_id = divination_records.id
    )
  );

