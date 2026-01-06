-- Fix handle_new_user trigger to use default nickname and avatar functions
-- This ensures new users get default nickname (易知用户01, 易知用户02, etc.) and avatar

-- Update the handle_new_user trigger function to use the new default functions
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

  -- Insert new profile for the user
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
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Add comment
COMMENT ON FUNCTION public.handle_new_user() IS 'Creates profile with default nickname and avatar when new user signs up';

