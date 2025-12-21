-- Ensure motto column exists in profiles table
-- This migration fixes the issue where the motto column might be missing
-- or the PostgREST schema cache is out of sync

-- Step 1: Add motto column if it doesn't exist
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS motto text;

-- Step 2: Add comment for documentation
COMMENT ON COLUMN public.profiles.motto IS 'User personal motto or quote';

-- Step 3: Ensure the column is included in RLS policies
-- The existing profiles_update_own policy should already cover this column
-- since it uses UPDATE on the entire table, but we verify it exists

-- Note: After running this migration, you may need to refresh the PostgREST schema cache
-- in Supabase Dashboard: Settings > API > Reload schema cache
-- Or wait a few minutes for automatic cache refresh

