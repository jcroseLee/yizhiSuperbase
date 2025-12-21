-- 修复易币明细缺失问题
-- 对于有易币余额但没有对应交易记录的用户，创建初始交易记录

-- 首先，检查指定用户的情况
DO $$
DECLARE
  target_user_id uuid := '8f34ea2f-0cc5-4d83-869a-1a7a1461b5d4';
  user_balance integer;
  total_transactions integer;
  missing_amount integer;
BEGIN
  -- 获取用户当前易币余额
  SELECT COALESCE(yi_coins, 0) INTO user_balance
  FROM public.profiles
  WHERE id = target_user_id;

  -- 获取用户所有交易记录的总和
  SELECT COALESCE(SUM(amount), 0) INTO total_transactions
  FROM public.coin_transactions
  WHERE user_id = target_user_id;

  -- 计算缺失的金额
  missing_amount := user_balance - total_transactions;

  RAISE NOTICE '用户 % 的易币余额: %, 交易记录总和: %, 缺失金额: %', 
    target_user_id, user_balance, total_transactions, missing_amount;

  -- 如果缺失金额大于0，创建初始交易记录
  IF missing_amount > 0 THEN
    INSERT INTO public.coin_transactions (
      user_id,
      amount,
      type,
      description,
      created_at
    ) VALUES (
      target_user_id,
      missing_amount,
      'reward',
      '系统初始化易币（历史余额补偿）',
      NOW() - INTERVAL '1 day'  -- 设置为1天前，避免显示在最前面
    );
    
    RAISE NOTICE '已为用户 % 创建初始交易记录，金额: %', target_user_id, missing_amount;
  ELSIF missing_amount < 0 THEN
    RAISE WARNING '用户 % 的交易记录总和 (%) 大于余额 (%)，可能存在数据不一致', 
      target_user_id, total_transactions, user_balance;
  ELSE
    RAISE NOTICE '用户 % 的易币余额与交易记录一致', target_user_id;
  END IF;
END $$;

-- 通用修复：为所有有易币余额但交易记录不匹配的用户创建初始记录
-- 注意：这个操作可能需要一些时间，建议在低峰期执行
DO $$
DECLARE
  user_record RECORD;
  user_balance integer;
  total_transactions integer;
  missing_amount integer;
  fixed_count integer := 0;
BEGIN
  -- 遍历所有有易币余额的用户
  FOR user_record IN 
    SELECT id, COALESCE(yi_coins, 0) as balance
    FROM public.profiles
    WHERE COALESCE(yi_coins, 0) > 0
  LOOP
    -- 获取该用户的交易记录总和
    SELECT COALESCE(SUM(amount), 0) INTO total_transactions
    FROM public.coin_transactions
    WHERE user_id = user_record.id;

    -- 计算缺失的金额
    missing_amount := user_record.balance - total_transactions;

    -- 如果缺失金额大于0，创建初始交易记录
    IF missing_amount > 0 THEN
      INSERT INTO public.coin_transactions (
        user_id,
        amount,
        type,
        description,
        created_at
      ) VALUES (
        user_record.id,
        missing_amount,
        'reward',
        '系统初始化易币（历史余额补偿）',
        NOW() - INTERVAL '1 day'
      );
      
      fixed_count := fixed_count + 1;
      
      RAISE NOTICE '已为用户 % 创建初始交易记录，金额: %', user_record.id, missing_amount;
    END IF;
  END LOOP;

  RAISE NOTICE '修复完成，共处理 % 个用户', fixed_count;
END $$;

