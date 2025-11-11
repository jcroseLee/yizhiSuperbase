-- Add online status and minimum consultation price to masters table
ALTER TABLE public.masters
  ADD COLUMN IF NOT EXISTS online_status text DEFAULT 'offline' CHECK (online_status IN ('online', 'busy', 'offline')),
  ADD COLUMN IF NOT EXISTS min_price numeric(10, 2) DEFAULT 0 CHECK (min_price >= 0);

-- Create consultations table to track master orders
CREATE TABLE IF NOT EXISTS public.consultations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_id uuid REFERENCES public.masters(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'completed', 'cancelled')),
  price numeric(10, 2) NOT NULL CHECK (price >= 0),
  question text,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  updated_at timestamptz DEFAULT now()
);

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_consultations_master_id ON public.consultations(master_id);
CREATE INDEX IF NOT EXISTS idx_consultations_created_at ON public.consultations(created_at);
CREATE INDEX IF NOT EXISTS idx_consultations_status ON public.consultations(status);

-- Enable RLS
ALTER TABLE public.consultations ENABLE ROW LEVEL SECURITY;

-- RLS policies for consultations
DO $$
BEGIN
  -- Allow users to view their own consultations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'consultations' 
    AND policyname = 'consultations_select_own'
  ) THEN
    CREATE POLICY "consultations_select_own"
      ON public.consultations FOR SELECT
      USING (auth.uid() = user_id OR auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
  
  -- Allow users to create consultations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'consultations' 
    AND policyname = 'consultations_insert_own'
  ) THEN
    CREATE POLICY "consultations_insert_own"
      ON public.consultations FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
  
  -- Allow masters to update consultations for their own orders
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'consultations' 
    AND policyname = 'consultations_update_master'
  ) THEN
    CREATE POLICY "consultations_update_master"
      ON public.consultations FOR UPDATE
      USING (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id))
      WITH CHECK (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
  
  -- Allow users to update their own consultations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'consultations' 
    AND policyname = 'consultations_update_own'
  ) THEN
    CREATE POLICY "consultations_update_own"
      ON public.consultations FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Function to update consultation updated_at
CREATE OR REPLACE FUNCTION update_consultation_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update updated_at when consultation is updated
DROP TRIGGER IF EXISTS update_consultation_updated_at_trigger ON public.consultations;
CREATE TRIGGER update_consultation_updated_at_trigger
  BEFORE UPDATE ON public.consultations
  FOR EACH ROW EXECUTE FUNCTION update_consultation_updated_at();

-- Function to calculate 30-day order count for a master
CREATE OR REPLACE FUNCTION get_master_orders_30d(master_uuid uuid)
RETURNS integer AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM public.consultations
    WHERE master_id = master_uuid
      AND status = 'completed'
      AND created_at >= now() - INTERVAL '30 days'
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get 30-day order counts for multiple masters (batch)
CREATE OR REPLACE FUNCTION get_master_orders_30d_batch(master_ids uuid[])
RETURNS TABLE(master_id uuid, count bigint) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.master_id,
    COUNT(*)::bigint as count
  FROM public.consultations c
  WHERE c.master_id = ANY(master_ids)
    AND c.status = 'completed'
    AND c.created_at >= now() - INTERVAL '30 days'
  GROUP BY c.master_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permission on RPC functions
GRANT EXECUTE ON FUNCTION get_master_orders_30d(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_master_orders_30d_batch(uuid[]) TO authenticated, anon;

-- Comment on columns
COMMENT ON COLUMN public.masters.online_status IS '在线状态: online(在线), busy(忙碌), offline(离线)';
COMMENT ON COLUMN public.masters.min_price IS '最低咨询价格（元）';
COMMENT ON TABLE public.consultations IS '咨询订单表，用于记录用户向卦师的咨询订单';

