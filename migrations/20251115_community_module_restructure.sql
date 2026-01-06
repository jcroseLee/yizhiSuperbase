-- Community Module Restructure Migration
-- Adds sections/status to posts, reporting/moderation tables, sensitive keywords,
-- extends profiles, and updates RLS to enforce compliance.

-- 1) Extend posts with community governance fields
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS section text CHECK (section IN ('study','help','casual','announcement')) DEFAULT 'study',
  ADD COLUMN IF NOT EXISTS status text CHECK (status IN ('published','pending','hidden','rejected')) DEFAULT 'published',
  ADD COLUMN IF NOT EXISTS is_pinned boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_featured boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS tags text[] DEFAULT ARRAY[]::text[],
  ADD COLUMN IF NOT EXISTS last_moderated_at timestamptz,
  ADD COLUMN IF NOT EXISTS moderated_by uuid,
  ADD COLUMN IF NOT EXISTS hide_reason text;

DO $$
BEGIN
  -- Add foreign key for moderated_by if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public' AND table_name = 'posts' AND constraint_name = 'posts_moderated_by_fkey'
  ) THEN
    ALTER TABLE public.posts
      ADD CONSTRAINT posts_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 2) Sensitive keywords for moderation
CREATE TABLE IF NOT EXISTS public.sensitive_keywords (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  word text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('block','warn')),
  category text CHECK (category IN ('外联','迷信','广告','辱骂','其他')),
  enabled boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.sensitive_keywords ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Admins manage sensitive keywords
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sensitive_keywords' AND policyname='sensitive_keywords_admin_all'
  ) THEN
    CREATE POLICY "sensitive_keywords_admin_all"
      ON public.sensitive_keywords FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
  -- All users can read keywords (client-side hints)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sensitive_keywords' AND policyname='sensitive_keywords_select_all'
  ) THEN
    CREATE POLICY "sensitive_keywords_select_all" ON public.sensitive_keywords FOR SELECT USING (true);
  END IF;
END $$;

-- Seed basic keywords (idempotent)
INSERT INTO public.sensitive_keywords (word, severity, category)
SELECT w, s, c FROM (
  VALUES
    ('命理','block','迷信'),
    ('改运','block','迷信'),
    ('神仙','block','迷信'),
    ('风水宝地','block','迷信'),
    ('加微信','block','外联'),
    ('微信号','block','外联'),
    ('手机号','block','外联'),
    ('二维码','block','外联'),
    ('私下交易','block','外联'),
    ('平台外支付','block','外联'),
    ('带单','warn','广告'),
    ('外部群','warn','外联')
) AS seed(w,s,c)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sensitive_keywords k WHERE k.word = seed.w
);

-- 3) Post reports for user-driven moderation
CREATE TABLE IF NOT EXISTS public.post_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('广告','辱骂','导流','迷信','其他')),
  details text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  processed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  processed_at timestamptz
);

ALTER TABLE public.post_reports ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Reporters can insert their own reports
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_reports' AND policyname='post_reports_insert_own'
  ) THEN
    CREATE POLICY "post_reports_insert_own" ON public.post_reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
  END IF;
  -- Admins can do all
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_reports' AND policyname='post_reports_admin_all'
  ) THEN
    CREATE POLICY "post_reports_admin_all"
      ON public.post_reports FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
  -- Authors can read reports against their posts
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_reports' AND policyname='post_reports_select_author'
  ) THEN
    CREATE POLICY "post_reports_select_author"
      ON public.post_reports FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.posts p WHERE p.id = post_reports.post_id AND p.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- 4) Moderation actions log
CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (target_type IN ('post','comment','profile')),
  target_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('delete','warn','mute','ban','unhide','approve','feature','pin')),
  reason text,
  moderator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  meta jsonb
);

ALTER TABLE public.moderation_actions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Admin only
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='moderation_actions' AND policyname='moderation_actions_admin_all'
  ) THEN
    CREATE POLICY "moderation_actions_admin_all"
      ON public.moderation_actions FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
  -- Authors can read actions against their own posts/comments
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='moderation_actions' AND policyname='moderation_actions_select_author'
  ) THEN
    CREATE POLICY "moderation_actions_select_author"
      ON public.moderation_actions FOR SELECT
      USING (
        (target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = moderation_actions.target_id AND p.user_id = auth.uid()))
        OR
        (target_type = 'comment' AND EXISTS (SELECT 1 FROM public.comments c WHERE c.id = moderation_actions.target_id AND c.user_id = auth.uid()))
      );
  END IF;
END $$;

-- 5) Extend profiles with governance fields
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS level integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS contribution_score integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_muted_until timestamptz,
  ADD COLUMN IF NOT EXISTS is_banned boolean DEFAULT false;

-- 6) Extend risk_control_violations for community
ALTER TABLE public.risk_control_violations
  ADD COLUMN IF NOT EXISTS post_id uuid;

DO $$
BEGIN
  -- Add FK if posts exist and constraint not added
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='posts') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='risk_control_violations' AND constraint_name='risk_control_violations_post_id_fkey'
    ) THEN
      ALTER TABLE public.risk_control_violations
        ADD CONSTRAINT risk_control_violations_post_id_fkey
        FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- 7) Update posts RLS: only published visible to all, authors/admin see all
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Drop existing select policies to replace
  DROP POLICY IF EXISTS "posts_select_all" ON public.posts;
  DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;
  -- Create visibility policy
  CREATE POLICY "posts_select_visible"
    ON public.posts FOR SELECT
    USING (
      status = 'published'
      OR auth.uid() = user_id
      OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

  -- Keep insert/update/delete own policies if not exist
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='posts_insert_own') THEN
    CREATE POLICY "posts_insert_own" ON public.posts FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='posts_update_own') THEN
    CREATE POLICY "posts_update_own" ON public.posts FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='posts_delete_own') THEN
    CREATE POLICY "posts_delete_own" ON public.posts FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- 8) Ensure admin full control (reuse pattern)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='posts_admin_all'
  ) THEN
    CREATE POLICY "posts_admin_all"
      ON public.posts FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
  END IF;
END $$;

-- 9) Ensure community module toggle exists
INSERT INTO public.modules (name, display_name, description, is_enabled, order_index)
SELECT 'community', '社区', '社区模块开关', true, 2
WHERE NOT EXISTS (SELECT 1 FROM public.modules WHERE name = 'community');

-- Comments optional moderation fields (status)
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS status text CHECK (status IN ('published','hidden','rejected')) DEFAULT 'published',
  ADD COLUMN IF NOT EXISTS last_moderated_at timestamptz,
  ADD COLUMN IF NOT EXISTS moderated_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='comments' AND constraint_name='comments_moderated_by_fkey'
  ) THEN
    ALTER TABLE public.comments
      ADD CONSTRAINT comments_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

COMMENT ON TABLE public.post_reports IS '用户举报帖子表';
COMMENT ON TABLE public.moderation_actions IS '内容审核处置记录表';
COMMENT ON TABLE public.sensitive_keywords IS '敏感词配置表（阻断/警告）';
COMMENT ON COLUMN public.posts.section IS '社区板块：study研习、help互助、casual闲谈、announcement公告';
COMMENT ON COLUMN public.posts.status IS '帖子状态：published/pending/hidden/rejected';