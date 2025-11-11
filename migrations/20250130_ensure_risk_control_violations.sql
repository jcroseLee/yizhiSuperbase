-- Ensure risk_control_violations table exists with proper foreign keys
-- This migration ensures the table is created even if the original migration
-- failed due to missing foreign key references

-- Create the table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.risk_control_violations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  violation_type text NOT NULL CHECK (violation_type IN ('private_transaction', 'inappropriate_content', 'spam')),
  detected_content text NOT NULL,
  message_id uuid,
  action_taken text CHECK (action_taken IN ('warning', 'blocked', 'reported')),
  is_resolved boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

-- Add foreign key constraints if the referenced tables exist
DO $$
BEGIN
  -- Add consultation_id foreign key if consultations table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'consultations') THEN
    -- Drop existing constraint if it exists with wrong definition
    IF EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_schema = 'public' 
      AND table_name = 'risk_control_violations' 
      AND constraint_name = 'risk_control_violations_consultation_id_fkey'
    ) THEN
      ALTER TABLE public.risk_control_violations DROP CONSTRAINT risk_control_violations_consultation_id_fkey;
    END IF;
    
    -- Add the constraint if it doesn't exist
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_schema = 'public' 
      AND table_name = 'risk_control_violations' 
      AND constraint_name = 'risk_control_violations_consultation_id_fkey'
    ) THEN
      ALTER TABLE public.risk_control_violations
        ADD CONSTRAINT risk_control_violations_consultation_id_fkey
        FOREIGN KEY (consultation_id) REFERENCES public.consultations(id) ON DELETE CASCADE;
    END IF;
  END IF;

  -- Add message_id foreign key if messages table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'messages') THEN
    -- Drop existing constraint if it exists with wrong definition
    IF EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_schema = 'public' 
      AND table_name = 'risk_control_violations' 
      AND constraint_name = 'risk_control_violations_message_id_fkey'
    ) THEN
      ALTER TABLE public.risk_control_violations DROP CONSTRAINT risk_control_violations_message_id_fkey;
    END IF;
    
    -- Add the constraint if it doesn't exist
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE constraint_schema = 'public' 
      AND table_name = 'risk_control_violations' 
      AND constraint_name = 'risk_control_violations_message_id_fkey'
    ) THEN
      ALTER TABLE public.risk_control_violations
        ADD CONSTRAINT risk_control_violations_message_id_fkey
        FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_risk_control_consultation ON public.risk_control_violations(consultation_id);
CREATE INDEX IF NOT EXISTS idx_risk_control_user ON public.risk_control_violations(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_control_resolved ON public.risk_control_violations(is_resolved);

-- Enable RLS
ALTER TABLE public.risk_control_violations ENABLE ROW LEVEL SECURITY;

-- Create RLS policies if they don't exist
DO $$
BEGIN
  -- Drop existing policies if they exist (to recreate with correct definition)
  DROP POLICY IF EXISTS "risk_control_violations_select_own" ON public.risk_control_violations;
  DROP POLICY IF EXISTS "risk_control_violations_admin_all" ON public.risk_control_violations;

  -- Users can view their own violations
  CREATE POLICY "risk_control_violations_select_own"
    ON public.risk_control_violations FOR SELECT
    USING (auth.uid() = user_id);

  -- Admins can do all operations (SELECT, INSERT, UPDATE, DELETE)
  -- This policy uses a more robust check that handles NULL cases
  CREATE POLICY "risk_control_violations_admin_all"
    ON public.risk_control_violations FOR ALL
    USING (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    )
    WITH CHECK (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    );
END $$;

-- Add table comment
COMMENT ON TABLE public.risk_control_violations IS '风控违规记录表，记录聊天中的违规行为';

