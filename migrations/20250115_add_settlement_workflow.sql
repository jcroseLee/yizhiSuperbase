-- Add settlement workflow for consultation orders
-- This migration adds settlement-related fields and logic for the payment flow

-- ===============================
-- Extend consultations table with settlement fields
-- ===============================
ALTER TABLE public.consultations
  ADD COLUMN IF NOT EXISTS settlement_status text CHECK (settlement_status IN ('pending', 'settled', 'cancelled')) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS settlement_scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS settlement_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS platform_fee_rate numeric(5,4) DEFAULT 0.10 CHECK (platform_fee_rate >= 0 AND platform_fee_rate <= 1),
  ADD COLUMN IF NOT EXISTS platform_fee_amount numeric(12,2),
  ADD COLUMN IF NOT EXISTS master_payout_amount numeric(12,2),
  ADD COLUMN IF NOT EXISTS review_required boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS review_submitted boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS review_id uuid REFERENCES public.master_reviews(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.consultations.settlement_status IS '结算状态：pending(待结算), settled(已结算), cancelled(已取消)';
COMMENT ON COLUMN public.consultations.settlement_scheduled_at IS '计划结算时间（T+7，即咨询完成后的第7天）';
COMMENT ON COLUMN public.consultations.settlement_completed_at IS '实际结算完成时间';
COMMENT ON COLUMN public.consultations.platform_fee_rate IS '平台服务费率（默认10%）';
COMMENT ON COLUMN public.consultations.platform_fee_amount IS '平台服务费金额（佣金）';
COMMENT ON COLUMN public.consultations.master_payout_amount IS '卦师实际结算金额（扣除服务费后）';
COMMENT ON COLUMN public.consultations.review_required IS '是否需要评价（咨询完成后必须评价）';
COMMENT ON COLUMN public.consultations.review_submitted IS '是否已提交评价';
COMMENT ON COLUMN public.consultations.review_id IS '关联的评价记录ID';

-- Update status check constraint to include pending_settlement
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

ALTER TABLE public.consultations
  ADD CONSTRAINT consultations_status_check
  CHECK (
    status IN (
      'pending_payment',
      'awaiting_master',
      'in_progress',
      'pending_settlement',
      'completed',
      'cancelled',
      'refunded',
      'timeout_cancelled'
    )
  );

-- ===============================
-- Create master settlements table for payout tracking
-- ===============================
CREATE TABLE IF NOT EXISTS public.master_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_id uuid REFERENCES public.masters(id) ON DELETE CASCADE NOT NULL,
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE NOT NULL,
  total_amount numeric(12,2) NOT NULL CHECK (total_amount >= 0),
  platform_fee_amount numeric(12,2) NOT NULL CHECK (platform_fee_amount >= 0),
  payout_amount numeric(12,2) NOT NULL CHECK (payout_amount >= 0),
  settlement_status text NOT NULL CHECK (settlement_status IN ('pending', 'processing', 'completed', 'failed')) DEFAULT 'pending',
  payout_method text CHECK (payout_method IN ('wechat', 'bank', 'alipay')),
  payout_account text,
  payout_transaction_no text,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_master_settlements_master ON public.master_settlements(master_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_master_settlements_consultation ON public.master_settlements(consultation_id);
CREATE INDEX IF NOT EXISTS idx_master_settlements_status ON public.master_settlements(settlement_status);

ALTER TABLE public.master_settlements ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'master_settlements'
      AND policyname = 'master_settlements_select_own'
  ) THEN
    CREATE POLICY "master_settlements_select_own"
      ON public.master_settlements FOR SELECT
      USING (
        auth.uid() IN (
          SELECT m.user_id
          FROM public.masters m
          WHERE m.id = master_id
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'master_settlements'
      AND policyname = 'master_settlements_admin_all'
  ) THEN
    CREATE POLICY "master_settlements_admin_all"
      ON public.master_settlements FOR ALL
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

COMMENT ON TABLE public.master_settlements IS '卦师结算记录表，记录每笔咨询订单的结算详情';

-- ===============================
-- Create platform escrow account tracking
-- ===============================
CREATE TABLE IF NOT EXISTS public.platform_escrow (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE NOT NULL UNIQUE,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status text NOT NULL CHECK (status IN ('held', 'released', 'refunded')) DEFAULT 'held',
  held_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_platform_escrow_status ON public.platform_escrow(status);
CREATE INDEX IF NOT EXISTS idx_platform_escrow_held_at ON public.platform_escrow(held_at);

ALTER TABLE public.platform_escrow ENABLE ROW LEVEL SECURITY;

-- Only admins can view escrow records
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'platform_escrow'
      AND policyname = 'platform_escrow_admin_select'
  ) THEN
    CREATE POLICY "platform_escrow_admin_select"
      ON public.platform_escrow FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

COMMENT ON TABLE public.platform_escrow IS '平台托管账户记录，记录每笔订单的资金托管情况';

-- ===============================
-- Create risk control violations table
-- ===============================
CREATE TABLE IF NOT EXISTS public.risk_control_violations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  violation_type text NOT NULL CHECK (violation_type IN ('private_transaction', 'inappropriate_content', 'spam')),
  detected_content text NOT NULL,
  message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  action_taken text CHECK (action_taken IN ('warning', 'blocked', 'reported')),
  is_resolved boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_risk_control_consultation ON public.risk_control_violations(consultation_id);
CREATE INDEX IF NOT EXISTS idx_risk_control_user ON public.risk_control_violations(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_control_resolved ON public.risk_control_violations(is_resolved);

ALTER TABLE public.risk_control_violations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Users can view their own violations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'risk_control_violations'
      AND policyname = 'risk_control_violations_select_own'
  ) THEN
    CREATE POLICY "risk_control_violations_select_own"
      ON public.risk_control_violations FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  -- Admins can view all violations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'risk_control_violations'
      AND policyname = 'risk_control_violations_admin_all'
  ) THEN
    CREATE POLICY "risk_control_violations_admin_all"
      ON public.risk_control_violations FOR ALL
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

COMMENT ON TABLE public.risk_control_violations IS '风控违规记录表，记录聊天中的违规行为';

-- ===============================
-- Function to calculate settlement amounts
-- ===============================
CREATE OR REPLACE FUNCTION public.calculate_settlement_amounts(
  p_consultation_id uuid
)
RETURNS TABLE (
  total_amount numeric,
  platform_fee_amount numeric,
  payout_amount numeric
) AS $$
DECLARE
  v_price numeric;
  v_fee_rate numeric;
  v_platform_fee numeric;
  v_payout numeric;
BEGIN
  SELECT price, COALESCE(platform_fee_rate, 0.10)
  INTO v_price, v_fee_rate
  FROM public.consultations
  WHERE id = p_consultation_id;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'Consultation not found';
  END IF;

  v_platform_fee := ROUND(v_price * v_fee_rate, 2);
  v_payout := v_price - v_platform_fee;

  RETURN QUERY SELECT v_price, v_platform_fee, v_payout;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.calculate_settlement_amounts(uuid) TO authenticated, service_role;

-- ===============================
-- Function to schedule settlement (T+7)
-- ===============================
CREATE OR REPLACE FUNCTION public.schedule_settlement(
  p_consultation_id uuid
)
RETURNS void AS $$
DECLARE
  v_amounts RECORD;
BEGIN
  -- Calculate settlement amounts
  SELECT * INTO v_amounts
  FROM public.calculate_settlement_amounts(p_consultation_id);

  -- Update consultation with settlement info
  UPDATE public.consultations
  SET
    settlement_status = 'pending',
    settlement_scheduled_at = now() + INTERVAL '7 days',
    platform_fee_amount = v_amounts.platform_fee_amount,
    master_payout_amount = v_amounts.payout_amount,
    review_required = true
  WHERE id = p_consultation_id;

  -- Create settlement record
  INSERT INTO public.master_settlements (
    master_id,
    consultation_id,
    total_amount,
    platform_fee_amount,
    payout_amount,
    settlement_status
  )
  SELECT
    master_id,
    p_consultation_id,
    v_amounts.total_amount,
    v_amounts.platform_fee_amount,
    v_amounts.payout_amount,
    'pending'
  FROM public.consultations
  WHERE id = p_consultation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.schedule_settlement(uuid) TO authenticated, service_role;

-- ===============================
-- Trigger to update master_settlements.updated_at
-- ===============================
CREATE OR REPLACE FUNCTION public.touch_master_settlement_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_master_settlements_updated_at ON public.master_settlements;
CREATE TRIGGER trg_master_settlements_updated_at
  BEFORE UPDATE ON public.master_settlements
  FOR EACH ROW
  EXECUTE PROCEDURE public.touch_master_settlement_updated_at();

