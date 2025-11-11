-- Ensure master_settlements table exists
-- This migration ensures the table exists even if 20250115_add_settlement_workflow.sql wasn't applied

-- Create master_settlements table if it doesn't exist
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

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_master_settlements_master ON public.master_settlements(master_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_master_settlements_consultation ON public.master_settlements(consultation_id);
CREATE INDEX IF NOT EXISTS idx_master_settlements_status ON public.master_settlements(settlement_status);

-- Enable RLS
ALTER TABLE public.master_settlements ENABLE ROW LEVEL SECURITY;

-- Create RLS policies if they don't exist
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

-- Add comment
COMMENT ON TABLE public.master_settlements IS '卦师结算记录表，记录每笔咨询订单的结算详情';

-- Create trigger function for updated_at if it doesn't exist
CREATE OR REPLACE FUNCTION public.touch_master_settlement_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if it doesn't exist
DROP TRIGGER IF EXISTS trg_master_settlements_updated_at ON public.master_settlements;
CREATE TRIGGER trg_master_settlements_updated_at
  BEFORE UPDATE ON public.master_settlements
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_master_settlement_updated_at();

