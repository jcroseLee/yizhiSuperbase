-- Remove user_profiles_view as it's not being used
-- All code should use the profiles table directly instead
-- This migration consolidates to a single source of truth: the profiles table

-- Drop the view if it exists
DROP VIEW IF EXISTS public.user_profiles_view;

-- Note: The profiles table already contains all necessary fields:
-- - id (references auth.users)
-- - nickname
-- - avatar_url
-- - role
-- - wechat_openid
-- - wechat_unionid
-- - phone
-- - created_at
-- - updated_at
--
-- If you need auth.users data (like email, last_sign_in_at), 
-- you can join with auth.users directly in your queries.

