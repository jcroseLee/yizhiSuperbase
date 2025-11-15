-- Create community_subsections table for managing subsection configurations
CREATE TABLE IF NOT EXISTS public.community_subsections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_key text NOT NULL,
  key text NOT NULL,
  label text NOT NULL,
  description text,
  order_index integer NOT NULL DEFAULT 0,
  is_enabled boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(section_key, key)
);

ALTER TABLE public.community_subsections ENABLE ROW LEVEL SECURITY;

-- RLS Policies for community_subsections
DO $$
BEGIN
  -- All users can read enabled subsections
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' 
    AND tablename='community_subsections' 
    AND policyname='community_subsections_select_enabled'
  ) THEN
    CREATE POLICY "community_subsections_select_enabled"
      ON public.community_subsections FOR SELECT
      USING (is_enabled = true);
  END IF;

  -- Admins can do all operations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' 
    AND tablename='community_subsections' 
    AND policyname='community_subsections_admin_all'
  ) THEN
    CREATE POLICY "community_subsections_admin_all"
      ON public.community_subsections FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
END $$;

-- Insert default subsections (idempotent)
INSERT INTO public.community_subsections (section_key, key, label, description, order_index, is_enabled)
SELECT s, k, l, d, o, e FROM (
  VALUES
    ('study', 'theory', '六爻理论', '六爻理论讨论', 1, true),
    ('study', 'practice', '实战案例', '实战案例分享', 2, true),
    ('study', 'classic', '经典卦例', '经典卦例分析', 3, true),
    ('help', 'question', '问题求助', '问题求助区', 1, true),
    ('help', 'answer', '解答分享', '解答分享区', 2, true),
    ('help', 'discussion', '讨论交流', '讨论交流区', 3, true),
    ('casual', 'chat', '闲谈', '闲谈区', 1, true),
    ('casual', 'share', '分享', '分享区', 2, true),
    ('casual', 'other', '其他', '其他话题', 3, true)
) AS seed(s, k, l, d, o, e)
WHERE NOT EXISTS (
  SELECT 1 FROM public.community_subsections ss WHERE ss.section_key = seed.s AND ss.key = seed.k
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_community_subsections_section_key 
  ON public.community_subsections(section_key);

CREATE INDEX IF NOT EXISTS idx_community_subsections_order 
  ON public.community_subsections(section_key, order_index);

CREATE INDEX IF NOT EXISTS idx_community_subsections_enabled 
  ON public.community_subsections(is_enabled) 
  WHERE is_enabled = true;

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_community_subsections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_community_subsections_updated_at ON public.community_subsections;
CREATE TRIGGER trigger_update_community_subsections_updated_at
  BEFORE UPDATE ON public.community_subsections
  FOR EACH ROW
  EXECUTE FUNCTION update_community_subsections_updated_at();

-- Add subsection column to posts table if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'posts' 
    AND column_name = 'subsection'
  ) THEN
    ALTER TABLE public.posts ADD COLUMN subsection text;
    
    -- Add comment
    COMMENT ON COLUMN public.posts.subsection IS '版块分区标识符，关联 community_subsections.key';
  END IF;
END $$;

COMMENT ON TABLE public.community_subsections IS '社区版块分区配置表，用于管理各分类下的子分区';
COMMENT ON COLUMN public.community_subsections.section_key IS '所属分类标识符，关联 community_sections.key';
COMMENT ON COLUMN public.community_subsections.key IS '分区唯一标识符';
COMMENT ON COLUMN public.community_subsections.label IS '分区显示名称';
COMMENT ON COLUMN public.community_subsections.order_index IS '排序索引，数字越小越靠前';
COMMENT ON COLUMN public.community_subsections.is_enabled IS '是否启用该分区';

