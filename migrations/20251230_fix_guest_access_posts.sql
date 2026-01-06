-- Fix guest access to posts and divination records
-- Ensures that guests (anonymous users) can view published posts and associated divination records

-- 1. Ensure permissions are granted to anonymous and authenticated users
GRANT SELECT ON TABLE public.posts TO anon, authenticated;
GRANT SELECT ON TABLE public.divination_records TO anon, authenticated;

-- 2. Update posts policy to strictly allow published posts for everyone
DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;

CREATE POLICY "posts_select_visible"
  ON public.posts FOR SELECT
  USING (
    status = 'published'
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

-- 3. Update divination_records policy to allow access if associated with a published post
DROP POLICY IF EXISTS "records_select_associated_with_posts" ON public.divination_records;

CREATE POLICY "records_select_associated_with_posts"
  ON public.divination_records
  FOR SELECT
  USING (
    -- Allow if user owns the record
    auth.uid() = user_id
    OR
    -- Allow if record is associated with a published post (visible to everyone)
    EXISTS (
      SELECT 1
      FROM public.posts
      WHERE posts.divination_record_id = divination_records.id
      AND (
        posts.status = 'published'
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

-- 4. Add comments to explain the policies
COMMENT ON POLICY "posts_select_visible" ON public.posts IS 
  'Allows everyone to see published posts; authors and admins see all.';

COMMENT ON POLICY "records_select_associated_with_posts" ON public.divination_records IS 
  'Allows everyone to see records associated with published posts; authors see their own.';
