DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'divination_method_type') THEN
    CREATE TYPE public.divination_method_type AS ENUM ('liuyao', 'bazi', 'qimen', 'meihua', 'ziwei', 'general');
  END IF;
END $$;

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS method public.divination_method_type DEFAULT 'liuyao';

CREATE TABLE IF NOT EXISTS public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text NOT NULL CHECK (category IN ('subject', 'technique', 'custom')),
  CONSTRAINT tags_name_length_check CHECK (char_length(name) > 0 AND char_length(name) <= 20),
  scope public.divination_method_type,
  usage_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (name, scope, category)
);

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tags' AND policyname = 'tags_select_all'
  ) THEN
    CREATE POLICY "tags_select_all" ON public.tags FOR SELECT USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tags' AND policyname = 'tags_admin_all'
  ) THEN
    CREATE POLICY "tags_admin_all"
      ON public.tags FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tags' AND policyname = 'tags_insert_custom'
  ) THEN
    CREATE POLICY "tags_insert_custom"
      ON public.tags FOR INSERT
      WITH CHECK (auth.uid() IS NOT NULL AND category = 'custom');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.post_tags (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (post_id, tag_id)
);

ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_tags' AND policyname = 'post_tags_select_all'
  ) THEN
    CREATE POLICY "post_tags_select_all" ON public.post_tags FOR SELECT USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_tags' AND policyname = 'post_tags_insert_own_post'
  ) THEN
    CREATE POLICY "post_tags_insert_own_post"
      ON public.post_tags FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.posts p
          WHERE p.id = post_tags.post_id
          AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_tags' AND policyname = 'post_tags_delete_own_post'
  ) THEN
    CREATE POLICY "post_tags_delete_own_post"
      ON public.post_tags FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.posts p
          WHERE p.id = post_tags.post_id
          AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_tags' AND policyname = 'post_tags_admin_all'
  ) THEN
    CREATE POLICY "post_tags_admin_all"
      ON public.post_tags FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tags_scope_category_usage ON public.tags (scope, category, usage_count DESC);
CREATE INDEX IF NOT EXISTS idx_tags_name ON public.tags (name);
CREATE INDEX IF NOT EXISTS idx_post_tags_post_id ON public.post_tags (post_id);
CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON public.post_tags (tag_id);

CREATE OR REPLACE FUNCTION public.update_tag_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_tag_updated_at_trigger ON public.tags;
CREATE TRIGGER update_tag_updated_at_trigger
  BEFORE UPDATE ON public.tags
  FOR EACH ROW EXECUTE FUNCTION public.update_tag_updated_at();

CREATE OR REPLACE FUNCTION public.sync_post_tags_and_usage()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_post_id uuid;
BEGIN
  v_post_id := COALESCE(NEW.post_id, OLD.post_id);

  IF TG_OP = 'INSERT' THEN
    UPDATE public.tags
    SET usage_count = COALESCE(usage_count, 0) + 1
    WHERE id = NEW.tag_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.tags
    SET usage_count = GREATEST(COALESCE(usage_count, 0) - 1, 0)
    WHERE id = OLD.tag_id;
  END IF;

  UPDATE public.posts p
  SET tags = COALESCE((
    SELECT array_agg(t.name ORDER BY t.category, t.name)
    FROM public.post_tags pt
    JOIN public.tags t ON t.id = pt.tag_id
    WHERE pt.post_id = v_post_id
  ), ARRAY[]::text[])
  WHERE p.id = v_post_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_post_tags_and_usage_trigger ON public.post_tags;
CREATE TRIGGER sync_post_tags_and_usage_trigger
  AFTER INSERT OR DELETE ON public.post_tags
  FOR EACH ROW EXECUTE FUNCTION public.sync_post_tags_and_usage();

CREATE OR REPLACE FUNCTION public.validate_post_tag()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_post_method public.divination_method_type;
  v_tag_category text;
  v_tag_scope public.divination_method_type;
BEGIN
  SELECT p.method INTO v_post_method FROM public.posts p WHERE p.id = NEW.post_id;
  SELECT t.category, t.scope INTO v_tag_category, v_tag_scope FROM public.tags t WHERE t.id = NEW.tag_id;

  IF v_tag_category = 'subject' THEN
    IF v_tag_scope IS NOT NULL THEN
      RAISE EXCEPTION 'Subject tags must be common (scope is null)';
    END IF;
  ELSIF v_tag_category = 'technique' THEN
    IF v_post_method IS NULL THEN
      RAISE EXCEPTION 'Post method is required for technique tags';
    END IF;
    IF v_tag_scope IS DISTINCT FROM v_post_method THEN
      RAISE EXCEPTION 'Technique tag scope must match post method';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_post_tag_trigger ON public.post_tags;
CREATE TRIGGER validate_post_tag_trigger
  BEFORE INSERT OR UPDATE ON public.post_tags
  FOR EACH ROW EXECUTE FUNCTION public.validate_post_tag();

INSERT INTO public.tags (name, category, scope)
SELECT s.name, s.category, s.scope
FROM (
  VALUES
    ('事业', 'subject', NULL::public.divination_method_type),
    ('财运', 'subject', NULL::public.divination_method_type),
    ('感情', 'subject', NULL::public.divination_method_type),
    ('婚姻', 'subject', NULL::public.divination_method_type),
    ('健康', 'subject', NULL::public.divination_method_type),
    ('学业', 'subject', NULL::public.divination_method_type),
    ('官非', 'subject', NULL::public.divination_method_type),
    ('寻人', 'subject', NULL::public.divination_method_type),
    ('择日', 'subject', NULL::public.divination_method_type),
    ('流年', 'subject', NULL::public.divination_method_type),
    ('六冲', 'technique', 'liuyao'::public.divination_method_type),
    ('六合', 'technique', 'liuyao'::public.divination_method_type),
    ('伏吟', 'technique', 'liuyao'::public.divination_method_type),
    ('反吟', 'technique', 'liuyao'::public.divination_method_type),
    ('飞伏', 'technique', 'liuyao'::public.divination_method_type),
    ('进神', 'technique', 'liuyao'::public.divination_method_type),
    ('空亡', 'technique', 'liuyao'::public.divination_method_type),
    ('身旺', 'technique', 'bazi'::public.divination_method_type),
    ('身弱', 'technique', 'bazi'::public.divination_method_type),
    ('伤官见官', 'technique', 'bazi'::public.divination_method_type),
    ('食神制杀', 'technique', 'bazi'::public.divination_method_type),
    ('大运', 'technique', 'bazi'::public.divination_method_type),
    ('伏吟局', 'technique', 'qimen'::public.divination_method_type),
    ('反吟局', 'technique', 'qimen'::public.divination_method_type),
    ('五不遇时', 'technique', 'qimen'::public.divination_method_type),
    ('击刑', 'technique', 'qimen'::public.divination_method_type),
    ('入墓', 'technique', 'qimen'::public.divination_method_type),
    ('体用', 'technique', 'meihua'::public.divination_method_type),
    ('互卦', 'technique', 'meihua'::public.divination_method_type),
    ('变卦', 'technique', 'meihua'::public.divination_method_type),
    ('外应', 'technique', 'meihua'::public.divination_method_type)
) AS s(name, category, scope)
WHERE NOT EXISTS (
  SELECT 1 FROM public.tags t
  WHERE t.name = s.name AND t.category = s.category AND t.scope IS NOT DISTINCT FROM s.scope
);
