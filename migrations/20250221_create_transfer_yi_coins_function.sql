-- 创建易币转账函数
-- 使用 SECURITY DEFINER 绕过 RLS 限制，允许系统为用户之间转账

CREATE OR REPLACE FUNCTION public.transfer_yi_coins(
  p_from_user_id uuid,
  p_to_user_id uuid,
  p_amount numeric,
  p_type text,
  p_description text DEFAULT NULL,
  p_related_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_from_balance numeric;
  v_to_balance numeric;
  v_from_new_balance numeric;
  v_to_new_balance numeric;
  v_result jsonb;
BEGIN
  -- 验证参数
  IF p_amount <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '转账金额必须大于0'
    );
  END IF;

  IF p_from_user_id = p_to_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '不能转账给自己'
    );
  END IF;

  -- 检查发送者余额
  SELECT yi_coins INTO v_from_balance
  FROM public.profiles
  WHERE id = p_from_user_id;

  IF v_from_balance IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '发送者信息不存在'
    );
  END IF;

  IF (v_from_balance < p_amount) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '易币余额不足'
    );
  END IF;

  -- 检查接收者是否存在
  SELECT yi_coins INTO v_to_balance
  FROM public.profiles
  WHERE id = p_to_user_id;

  IF v_to_balance IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '接收者信息不存在'
    );
  END IF;

  -- 计算新余额
  v_from_new_balance := v_from_balance - p_amount;
  v_to_new_balance := COALESCE(v_to_balance, 0) + p_amount;

  -- 更新发送者余额
  UPDATE public.profiles
  SET yi_coins = v_from_new_balance
  WHERE id = p_from_user_id;

  -- 更新接收者余额
  UPDATE public.profiles
  SET yi_coins = v_to_new_balance
  WHERE id = p_to_user_id;

  -- 记录发送者交易流水
  INSERT INTO public.coin_transactions (
    user_id,
    amount,
    type,
    description,
    related_id
  ) VALUES (
    p_from_user_id,
    -p_amount,
    p_type,
    COALESCE(p_description, '转账给其他用户'),
    p_related_id
  );

  -- 记录接收者交易流水
  INSERT INTO public.coin_transactions (
    user_id,
    amount,
    type,
    description,
    related_id
  ) VALUES (
    p_to_user_id,
    p_amount,
    p_type,
    COALESCE(p_description, '收到转账'),
    p_related_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', '转账成功',
    'from_balance', v_from_new_balance,
    'to_balance', v_to_new_balance
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', '转账失败: ' || SQLERRM
    );
END;
$$;

-- 添加函数注释
COMMENT ON FUNCTION public.transfer_yi_coins IS 
  '易币转账函数：从发送者转给接收者，自动更新余额并记录交易流水。使用 SECURITY DEFINER 绕过 RLS 限制。';

-- 授予执行权限给所有认证用户
GRANT EXECUTE ON FUNCTION public.transfer_yi_coins TO authenticated;

