-- Fix nickname to use default format instead of email prefix
-- Add user_number field to profiles table (累加编号，根据注册时间，第一位是1)

-- Step 1: Add user_number column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS user_number integer;

-- Step 2: Create unique index on user_number for faster lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_user_number_unique 
ON public.profiles(user_number) 
WHERE user_number IS NOT NULL;

-- Step 3: Create function to get next user number based on registration time
CREATE OR REPLACE FUNCTION public.get_next_user_number()
RETURNS integer AS $$
DECLARE
  max_number integer;
  next_number integer;
BEGIN
  -- Find the maximum user_number already assigned
  SELECT COALESCE(MAX(user_number), 0) INTO max_number
  FROM public.profiles
  WHERE user_number IS NOT NULL;
  
  -- Return the next number
  next_number := max_number + 1;
  
  RETURN next_number;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Ensure get_next_default_nickname_number function exists
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

-- Step 5: Ensure generate_default_nickname function exists
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

-- Step 6: Ensure get_default_avatar_url function exists
CREATE OR REPLACE FUNCTION public.get_default_avatar_url()
RETURNS text AS $$
BEGIN
  -- Return a default avatar URL
  -- Using dicebear API for default avatar generation
  RETURN 'https://api.dicebear.com/7.x/avataaars/svg?seed=易知用户';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 7: Update handle_new_user function to use default nickname and set user_number
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_nickname text;
  default_avatar text;
  new_user_number integer;
BEGIN
  -- Get next user number
  new_user_number := public.get_next_user_number();
  
  -- Use provided nickname from metadata if available
  IF new.raw_user_meta_data->>'nickname' IS NOT NULL 
     AND new.raw_user_meta_data->>'nickname' != '' THEN
    default_nickname := new.raw_user_meta_data->>'nickname';
  ELSE
    -- Generate default nickname: '易知用户01', '易知用户02', etc. (2-digit format)
    -- DO NOT use email prefix anymore
    default_nickname := public.generate_default_nickname();
  END IF;
  
  -- Use provided avatar from metadata if available
  IF new.raw_user_meta_data->>'avatar_url' IS NOT NULL 
     AND new.raw_user_meta_data->>'avatar_url' != '' THEN
    default_avatar := new.raw_user_meta_data->>'avatar_url';
  ELSE
    -- Use default avatar
    default_avatar := public.get_default_avatar_url();
  END IF;

  -- Insert new profile for the user with default nickname, avatar, and user_number
  INSERT INTO public.profiles (
    id,
    nickname,
    avatar_url,
    role,
    user_number,
    wechat_openid,
    wechat_unionid,
    phone,
    email,
    created_at
  )
  VALUES (
    new.id,
    default_nickname,
    default_avatar,
    'user',
    new_user_number,
    COALESCE(new.raw_user_meta_data->>'wechat_openid', NULL),
    COALESCE(new.raw_user_meta_data->>'wechat_unionid', NULL),
    COALESCE(new.phone, NULL),
    COALESCE(new.email, NULL),
    new.created_at
  )
  ON CONFLICT (id) DO UPDATE SET
    -- If profile already exists but nickname, avatar, or user_number is missing, update them
    nickname = COALESCE(profiles.nickname, EXCLUDED.nickname),
    avatar_url = COALESCE(profiles.avatar_url, EXCLUDED.avatar_url),
    user_number = COALESCE(profiles.user_number, EXCLUDED.user_number);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 8: Ensure the trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Step 9: Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_next_user_number() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_next_default_nickname_number() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.generate_default_nickname() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_default_avatar_url() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO authenticated, anon, service_role;

-- Step 10: Add comments for documentation
COMMENT ON COLUMN public.profiles.user_number IS '用户编号，根据注册时间累加，第一位注册用户编号是1';
COMMENT ON FUNCTION public.get_next_user_number() IS 'Gets the next available user number based on registration time';
COMMENT ON FUNCTION public.get_next_default_nickname_number() IS 'Gets the next available number for default nickname (易知用户XX)';
COMMENT ON FUNCTION public.generate_default_nickname() IS 'Generates a default nickname in format 易知用户01, 易知用户02, etc. (2-digit format)';
COMMENT ON FUNCTION public.get_default_avatar_url() IS 'Returns the default avatar URL for new users';
COMMENT ON FUNCTION public.handle_new_user() IS 'Creates profile with default nickname, avatar, and user_number when new user signs up';

-- Step 11: Assign user_number to existing users based on registration time
-- This ensures all existing users get a user_number (第一位注册用户编号是1)
DO $$
DECLARE
  user_record RECORD;
  current_number integer;
  max_existing_number integer;
  user_count integer := 0;
BEGIN
  -- Find the maximum user_number already assigned
  SELECT COALESCE(MAX(user_number), 0) INTO max_existing_number
  FROM public.profiles
  WHERE user_number IS NOT NULL;
  
  current_number := max_existing_number;
  
  -- Process all users without user_number, ordered by registration time (created_at)
  -- This ensures users get numbers based on their creation time
  FOR user_record IN 
    SELECT 
      p.id, 
      p.user_number,
      p.nickname,
      p.avatar_url,
      p.created_at,
      COALESCE(au.created_at, p.created_at) as registration_time
    FROM public.profiles p
    LEFT JOIN auth.users au ON au.id = p.id
    WHERE p.user_number IS NULL
    ORDER BY COALESCE(au.created_at, p.created_at) ASC NULLS LAST
  LOOP
    current_number := current_number + 1;
    
    -- Update the profile with user_number
    UPDATE public.profiles
    SET user_number = current_number
    WHERE id = user_record.id;
    
    user_count := user_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Assigned user_number to % existing users', user_count;
END $$;

-- Step 12: Update existing users who don't have default nickname or avatar
-- This ensures existing users also get default values if they're missing
DO $$
DECLARE
  user_record RECORD;
  default_nickname text;
  default_avatar text;
  user_count integer := 0;
  current_number integer;
  max_existing_number integer;
BEGIN
  -- Find the maximum number already used in default nicknames
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN nickname ~ '^易知用户[0-9]+$' THEN
          CAST(SUBSTRING(nickname FROM '易知用户([0-9]+)$') AS integer)
        ELSE 0
      END
    ), 0
  ) INTO max_existing_number
  FROM public.profiles
  WHERE nickname ~ '^易知用户[0-9]+$';
  
  current_number := max_existing_number;
  
  -- Process users without nickname or avatar, ordered by created_at
  -- Skip users who already have custom nicknames (not default format and not email-based)
  FOR user_record IN 
    SELECT 
      p.id, 
      p.nickname, 
      p.avatar_url,
      p.created_at,
      COALESCE(au.created_at, p.created_at) as registration_time
    FROM public.profiles p
    LEFT JOIN auth.users au ON au.id = p.id
    WHERE (p.nickname IS NULL OR p.nickname = '' OR p.avatar_url IS NULL OR p.avatar_url = '')
      -- Update users with email-based nicknames or no nickname
      AND (
        p.nickname IS NULL 
        OR p.nickname = '' 
        OR p.nickname ~ '^易知用户[0-9]+$'
        OR (p.nickname ~ '@' AND p.nickname !~ '^易知用户[0-9]+$')  -- Email-based nickname
        OR (p.nickname ~ '^用户_' AND p.nickname !~ '^易知用户[0-9]+$')  -- Old default format
      )
    ORDER BY COALESCE(au.created_at, p.created_at) ASC NULLS LAST
  LOOP
    -- Generate default nickname if missing or if it's email-based
    IF user_record.nickname IS NULL 
       OR user_record.nickname = '' 
       OR (user_record.nickname ~ '@' AND user_record.nickname !~ '^易知用户[0-9]+$')
       OR (user_record.nickname ~ '^用户_' AND user_record.nickname !~ '^易知用户[0-9]+$') THEN
      current_number := current_number + 1;
      default_nickname := '易知用户' || lpad(current_number::text, 2, '0');
    ELSE
      -- Keep existing nickname if it's already in default format
      default_nickname := user_record.nickname;
    END IF;
    
    -- Set default avatar if missing
    IF user_record.avatar_url IS NULL OR user_record.avatar_url = '' THEN
      default_avatar := public.get_default_avatar_url();
    ELSE
      default_avatar := user_record.avatar_url;
    END IF;
    
    -- Update the profile
    UPDATE public.profiles
    SET 
      nickname = default_nickname,
      avatar_url = default_avatar
    WHERE id = user_record.id;
    
    user_count := user_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Updated % users with default nickname and avatar', user_count;
END $$;

