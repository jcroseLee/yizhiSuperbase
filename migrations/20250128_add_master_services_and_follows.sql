-- Master services table for service items
CREATE TABLE IF NOT EXISTS public.master_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_id uuid REFERENCES public.masters(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  price numeric(10, 2) NOT NULL CHECK (price >= 0),
  service_type text NOT NULL CHECK (service_type IN ('图文', '语音')),
  description text,
  is_active boolean DEFAULT true,
  order_index integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_master_services_master_id ON public.master_services(master_id);
CREATE INDEX IF NOT EXISTS idx_master_services_is_active ON public.master_services(is_active);

-- Enable RLS
ALTER TABLE public.master_services ENABLE ROW LEVEL SECURITY;

-- RLS policies for master_services
DO $$
BEGIN
  -- Allow everyone to view active services
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_services' 
    AND policyname = 'master_services_select_all'
  ) THEN
    CREATE POLICY "master_services_select_all"
      ON public.master_services FOR SELECT
      USING (is_active = true);
  END IF;
  
  -- Allow masters to view their own services (including inactive)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_services' 
    AND policyname = 'master_services_select_own'
  ) THEN
    CREATE POLICY "master_services_select_own"
      ON public.master_services FOR SELECT
      USING (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
  
  -- Allow masters to insert their own services
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_services' 
    AND policyname = 'master_services_insert_own'
  ) THEN
    CREATE POLICY "master_services_insert_own"
      ON public.master_services FOR INSERT
      WITH CHECK (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
  
  -- Allow masters to update their own services
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_services' 
    AND policyname = 'master_services_update_own'
  ) THEN
    CREATE POLICY "master_services_update_own"
      ON public.master_services FOR UPDATE
      USING (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id))
      WITH CHECK (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
  
  -- Allow masters to delete their own services
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_services' 
    AND policyname = 'master_services_delete_own'
  ) THEN
    CREATE POLICY "master_services_delete_own"
      ON public.master_services FOR DELETE
      USING (auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id));
  END IF;
END $$;

-- Function to update service updated_at
CREATE OR REPLACE FUNCTION update_master_service_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update updated_at when service is updated
DROP TRIGGER IF EXISTS update_master_service_updated_at_trigger ON public.master_services;
CREATE TRIGGER update_master_service_updated_at_trigger
  BEFORE UPDATE ON public.master_services
  FOR EACH ROW EXECUTE FUNCTION update_master_service_updated_at();

-- Master follows table for user following masters
CREATE TABLE IF NOT EXISTS public.master_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  master_id uuid REFERENCES public.masters(id) ON DELETE CASCADE NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, master_id)
);

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_master_follows_user_id ON public.master_follows(user_id);
CREATE INDEX IF NOT EXISTS idx_master_follows_master_id ON public.master_follows(master_id);

-- Enable RLS
ALTER TABLE public.master_follows ENABLE ROW LEVEL SECURITY;

-- RLS policies for master_follows
DO $$
BEGIN
  -- Allow users to view their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_follows' 
    AND policyname = 'master_follows_select_own'
  ) THEN
    CREATE POLICY "master_follows_select_own"
      ON public.master_follows FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
  
  -- Allow users to view follow counts (for public display)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_follows' 
    AND policyname = 'master_follows_select_public'
  ) THEN
    CREATE POLICY "master_follows_select_public"
      ON public.master_follows FOR SELECT
      USING (true);
  END IF;
  
  -- Allow users to insert their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_follows' 
    AND policyname = 'master_follows_insert_own'
  ) THEN
    CREATE POLICY "master_follows_insert_own"
      ON public.master_follows FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
  
  -- Allow users to delete their own follows
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'master_follows' 
    AND policyname = 'master_follows_delete_own'
  ) THEN
    CREATE POLICY "master_follows_delete_own"
      ON public.master_follows FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Comments
COMMENT ON TABLE public.master_services IS '卦师服务项目表，记录卦师提供的服务项目、价格和服务形式';
COMMENT ON COLUMN public.master_services.service_type IS '服务形式: 图文/语音';
COMMENT ON TABLE public.master_follows IS '用户关注卦师表';

