-- Ensure platform_escrow table exists with proper RLS policies
-- This migration ensures the table is created even if the previous migration wasn't applied

-- Create the table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.platform_escrow (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid REFERENCES public.consultations(id) ON DELETE CASCADE NOT NULL UNIQUE,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status text NOT NULL CHECK (status IN ('held', 'released', 'refunded')) DEFAULT 'held',
  held_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_platform_escrow_status ON public.platform_escrow(status);
CREATE INDEX IF NOT EXISTS idx_platform_escrow_held_at ON public.platform_escrow(held_at);
CREATE INDEX IF NOT EXISTS idx_platform_escrow_consultation_id ON public.platform_escrow(consultation_id);

-- Enable RLS
ALTER TABLE public.platform_escrow ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if it exists (to recreate with correct definition)
DROP POLICY IF EXISTS "platform_escrow_admin_select" ON public.platform_escrow;

-- Create admin select policy
CREATE POLICY "platform_escrow_admin_select"
  ON public.platform_escrow FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
  );

-- Add admin insert/update/delete policies if they don't exist
DO $$
BEGIN
  -- Insert policy for admins
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'platform_escrow'
      AND policyname = 'platform_escrow_admin_insert'
  ) THEN
    CREATE POLICY "platform_escrow_admin_insert"
      ON public.platform_escrow FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;

  -- Update policy for admins
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'platform_escrow'
      AND policyname = 'platform_escrow_admin_update'
  ) THEN
    CREATE POLICY "platform_escrow_admin_update"
      ON public.platform_escrow FOR UPDATE
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

  -- Delete policy for admins
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'platform_escrow'
      AND policyname = 'platform_escrow_admin_delete'
  ) THEN
    CREATE POLICY "platform_escrow_admin_delete"
      ON public.platform_escrow FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

-- Add table comment
COMMENT ON TABLE public.platform_escrow IS '平台托管账户记录，记录每笔订单的资金托管情况';

