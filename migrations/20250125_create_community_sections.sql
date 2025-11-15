-- Create community_sections table for managing community section configurations
CREATE TABLE IF NOT EXISTS public.community_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  label text NOT NULL,
  description text,
  order_index integer NOT NULL DEFAULT 0,
  is_enabled boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.community_sections ENABLE ROW LEVEL SECURITY;

-- RLS Policies for community_sections
DO $$
BEGIN
  -- All users can read enabled sections
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' 
    AND tablename='community_sections' 
    AND policyname='community_sections_select_enabled'
  ) THEN
    CREATE POLICY "community_sections_select_enabled"
      ON public.community_sections FOR SELECT
      USING (is_enabled = true);
  END IF;

  -- Admins can do all operations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' 
    AND tablename='community_sections' 
    AND policyname='community_sections_admin_all'
  ) THEN
    CREATE POLICY "community_sections_admin_all"
      ON public.community_sections FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
END $$;

-- Insert default sections (idempotent)
INSERT INTO public.community_sections (key, label, description, order_index, is_enabled)
SELECT k, l, d, o, e FROM (
  VALUES
    ('study', '六爻研习', '六爻学习交流区', 1, true),
    ('help', '卦象互助', '卦象解答互助区', 2, true),
    ('casual', '易学闲谈', '易学闲聊讨论区', 3, true),
    ('announcement', '官方公告', '官方公告发布区', 4, true)
) AS seed(k, l, d, o, e)
WHERE NOT EXISTS (
  SELECT 1 FROM public.community_sections s WHERE s.key = seed.k
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_community_sections_order 
  ON public.community_sections(order_index);

CREATE INDEX IF NOT EXISTS idx_community_sections_enabled 
  ON public.community_sections(is_enabled) 
  WHERE is_enabled = true;

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_community_sections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_community_sections_updated_at ON public.community_sections;
CREATE TRIGGER trigger_update_community_sections_updated_at
  BEFORE UPDATE ON public.community_sections
  FOR EACH ROW
  EXECUTE FUNCTION update_community_sections_updated_at();

COMMENT ON TABLE public.community_sections IS '社区分类配置表，用于管理社区板块';
COMMENT ON COLUMN public.community_sections.key IS '分类唯一标识符';
COMMENT ON COLUMN public.community_sections.label IS '分类显示名称';
COMMENT ON COLUMN public.community_sections.order_index IS '排序索引，数字越小越靠前';
COMMENT ON COLUMN public.community_sections.is_enabled IS '是否启用该分类';

