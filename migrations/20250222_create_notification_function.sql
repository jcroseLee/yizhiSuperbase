-- 创建通知插入函数
-- 使用 SECURITY DEFINER 绕过 RLS 限制，允许系统为用户创建通知

CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id uuid,
  p_type text,
  p_related_id uuid,
  p_related_type text,
  p_actor_id uuid DEFAULT NULL,
  p_content text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notification_id uuid;
BEGIN
  -- 验证参数
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id cannot be null';
  END IF;

  IF p_type IS NULL OR p_related_id IS NULL OR p_related_type IS NULL THEN
    RAISE EXCEPTION 'type, related_id, and related_type are required';
  END IF;

  -- 插入通知
  INSERT INTO public.notifications (
    user_id,
    type,
    related_id,
    related_type,
    actor_id,
    content,
    metadata,
    is_read
  ) VALUES (
    p_user_id,
    p_type,
    p_related_id,
    p_related_type,
    p_actor_id,
    p_content,
    p_metadata,
    false
  ) RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create notification: %', SQLERRM;
END;
$$;

-- 添加函数注释
COMMENT ON FUNCTION public.create_notification IS 
  '创建通知函数：允许系统为用户创建通知。使用 SECURITY DEFINER 绕过 RLS 限制。';

-- 授予执行权限给所有认证用户
GRANT EXECUTE ON FUNCTION public.create_notification TO authenticated;

