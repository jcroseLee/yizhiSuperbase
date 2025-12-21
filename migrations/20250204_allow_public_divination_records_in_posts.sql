-- Allow all users (including anonymous) to view divination records associated with published posts
-- This ensures that post-related divination records are visible to everyone

-- Drop the existing policy if it exists (we'll recreate it with better logic)
DROP POLICY IF EXISTS "records_select_associated_with_posts" ON public.divination_records;

-- Create a new policy that allows:
-- 1. Users to view their own records (auth.uid() = user_id)
-- 2. Anyone (including anonymous users) to view records associated with published posts
-- 3. Post authors and admins can view records associated with their posts (even if not published)
CREATE POLICY "records_select_associated_with_posts"
  ON public.divination_records
  FOR SELECT
  USING (
    -- Allow if user owns the record
    auth.uid() = user_id
    OR
    -- Allow if record is associated with a published post (visible to everyone)
    -- Also allow if status is null (for backward compatibility with old posts)
    EXISTS (
      SELECT 1
      FROM public.posts
      WHERE posts.divination_record_id = divination_records.id
      AND (
        posts.status = 'published'
        OR posts.status IS NULL
        OR posts.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles 
          WHERE profiles.id = auth.uid() 
          AND profiles.role = 'admin'
        )
      )
    )
  );

-- Add comment to document the policy
COMMENT ON POLICY "records_select_associated_with_posts" ON public.divination_records IS 
  'Allows all users (including anonymous) to view divination records that are associated with published posts';

