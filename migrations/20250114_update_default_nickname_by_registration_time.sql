-- Update default nickname logic to assign numbers based on registration time
-- Format: '易知用户01', '易知用户02', etc. (2-digit format)
-- Update specific user to '易知用户01'

-- Step 1: Update the specific user to '易知用户01'
UPDATE public.profiles
SET nickname = '易知用户01'
WHERE id = '8f34ea2f-0cc5-4d83-869a-1a7a1461b5d4';

-- Step 2: Update function to generate 2-digit format nicknames
CREATE OR REPLACE FUNCTION public.generate_default_nickname()
RETURNS text AS $$
DECLARE
  next_number integer;
  formatted_number text;
BEGIN
  next_number := public.get_next_default_nickname_number();
  -- Format number with 2 digits (01, 02, etc.)
  formatted_number := lpad(next_number::text, 2, '0');
  RETURN '易知用户' || formatted_number;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Update function to get next number, considering existing 2-digit and 3-digit formats
CREATE OR REPLACE FUNCTION public.get_next_default_nickname_number()
RETURNS integer AS $$
DECLARE
  max_number integer;
  next_number integer;
BEGIN
  -- Find the maximum number used in default nicknames (support both 2-digit and 3-digit formats)
  -- Extract number from nickname like '易知用户01', '易知用户001', etc.
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN nickname ~ '^易知用户[0-9]+$' THEN
          CAST(SUBSTRING(nickname FROM '易知用户([0-9]+)$') AS integer)
        ELSE 0
      END
    ), 0
  ) INTO max_number
  FROM public.profiles
  WHERE nickname ~ '^易知用户[0-9]+$';
  
  -- Return the next number
  next_number := max_number + 1;
  
  RETURN next_number;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Reassign all default nicknames based on registration time
-- This ensures all users get numbers based on their creation order
-- The specific user (8f34ea2f-0cc5-4d83-869a-1a7a1461b5d4) will be '易知用户01'
DO $$
DECLARE
  user_record RECORD;
  current_number integer := 0;
  user_count integer := 0;
  formatted_number text;
  new_nickname text;
  specific_user_id uuid := '8f34ea2f-0cc5-4d83-869a-1a7a1461b5d4';
BEGIN
  -- Process all users with default nickname format, ordered by created_at
  -- This ensures users get numbers based on their registration time
  -- Skip the specific user as it's already set to '易知用户01'
  FOR user_record IN 
    SELECT 
      p.id, 
      p.nickname, 
      p.created_at,
      COALESCE(au.created_at, p.created_at) as registration_time
    FROM public.profiles p
    LEFT JOIN auth.users au ON au.id = p.id
    WHERE (p.nickname IS NULL 
       OR p.nickname = '' 
       OR p.nickname ~ '^易知用户[0-9]+$')
       AND p.id != specific_user_id  -- Skip the specific user
    ORDER BY COALESCE(au.created_at, p.created_at) ASC NULLS LAST
  LOOP
    current_number := current_number + 1;
    
    -- Format number with 2 digits (02, 03, etc., starting from 02 since 01 is reserved)
    formatted_number := lpad((current_number + 1)::text, 2, '0');
    new_nickname := '易知用户' || formatted_number;
    
    -- Update the profile with new nickname
    UPDATE public.profiles
    SET nickname = new_nickname
    WHERE id = user_record.id;
    
    user_count := user_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Updated % users with default nickname based on registration time (易知用户01 is reserved for user %s)', user_count, specific_user_id;
END $$;

-- Add comment
COMMENT ON FUNCTION public.generate_default_nickname() IS 'Generates a default nickname in format 易知用户01, 易知用户02, etc. (2-digit format, based on registration time)';

