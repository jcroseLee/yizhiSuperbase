-- 确保 coin_transactions 表的 INSERT 策略存在
-- 修复 403 Forbidden 错误

-- 删除可能存在的旧策略（如果存在）
DROP POLICY IF EXISTS "coin_transactions_insert_own" ON public.coin_transactions;

-- 创建 INSERT 策略
CREATE POLICY "coin_transactions_insert_own"
  ON public.coin_transactions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 添加策略注释
COMMENT ON POLICY "coin_transactions_insert_own" ON public.coin_transactions IS 
  '允许用户插入自己的易币交易记录';

