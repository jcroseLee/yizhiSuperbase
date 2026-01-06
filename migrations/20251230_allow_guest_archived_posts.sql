-- Update RLS policies to allow guest access to archived posts
-- Extends the previous fix to include 'archived' status for public viewing

-- 1. Update posts policy to allow 'published' and 'archived'
DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;

CREATE POLICY "posts_select_visible"
  ON public.posts FOR SELECT
  USING (
    status IN ('published', 'archived')
    OR auth.uid() = user_id
    OR (
      auth.uid() IS NOT NULL 
      AND EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
      )
    )
  );

-- 2. Update divination_records policy to allow access if associated with a published or archived post
DROP POLICY IF EXISTS "records_select_associated_with_posts" ON public.divination_records;

CREATE POLICY "records_select_associated_with_posts"
  ON public.divination_records
  FOR SELECT
  USING (
    -- Allow if user owns the record
    auth.uid() = user_id
    OR
    -- Allow if record is associated with a public post (published or archived)
    EXISTS (
      SELECT 1
      FROM public.posts
      WHERE posts.divination_record_id = divination_records.id
      AND (
        posts.status IN ('published', 'archived')
        OR posts.user_id = auth.uid()
        OR (
          auth.uid() IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() 
            AND profiles.role = 'admin'
          )
        )
      )
    )
  );

-- 3. Update comments to reflect the change
COMMENT ON POLICY "posts_select_visible" ON public.posts IS 
  'Allows everyone to see published and archived posts; authors and admins see all.';

COMMENT ON POLICY "records_select_associated_with_posts" ON public.divination_records IS 
  'Allows everyone to see records associated with published or archived posts; authors see their own.';
