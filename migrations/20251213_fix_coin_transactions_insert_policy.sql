-- Fix coin_transactions RLS policy to allow users to insert their own transactions
-- The original migration (20250110_add_user_growth_economy_system.sql) only had a SELECT policy,
-- but the client code (growth.ts) needs to insert records directly

DO $$
BEGIN
  -- Add INSERT policy if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'coin_transactions' 
    AND policyname = 'coin_transactions_insert_own'
  ) THEN
    CREATE POLICY "coin_transactions_insert_own"
      ON public.coin_transactions FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Add comment if policy exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'coin_transactions' 
    AND policyname = 'coin_transactions_insert_own'
  ) THEN
    COMMENT ON POLICY "coin_transactions_insert_own" ON public.coin_transactions IS 
      '允许用户插入自己的易币交易记录';
  END IF;
END $$;

