-- Sync profiles table with auth.users table
-- This migration ensures all login-related fields are synchronized between profiles and auth.users

-- 1. Sync phone number from auth.users to profiles
UPDATE public.profiles p
SET phone = (
  SELECT au.phone
  FROM auth.users au
  WHERE au.id = p.id
)
WHERE EXISTS (
  SELECT 1
  FROM auth.users au
  WHERE au.id = p.id
  AND au.phone IS NOT NULL
  AND (p.phone IS NULL OR p.phone != au.phone)
);

-- 2. Sync wechat_openid from auth.users.user_metadata to profiles
UPDATE public.profiles p
SET wechat_openid = (
  SELECT au.raw_user_meta_data->>'wechat_openid'
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'wechat_openid' IS NOT NULL
)
WHERE EXISTS (
  SELECT 1
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'wechat_openid' IS NOT NULL
  AND (p.wechat_openid IS NULL OR p.wechat_openid != au.raw_user_meta_data->>'wechat_openid')
);

-- 3. Sync wechat_unionid from auth.users.user_metadata to profiles
UPDATE public.profiles p
SET wechat_unionid = (
  SELECT au.raw_user_meta_data->>'wechat_unionid'
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'wechat_unionid' IS NOT NULL
)
WHERE EXISTS (
  SELECT 1
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'wechat_unionid' IS NOT NULL
  AND (p.wechat_unionid IS NULL OR p.wechat_unionid != au.raw_user_meta_data->>'wechat_unionid')
);

-- 4. Sync nickname from auth.users.user_metadata to profiles
UPDATE public.profiles p
SET nickname = (
  SELECT COALESCE(au.raw_user_meta_data->>'nickname', '用户')
  FROM auth.users au
  WHERE au.id = p.id
)
WHERE EXISTS (
  SELECT 1
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'nickname' IS NOT NULL
  AND (p.nickname IS NULL OR p.nickname != au.raw_user_meta_data->>'nickname')
);

-- 5. Sync avatar_url from auth.users.user_metadata to profiles
UPDATE public.profiles p
SET avatar_url = (
  SELECT au.raw_user_meta_data->>'avatar_url'
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'avatar_url' IS NOT NULL
)
WHERE EXISTS (
  SELECT 1
  FROM auth.users au
  WHERE au.id = p.id
  AND au.raw_user_meta_data->>'avatar_url' IS NOT NULL
  AND (p.avatar_url IS NULL OR p.avatar_url != au.raw_user_meta_data->>'avatar_url')
);

-- 6. Create profiles for any auth.users that don't have one
INSERT INTO public.profiles (
  id,
  nickname,
  avatar_url,
  role,
  wechat_openid,
  wechat_unionid,
  phone,
  created_at
)
SELECT 
  au.id,
  COALESCE(au.raw_user_meta_data->>'nickname', '用户') as nickname,
  au.raw_user_meta_data->>'avatar_url' as avatar_url,
  'user' as role,
  au.raw_user_meta_data->>'wechat_openid' as wechat_openid,
  au.raw_user_meta_data->>'wechat_unionid' as wechat_unionid,
  au.phone,
  au.created_at
FROM auth.users au
WHERE au.id NOT IN (SELECT id FROM public.profiles)
ON CONFLICT (id) DO NOTHING;

-- 7. Create a function to automatically sync profiles when auth.users is updated
-- Note: This function can be called manually or via triggers (if triggers are set up)
CREATE OR REPLACE FUNCTION public.sync_profile_from_auth_user(user_id uuid)
RETURNS void AS $$
DECLARE
  profile_exists boolean;
BEGIN
  -- Check if profile exists
  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id = user_id) INTO profile_exists;
  
  IF profile_exists THEN
    -- Update existing profile
    UPDATE public.profiles p
    SET
      phone = au.phone,
      nickname = COALESCE(au.raw_user_meta_data->>'nickname', p.nickname),
      avatar_url = COALESCE(au.raw_user_meta_data->>'avatar_url', p.avatar_url),
      wechat_openid = COALESCE(au.raw_user_meta_data->>'wechat_openid', p.wechat_openid),
      wechat_unionid = COALESCE(au.raw_user_meta_data->>'wechat_unionid', p.wechat_unionid),
      updated_at = now()
    FROM auth.users au
    WHERE p.id = au.id
      AND au.id = user_id;
  ELSE
    -- Create new profile if it doesn't exist
    INSERT INTO public.profiles (
      id,
      nickname,
      avatar_url,
      role,
      wechat_openid,
      wechat_unionid,
      phone,
      created_at
    )
    SELECT 
      au.id,
      COALESCE(au.raw_user_meta_data->>'nickname', '用户'),
      au.raw_user_meta_data->>'avatar_url',
      'user',
      au.raw_user_meta_data->>'wechat_openid',
      au.raw_user_meta_data->>'wechat_unionid',
      au.phone,
      au.created_at
    FROM auth.users au
    WHERE au.id = user_id
    ON CONFLICT (id) DO NOTHING;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Create a view for easy querying of user data from both tables
CREATE OR REPLACE VIEW public.user_profiles_view AS
SELECT 
  p.id,
  p.nickname,
  p.avatar_url,
  p.role,
  p.wechat_openid,
  p.wechat_unionid,
  p.phone,
  p.created_at,
  p.updated_at,
  au.email,
  au.created_at as auth_created_at,
  au.last_sign_in_at,
  au.raw_user_meta_data->>'nickname' as auth_nickname,
  au.raw_user_meta_data->>'avatar_url' as auth_avatar_url,
  au.raw_user_meta_data->>'wechat_openid' as auth_wechat_openid,
  au.raw_user_meta_data->>'wechat_unionid' as auth_wechat_unionid,
  au.phone as auth_phone
FROM public.profiles p
LEFT JOIN auth.users au ON p.id = au.id;

-- Grant access to the view
GRANT SELECT ON public.user_profiles_view TO authenticated;
GRANT SELECT ON public.user_profiles_view TO anon;

