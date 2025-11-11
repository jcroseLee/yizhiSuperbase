-- Sync data from users_profiles table to profiles table
-- This migration handles the case where users_profiles table exists and needs to be merged into profiles
-- It dynamically checks which columns exist before syncing

DO $$
DECLARE
  table_exists boolean;
  has_nickname boolean;
  has_avatar_url boolean;
  has_role boolean;
  has_wechat_openid boolean;
  has_wechat_unionid boolean;
  has_phone boolean;
  has_created_at boolean;
  has_updated_at boolean;
  row_count integer;
  insert_sql text;
  update_sql text;
  insert_cols text;
  insert_vals text;
  update_set text;
  where_conditions text;
BEGIN
  -- Check if users_profiles table exists
  SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles'
  ) INTO table_exists;

  IF NOT table_exists THEN
    RAISE NOTICE 'users_profiles table does not exist. Nothing to sync.';
    RETURN;
  END IF;

  RAISE NOTICE 'users_profiles table exists, checking columns...';
  
  -- Check which columns exist
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'nickname'
  ) INTO has_nickname;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'avatar_url'
  ) INTO has_avatar_url;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'role'
  ) INTO has_role;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'wechat_openid'
  ) INTO has_wechat_openid;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'wechat_unionid'
  ) INTO has_wechat_unionid;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'phone'
  ) INTO has_phone;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'created_at'
  ) INTO has_created_at;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users_profiles' 
    AND column_name = 'updated_at'
  ) INTO has_updated_at;

  -- Get count of rows in users_profiles
  EXECUTE 'SELECT COUNT(*) FROM public.users_profiles' INTO row_count;
  RAISE NOTICE 'Found % rows in users_profiles table', row_count;

  -- Build INSERT statement dynamically
  insert_cols := 'id';
  insert_vals := 'up.id';
  
  IF has_nickname THEN
    insert_cols := insert_cols || ', nickname';
    insert_vals := insert_vals || ', up.nickname';
  END IF;
  
  IF has_avatar_url THEN
    insert_cols := insert_cols || ', avatar_url';
    insert_vals := insert_vals || ', up.avatar_url';
  END IF;
  
  IF has_role THEN
    insert_cols := insert_cols || ', role';
    insert_vals := insert_vals || ', COALESCE(up.role, ''user'')';
  ELSE
    insert_cols := insert_cols || ', role';
    insert_vals := insert_vals || ', ''user''';
  END IF;
  
  IF has_wechat_openid THEN
    insert_cols := insert_cols || ', wechat_openid';
    insert_vals := insert_vals || ', up.wechat_openid';
  END IF;
  
  IF has_wechat_unionid THEN
    insert_cols := insert_cols || ', wechat_unionid';
    insert_vals := insert_vals || ', up.wechat_unionid';
  END IF;
  
  IF has_phone THEN
    insert_cols := insert_cols || ', phone';
    insert_vals := insert_vals || ', up.phone';
  END IF;
  
  IF has_created_at THEN
    insert_cols := insert_cols || ', created_at';
    insert_vals := insert_vals || ', COALESCE(up.created_at, now())';
  ELSE
    insert_cols := insert_cols || ', created_at';
    insert_vals := insert_vals || ', now()';
  END IF;
  
  IF has_updated_at THEN
    insert_cols := insert_cols || ', updated_at';
    insert_vals := insert_vals || ', COALESCE(up.updated_at, now())';
  ELSE
    insert_cols := insert_cols || ', updated_at';
    insert_vals := insert_vals || ', now()';
  END IF;

  -- Execute INSERT
  insert_sql := format(
    'INSERT INTO public.profiles (%s) SELECT %s FROM public.users_profiles up WHERE up.id NOT IN (SELECT id FROM public.profiles) ON CONFLICT (id) DO NOTHING',
    insert_cols,
    insert_vals
  );
  
  EXECUTE insert_sql;
  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE 'Inserted % new profiles from users_profiles', row_count;

  -- Build UPDATE statement dynamically
  update_set := 'updated_at = now()';
  
  IF has_nickname THEN
    update_set := update_set || ', nickname = COALESCE(up.nickname, p.nickname)';
  END IF;
  
  IF has_avatar_url THEN
    update_set := update_set || ', avatar_url = COALESCE(up.avatar_url, p.avatar_url)';
  END IF;
  
  IF has_role THEN
    update_set := update_set || ', role = COALESCE(up.role, p.role)';
  END IF;
  
  IF has_wechat_openid THEN
    update_set := update_set || ', wechat_openid = COALESCE(up.wechat_openid, p.wechat_openid)';
  END IF;
  
  IF has_wechat_unionid THEN
    update_set := update_set || ', wechat_unionid = COALESCE(up.wechat_unionid, p.wechat_unionid)';
  END IF;
  
  IF has_phone THEN
    update_set := update_set || ', phone = COALESCE(up.phone, p.phone)';
  END IF;

  -- Build WHERE clause for UPDATE
  update_sql := format(
    'UPDATE public.profiles p SET %s FROM public.users_profiles up WHERE p.id = up.id',
    update_set
  );
  
  -- Add conditions to only update if values differ
  -- Build WHERE conditions
  where_conditions := '';
  
  IF has_nickname THEN
    where_conditions := '(up.nickname IS NOT NULL AND up.nickname IS DISTINCT FROM p.nickname)';
  END IF;
  
  IF has_avatar_url THEN
    IF where_conditions != '' THEN
      where_conditions := where_conditions || ' OR ';
    END IF;
    where_conditions := where_conditions || '(up.avatar_url IS NOT NULL AND up.avatar_url IS DISTINCT FROM p.avatar_url)';
  END IF;
  
  IF has_role THEN
    IF where_conditions != '' THEN
      where_conditions := where_conditions || ' OR ';
    END IF;
    where_conditions := where_conditions || '(up.role IS NOT NULL AND up.role IS DISTINCT FROM p.role)';
  END IF;
  
  IF has_wechat_openid THEN
    IF where_conditions != '' THEN
      where_conditions := where_conditions || ' OR ';
    END IF;
    where_conditions := where_conditions || '(up.wechat_openid IS NOT NULL AND up.wechat_openid IS DISTINCT FROM p.wechat_openid)';
  END IF;
  
  IF has_wechat_unionid THEN
    IF where_conditions != '' THEN
      where_conditions := where_conditions || ' OR ';
    END IF;
    where_conditions := where_conditions || '(up.wechat_unionid IS NOT NULL AND up.wechat_unionid IS DISTINCT FROM p.wechat_unionid)';
  END IF;
  
  IF has_phone THEN
    IF where_conditions != '' THEN
      where_conditions := where_conditions || ' OR ';
    END IF;
    where_conditions := where_conditions || '(up.phone IS NOT NULL AND up.phone IS DISTINCT FROM p.phone)';
  END IF;
  
  -- Add WHERE conditions if any exist
  IF where_conditions != '' THEN
    update_sql := update_sql || ' AND (' || where_conditions || ')';
  END IF;

  -- Execute UPDATE
  EXECUTE update_sql;
  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE 'Updated % existing profiles from users_profiles', row_count;

  RAISE NOTICE 'Sync completed successfully!';
  
  -- Note: We don't drop the users_profiles table here to allow for verification
  -- You can manually drop it after verifying the sync is correct:
  -- DROP TABLE IF EXISTS public.users_profiles;

END $$;

-- Alternative: If users_profiles table structure is different, 
-- you may need to adjust the column mappings above.
-- Common variations might include:
-- - Different column names
-- - Additional columns not in profiles
-- - Different data types

-- To check the structure of users_profiles table (if it exists), run:
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_schema = 'public' 
-- AND table_name = 'users_profiles';

