-- Enhance consultation order workflow with service linkage, payment tracking, and chat support

-- ===============================
-- Helper function to drop constraint if exists
-- ===============================
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.consultations'::regclass
    AND contype = 'c'
    AND conname = 'consultations_status_check';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.consultations DROP CONSTRAINT %I', constraint_name);
  END IF;
END;
$$;

-- ===============================
-- Extend consultations table
-- ===============================
ALTER TABLE public.consultations
  ADD COLUMN IF NOT EXISTS service_id uuid REFERENCES public.master_services(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_method text CHECK (payment_method IN ('wechat', 'balance')) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS payment_status text CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'refunded', 'failed')) DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS agreement_accepted boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS birth_time time,
  ADD COLUMN IF NOT EXISTS birth_place text,
  ADD COLUMN IF NOT EXISTS gender text CHECK (gender IN ('male', 'female', 'unknown')),
  ADD COLUMN IF NOT EXISTS contact_info text,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS consultation_channel text CHECK (consultation_channel IN ('text', 'voice')) DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS remaining_sessions integer DEFAULT 1 CHECK (remaining_sessions >= 0),
  ADD COLUMN IF NOT EXISTS remaining_minutes integer CHECK (remaining_minutes >= 0),
  ADD COLUMN IF NOT EXISTS question_summary text,
  ADD COLUMN IF NOT EXISTS chat_room_id uuid DEFAULT gen_random_uuid();

-- Ensure question field is mandatory with length limit
UPDATE public.consultations
SET question = '系统补全：历史订单未填写问题描述，请联系平台客服。'
WHERE question IS NULL OR char_length(question) < 30;

ALTER TABLE public.consultations
  ALTER COLUMN question SET NOT NULL,
  ADD CONSTRAINT consultations_question_length_check CHECK (char_length(question) BETWEEN 30 AND 800);

ALTER TABLE public.consultations
  ALTER COLUMN status SET DEFAULT 'pending_payment';

COMMENT ON COLUMN public.consultations.question IS '用户在下单时提交的问题描述，必填，限字数';
COMMENT ON COLUMN public.consultations.question_summary IS '后台生成或用户填写的精简问题摘要';
COMMENT ON COLUMN public.consultations.chat_room_id IS '咨询专属聊天室 ID';

-- Update consultation status check constraint with new flow
ALTER TABLE public.consultations
  ADD CONSTRAINT consultations_status_check
  CHECK (
    status IN (
      'pending_payment',
      'awaiting_master',
      'in_progress',
      'completed',
      'cancelled',
      'refunded',
      'timeout_cancelled'
    )
  );

-- Set default status for existing rows if necessary
UPDATE public.consultations
SET status = 'awaiting_master'
WHERE status NOT IN ('pending_payment', 'awaiting_master', 'in_progress', 'completed', 'cancelled', 'refunded', 'timeout_cancelled');

-- Backfill expires_at for rows without value (default 24 hours from creation)
UPDATE public.consultations
SET expires_at = created_at + INTERVAL '24 hours'
WHERE expires_at IS NULL;

-- ===============================
-- Update master_services metadata
-- ===============================
ALTER TABLE public.master_services
  ADD COLUMN IF NOT EXISTS consultation_duration_minutes integer CHECK (consultation_duration_minutes >= 0),
  ADD COLUMN IF NOT EXISTS consultation_session_count integer DEFAULT 1 CHECK (consultation_session_count > 0),
  ADD COLUMN IF NOT EXISTS requires_birth_info boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS question_min_length integer DEFAULT 30 CHECK (question_min_length BETWEEN 10 AND 2000),
  ADD COLUMN IF NOT EXISTS question_max_length integer DEFAULT 500 CHECK (question_max_length BETWEEN 50 AND 2000 AND question_max_length >= question_min_length);

COMMENT ON COLUMN public.master_services.consultation_duration_minutes IS '服务时长（分钟），用于展示剩余服务时长';
COMMENT ON COLUMN public.master_services.consultation_session_count IS '包含的服务次数';
COMMENT ON COLUMN public.master_services.requires_birth_info IS '是否要求填写出生信息';
COMMENT ON COLUMN public.master_services.question_min_length IS '问题描述最小字数要求';
COMMENT ON COLUMN public.master_services.question_max_length IS '问题描述最大字数要求';

-- ===============================
-- Payment tracking tables
-- ===============================
CREATE TABLE IF NOT EXISTS public.user_wallets (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance numeric(12,2) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_wallets ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_wallets'
      AND policyname = 'user_wallets_select_own'
  ) THEN
    CREATE POLICY "user_wallets_select_own"
      ON public.user_wallets FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_wallets'
      AND policyname = 'user_wallets_update_admin'
  ) THEN
    CREATE POLICY "user_wallets_update_admin"
      ON public.user_wallets FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL,
  direction text NOT NULL CHECK (direction IN ('credit', 'debit')),
  balance_after numeric(12,2) NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user ON public.wallet_transactions(user_id, created_at DESC);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'wallet_transactions'
      AND policyname = 'wallet_transactions_select_own'
  ) THEN
    CREATE POLICY "wallet_transactions_select_own"
      ON public.wallet_transactions FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'wallet_transactions'
      AND policyname = 'wallet_transactions_insert_admin'
  ) THEN
    CREATE POLICY "wallet_transactions_insert_admin"
      ON public.wallet_transactions FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

COMMENT ON TABLE public.wallet_transactions IS '余额变动流水';

-- Payment transactions for external providers (e.g., WeChat Pay)
CREATE TABLE IF NOT EXISTS public.payment_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('wechat')),
  provider_trade_no text,
  amount numeric(12,2) NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'prepay_created', 'paid', 'refunded', 'failed')),
  raw_response jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_consultation ON public.payment_transactions(consultation_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON public.payment_transactions(user_id, created_at DESC);
ALTER TABLE public.payment_transactions
  ADD CONSTRAINT payment_transactions_consultation_unique UNIQUE (consultation_id);

ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_transactions'
      AND policyname = 'payment_transactions_select_own'
  ) THEN
    CREATE POLICY "payment_transactions_select_own"
      ON public.payment_transactions FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_transactions'
      AND policyname = 'payment_transactions_insert_admin'
  ) THEN
    CREATE POLICY "payment_transactions_insert_admin"
      ON public.payment_transactions FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_transactions'
      AND policyname = 'payment_transactions_update_admin'
  ) THEN
    CREATE POLICY "payment_transactions_update_admin"
      ON public.payment_transactions FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

COMMENT ON TABLE public.payment_transactions IS '第三方支付流水记录';

-- ===============================
-- Messages: link to consultation chat room
-- ===============================
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS message_type text DEFAULT 'chat' CHECK (message_type IN ('chat', 'system')),
  ADD COLUMN IF NOT EXISTS metadata jsonb;

COMMENT ON COLUMN public.messages.consultation_id IS '所属咨询订单的聊天室ID';
COMMENT ON COLUMN public.messages.message_type IS '消息类型：chat 或 system';
COMMENT ON COLUMN public.messages.metadata IS '附加元信息';

-- Ensure policy allows participants of linked consultation
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'messages'
      AND policyname = 'messages_select_own'
  ) THEN
    DROP POLICY "messages_select_own" ON public.messages;
  END IF;

  CREATE POLICY "messages_select_own"
    ON public.messages FOR SELECT
    USING (
      auth.uid() = sender_id
      OR auth.uid() = receiver_id
      OR (
        consultation_id IS NOT NULL
        AND auth.uid() IN (
          SELECT c.user_id
          FROM public.consultations c
          WHERE c.id = consultation_id
          UNION
          SELECT m.user_id
          FROM public.masters m
          INNER JOIN public.consultations c2 ON c2.master_id = m.id
          WHERE c2.id = consultation_id
        )
      )
    );

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'messages'
      AND policyname = 'messages_insert_own'
  ) THEN
    DROP POLICY "messages_insert_own" ON public.messages;
  END IF;

  CREATE POLICY "messages_insert_own"
    ON public.messages FOR INSERT
    WITH CHECK (
      auth.uid() = sender_id
      AND (
        consultation_id IS NULL
        OR auth.uid() IN (
          SELECT c.user_id
          FROM public.consultations c
          WHERE c.id = consultation_id
          UNION
          SELECT m.user_id
          FROM public.masters m
          INNER JOIN public.consultations c2 ON c2.master_id = m.id
          WHERE c2.id = consultation_id
        )
      )
    );
END $$;

-- ===============================
-- Trigger to keep payment_transactions.updated_at
-- ===============================
CREATE OR REPLACE FUNCTION public.touch_payment_transaction_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_payment_transactions_updated_at ON public.payment_transactions;
CREATE TRIGGER trg_payment_transactions_updated_at
  BEFORE UPDATE ON public.payment_transactions
  FOR EACH ROW
  EXECUTE PROCEDURE public.touch_payment_transaction_updated_at();

-- ===============================
-- Wallet helper function
-- ===============================
CREATE OR REPLACE FUNCTION public.adjust_user_wallet(
  p_user_id uuid,
  p_amount numeric,
  p_direction text,
  p_consultation_id uuid,
  p_description text DEFAULT NULL
)
RETURNS TABLE (
  transaction_id uuid,
  balance_after numeric
) AS $$
DECLARE
  new_balance numeric;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION '金额必须大于0';
  END IF;
  IF p_direction NOT IN ('credit', 'debit') THEN
    RAISE EXCEPTION 'Invalid wallet direction %', p_direction;
  END IF;

  -- Ensure wallet row exists
  INSERT INTO public.user_wallets (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  IF p_direction = 'debit' THEN
    UPDATE public.user_wallets
    SET balance = balance - p_amount,
        updated_at = now()
    WHERE user_id = p_user_id
      AND balance >= p_amount
    RETURNING balance INTO new_balance;

    IF new_balance IS NULL THEN
      RAISE EXCEPTION '余额不足';
    END IF;
  ELSE
    UPDATE public.user_wallets
    SET balance = balance + p_amount,
        updated_at = now()
    WHERE user_id = p_user_id
    RETURNING balance INTO new_balance;
  END IF;

  INSERT INTO public.wallet_transactions (
    user_id,
    consultation_id,
    amount,
    direction,
    balance_after,
    description
  )
  VALUES (
    p_user_id,
    p_consultation_id,
    p_amount,
    p_direction,
    new_balance,
    p_description
  )
  RETURNING id, balance_after INTO transaction_id, balance_after;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.adjust_user_wallet(uuid, numeric, text, uuid, text) TO authenticated, service_role;


