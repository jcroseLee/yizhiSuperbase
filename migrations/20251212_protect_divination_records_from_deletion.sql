-- Protect divination_records that are referenced by posts
-- This ensures that when a user deletes a divination record in their personal center,
-- the record is only deleted if it's not referenced by any posts.
-- When a post is deleted, the associated divination_record is only deleted if it's
-- not referenced by any other posts.

-- Step 1: Change the foreign key constraint from ON DELETE SET NULL to ON DELETE RESTRICT
-- This prevents deletion of divination_records that are referenced by posts
DO $$
BEGIN
  -- Drop the existing foreign key constraint
  IF EXISTS (
    SELECT 1 
    FROM pg_constraint 
    WHERE conname = 'posts_divination_record_id_fkey'
  ) THEN
    ALTER TABLE public.posts 
    DROP CONSTRAINT posts_divination_record_id_fkey;
  END IF;

  -- Add new constraint with RESTRICT to prevent deletion when referenced
  ALTER TABLE public.posts
  ADD CONSTRAINT posts_divination_record_id_fkey 
  FOREIGN KEY (divination_record_id) 
  REFERENCES public.divination_records(id) 
  ON DELETE RESTRICT;
END $$;

-- Step 2: Create a function to clean up divination_records when posts are deleted
-- This function checks if a divination_record is still referenced by any other posts
-- If not, it deletes the record
CREATE OR REPLACE FUNCTION public.cleanup_orphaned_divination_records()
RETURNS TRIGGER AS $$
DECLARE
  record_id uuid;
  reference_count integer;
BEGIN
  -- Get the divination_record_id from the deleted post
  record_id := OLD.divination_record_id;
  
  -- Only proceed if the post had a divination_record_id
  IF record_id IS NOT NULL THEN
    -- Count how many posts still reference this record
    SELECT COUNT(*) INTO reference_count
    FROM public.posts
    WHERE divination_record_id = record_id;
    
    -- If no other posts reference this record, delete it
    IF reference_count = 0 THEN
      DELETE FROM public.divination_records
      WHERE id = record_id;
    END IF;
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create a trigger to call the cleanup function when a post is deleted
DROP TRIGGER IF EXISTS trigger_cleanup_orphaned_divination_records ON public.posts;

CREATE TRIGGER trigger_cleanup_orphaned_divination_records
  AFTER DELETE ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.cleanup_orphaned_divination_records();

-- Step 4: Add comment to document the behavior
COMMENT ON FUNCTION public.cleanup_orphaned_divination_records() IS 
  'Automatically deletes divination_records when the last referencing post is deleted';

