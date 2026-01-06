-- ============================================
-- 添加用户封禁功能所需字段
-- ============================================

-- 检查并添加 is_banned 字段
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'is_banned'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN is_banned BOOLEAN DEFAULT FALSE NOT NULL;
    
    COMMENT ON COLUMN public.profiles.is_banned IS '用户是否被封禁';
  END IF;
END $$;

-- 检查并添加 banned_at 字段
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'banned_at'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN banned_at TIMESTAMPTZ;
    
    COMMENT ON COLUMN public.profiles.banned_at IS '用户被封禁的时间';
  END IF;
END $$;

-- 检查并添加 ban_reason 字段
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'ban_reason'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN ban_reason TEXT;
    
    COMMENT ON COLUMN public.profiles.ban_reason IS '用户被封禁的原因';
  END IF;
END $$;

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_profiles_is_banned 
  ON public.profiles(is_banned) 
  WHERE is_banned = TRUE;

-- ============================================
-- 确保 posts 表有 deleted 状态
-- ============================================

-- 检查 posts 表的 status 字段是否支持 'deleted'
-- 如果使用的是 CHECK 约束，可能需要更新

-- 注释：通常 status 字段使用 TEXT 类型，不需要额外配置
-- 只需确保应用层正确使用 'deleted' 值即可

-- 添加索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_posts_status_deleted 
  ON public.posts(status) 
  WHERE status = 'deleted';

CREATE INDEX IF NOT EXISTS idx_posts_status_hidden 
  ON public.posts(status) 
  WHERE status = 'hidden';

-- ============================================
-- 创建视图：查看被封禁用户
-- ============================================

CREATE OR REPLACE VIEW public.banned_users AS
SELECT 
  p.id,
  p.nickname,
  p.email,
  p.is_banned,
  p.banned_at,
  p.ban_reason,
  p.created_at,
  COUNT(DISTINCT pr.id) as report_count
FROM public.profiles p
LEFT JOIN public.posts posts ON p.id = posts.user_id
LEFT JOIN public.post_reports pr ON posts.id = pr.post_id
WHERE p.is_banned = TRUE
GROUP BY p.id, p.nickname, p.email, p.is_banned, p.banned_at, p.ban_reason, p.created_at
ORDER BY p.banned_at DESC;

COMMENT ON VIEW public.banned_users IS '查看所有被封禁的用户及其举报统计';

-- ============================================
-- 创建函数：解封用户
-- ============================================

CREATE OR REPLACE FUNCTION public.unban_user(
  p_user_id UUID,
  p_admin_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 解封用户
  UPDATE public.profiles
  SET 
    is_banned = FALSE,
    ban_reason = CASE 
      WHEN p_admin_note IS NOT NULL 
      THEN p_admin_note 
      ELSE ban_reason 
    END,
    updated_at = NOW()
  WHERE id = p_user_id;
  
  -- 发送通知给用户
  PERFORM public.create_notification(
    p_user_id,
    'system',
    p_user_id,
    'user',
    NULL,
    '您的账号已被解封，现在可以正常使用了。',
    jsonb_build_object(
      'action', 'user_unbanned',
      'admin_note', p_admin_note
    )
  );
  
  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to unban user: %', SQLERRM;
    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.unban_user IS '解封用户并发送通知';

-- ============================================
-- 测试查询
-- ============================================

-- 查看所有被封禁的用户
/*
SELECT * FROM public.banned_users;
*/

-- 查看被自动隐藏的帖子
/*
SELECT 
  p.id,
  p.title,
  p.user_id,
  p.status,
  p.updated_at,
  prof.nickname as author,
  COUNT(pr.id) as report_count
FROM public.posts p
LEFT JOIN public.profiles prof ON p.user_id = prof.id
LEFT JOIN public.post_reports pr ON p.id = pr.post_id AND pr.status = 'open'
WHERE p.status = 'hidden'
GROUP BY p.id, p.title, p.user_id, p.status, p.updated_at, prof.nickname
ORDER BY p.updated_at DESC;
*/

-- 查看最近的举报统计
/*
SELECT 
  post_id,
  COUNT(DISTINCT reporter_id) as unique_reporters,
  COUNT(*) as total_reports,
  array_agg(DISTINCT reporter_id) as reporter_ids,
  MIN(created_at) as first_report,
  MAX(created_at) as last_report
FROM public.post_reports
WHERE status = 'open'
  AND created_at > NOW() - INTERVAL '24 hours'
GROUP BY post_id
HAVING COUNT(DISTINCT reporter_id) >= 3
ORDER BY COUNT(DISTINCT reporter_id) DESC;
*/

