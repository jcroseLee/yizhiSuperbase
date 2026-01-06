-- Ensure default nickname and avatar for new users
-- This migration ensures that new users automatically get default nickname and avatar
-- Format: '易知用户01', '易知用户02', etc. (2-digit format)
-- This is a fix to ensure the trigger works correctly

-- Step 1: Ensure get_next_default_nickname_number function exists
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

-- Step 2: Ensure generate_default_nickname function exists
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

-- Step 3: Ensure get_default_avatar_url function exists
CREATE OR REPLACE FUNCTION public.get_default_avatar_url()
RETURNS text AS $$
BEGIN
  -- Return a default avatar URL
  -- Using dicebear API for default avatar generation
  RETURN 'https://api.dicebear.com/7.x/avataaars/svg?seed=易知用户';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Update handle_new_user function to ensure default nickname and avatar
-- This function is called automatically when a new user is created in auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_nickname text;
  default_avatar text;
BEGIN
  -- Use provided nickname from metadata if available
  IF new.raw_user_meta_data->>'nickname' IS NOT NULL 
     AND new.raw_user_meta_data->>'nickname' != '' THEN
    default_nickname := new.raw_user_meta_data->>'nickname';
  ELSE
    -- Generate default nickname: '易知用户01', '易知用户02', etc. (2-digit format)
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

  -- Insert new profile for the user with default nickname and avatar
  INSERT INTO public.profiles (
    id,
    nickname,
    avatar_url,
    role,
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
    COALESCE(new.raw_user_meta_data->>'wechat_openid', NULL),
    COALESCE(new.raw_user_meta_data->>'wechat_unionid', NULL),
    COALESCE(new.phone, NULL),
    COALESCE(new.email, NULL),
    new.created_at
  )
  ON CONFLICT (id) DO UPDATE SET
    -- If profile already exists but nickname or avatar is missing, update them
    nickname = COALESCE(profiles.nickname, EXCLUDED.nickname),
    avatar_url = COALESCE(profiles.avatar_url, EXCLUDED.avatar_url);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 5: Ensure the trigger exists and is properly configured
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Grant execute permissions to ensure functions can be called
GRANT EXECUTE ON FUNCTION public.get_next_default_nickname_number() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.generate_default_nickname() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_default_avatar_url() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO authenticated, anon, service_role;

-- Step 7: Add comments for documentation
COMMENT ON FUNCTION public.get_next_default_nickname_number() IS 'Gets the next available number for default nickname (易知用户XX)';
COMMENT ON FUNCTION public.generate_default_nickname() IS 'Generates a default nickname in format 易知用户01, 易知用户02, etc. (2-digit format)';
COMMENT ON FUNCTION public.get_default_avatar_url() IS 'Returns the default avatar URL for new users';
COMMENT ON FUNCTION public.handle_new_user() IS 'Creates profile with default nickname and avatar when new user signs up';

-- Step 8: Update existing users who don't have nickname or avatar
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
  -- This ensures users get numbers based on their creation time
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
      -- Don't update users who already have a custom nickname (not default format)
      AND (p.nickname IS NULL OR p.nickname = '' OR p.nickname ~ '^易知用户[0-9]+$')
    ORDER BY COALESCE(au.created_at, p.created_at) ASC NULLS LAST
  LOOP
    -- Generate default nickname if missing
    IF user_record.nickname IS NULL OR user_record.nickname = '' THEN
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

