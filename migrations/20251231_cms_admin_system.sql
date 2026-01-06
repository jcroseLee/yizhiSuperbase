DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'admin_level'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN admin_level text CHECK (admin_level IN ('super_admin', 'operator'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN is_verified boolean NOT NULL DEFAULT false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'verified_at'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN verified_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'verified_by'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN verified_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'banned_until'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN banned_until timestamptz;
  END IF;
END $$;

ALTER TABLE public.tags
  ADD COLUMN IF NOT EXISTS is_recommended boolean NOT NULL DEFAULT false;

ALTER TABLE public.tags
  ADD COLUMN IF NOT EXISTS recommended_rank integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_tags_recommended_rank
  ON public.tags (is_recommended, recommended_rank DESC, usage_count DESC)
  WHERE is_recommended = true;

ALTER TABLE public.case_metadata
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.case_metadata
  ADD COLUMN IF NOT EXISTS admin_note text;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS target_snapshot jsonb;

CREATE OR REPLACE FUNCTION public.capture_report_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snapshot jsonb;
BEGIN
  v_snapshot := NULL;

  IF NEW.target_type = 'post' THEN
    SELECT jsonb_build_object(
      'type', 'post',
      'id', p.id,
      'user_id', p.user_id,
      'title', p.title,
      'content', p.content,
      'content_html', p.content_html,
      'status', p.status,
      'created_at', p.created_at
    )
    INTO v_snapshot
    FROM public.posts p
    WHERE p.id = NEW.target_id;
  ELSIF NEW.target_type = 'comment' THEN
    SELECT jsonb_build_object(
      'type', 'comment',
      'id', c.id,
      'post_id', c.post_id,
      'user_id', c.user_id,
      'content', c.content,
      'status', c.status,
      'created_at', c.created_at
    )
    INTO v_snapshot
    FROM public.comments c
    WHERE c.id = NEW.target_id;
  ELSIF NEW.target_type = 'user' THEN
    SELECT jsonb_build_object(
      'type', 'user',
      'id', pr.id,
      'nickname', pr.nickname,
      'bio', pr.bio,
      'is_banned', pr.is_banned,
      'banned_until', pr.banned_until
    )
    INTO v_snapshot
    FROM public.profiles pr
    WHERE pr.id = NEW.target_id;
  END IF;

  IF NEW.target_snapshot IS NULL THEN
    NEW.target_snapshot := v_snapshot;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_capture_report_snapshot ON public.reports;
CREATE TRIGGER trigger_capture_report_snapshot
  BEFORE INSERT ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.capture_report_snapshot();

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_id uuid,
  details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created_at ON public.admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_action ON public.admin_audit_logs (action);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_operator_id ON public.admin_audit_logs (operator_id);

ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_audit_logs'
      AND policyname = 'admin_audit_logs_admin_select'
  ) THEN
    CREATE POLICY "admin_audit_logs_admin_select"
      ON public.admin_audit_logs FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.id = auth.uid()
            AND pr.role = 'admin'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_audit_logs'
      AND policyname = 'admin_audit_logs_admin_insert'
  ) THEN
    CREATE POLICY "admin_audit_logs_admin_insert"
      ON public.admin_audit_logs FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.id = auth.uid()
            AND pr.role = 'admin'
        )
      );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_report(
  p_report_id uuid,
  p_action text,
  p_note text,
  p_operator_id uuid,
  p_ban_days integer DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_id uuid;
  v_target_type text;
  v_admin_level text;
  v_target_user_id uuid;
  v_banned_until timestamptz;
BEGIN
  SELECT pr.admin_level INTO v_admin_level
  FROM public.profiles pr
  WHERE pr.id = p_operator_id AND pr.role = 'admin';

  IF v_admin_level IS NULL THEN
    v_admin_level := 'operator';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = p_operator_id AND pr.role = 'admin') THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_action NOT IN ('ignore', 'hide_content', 'ban_user') THEN
    RAISE EXCEPTION 'Invalid action';
  END IF;

  SELECT r.target_id, r.target_type INTO v_target_id, v_target_type
  FROM public.reports r
  WHERE r.id = p_report_id;

  IF v_target_id IS NULL OR v_target_type IS NULL THEN
    RAISE EXCEPTION 'Report not found';
  END IF;

  IF p_action = 'hide_content' THEN
    IF v_target_type = 'post' THEN
      UPDATE public.posts SET status = 'hidden' WHERE id = v_target_id;
    ELSIF v_target_type = 'comment' THEN
      UPDATE public.comments SET status = 'hidden' WHERE id = v_target_id;
    END IF;
  ELSIF p_action = 'ban_user' THEN
    IF v_admin_level = 'operator' AND COALESCE(p_ban_days, 0) > 7 THEN
      RAISE EXCEPTION 'Operator can only ban up to 7 days';
    END IF;

    IF v_target_type = 'user' THEN
      v_target_user_id := v_target_id;
    ELSIF v_target_type = 'post' THEN
      SELECT p.user_id INTO v_target_user_id FROM public.posts p WHERE p.id = v_target_id;
      UPDATE public.posts SET status = 'hidden' WHERE id = v_target_id;
    ELSIF v_target_type = 'comment' THEN
      SELECT c.user_id INTO v_target_user_id FROM public.comments c WHERE c.id = v_target_id;
      UPDATE public.comments SET status = 'hidden' WHERE id = v_target_id;
    END IF;

    IF v_target_user_id IS NOT NULL THEN
      v_banned_until := now() + make_interval(days => COALESCE(p_ban_days, 7));
      UPDATE public.profiles
      SET
        is_banned = true,
        banned_at = now(),
        banned_until = v_banned_until,
        ban_reason = COALESCE(NULLIF(btrim(p_note), ''), ban_reason)
      WHERE id = v_target_user_id;
    END IF;
  END IF;

  UPDATE public.reports
  SET
    status = 'resolved',
    resolution = CASE
      WHEN p_action = 'ignore' THEN 'rejected'
      WHEN p_action = 'hide_content' THEN 'deleted'
      WHEN p_action = 'ban_user' THEN 'banned'
      ELSE NULL
    END,
    admin_note = p_note,
    resolved_by = p_operator_id,
    resolved_at = now()
  WHERE id = p_report_id;

  INSERT INTO public.admin_audit_logs (operator_id, action, target_id, details)
  VALUES (
    p_operator_id,
    'resolve_report',
    v_target_id,
    jsonb_build_object(
      'report_id', p_report_id,
      'action', p_action,
      'note', p_note,
      'target_type', v_target_type,
      'ban_days', p_ban_days
    )
  );

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_merge_tags(
  p_source_tag_id uuid,
  p_target_tag_id uuid,
  p_operator_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source_exists boolean;
  v_target_exists boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = p_operator_id AND pr.role = 'admin') THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.tags t WHERE t.id = p_source_tag_id) INTO v_source_exists;
  SELECT EXISTS(SELECT 1 FROM public.tags t WHERE t.id = p_target_tag_id) INTO v_target_exists;

  IF NOT v_source_exists OR NOT v_target_exists THEN
    RAISE EXCEPTION 'Tag not found';
  END IF;

  INSERT INTO public.post_tags (post_id, tag_id)
  SELECT pt.post_id, p_target_tag_id
  FROM public.post_tags pt
  WHERE pt.tag_id = p_source_tag_id
  ON CONFLICT DO NOTHING;

  DELETE FROM public.post_tags WHERE tag_id = p_source_tag_id;
  DELETE FROM public.tags WHERE id = p_source_tag_id;

  INSERT INTO public.admin_audit_logs (operator_id, action, target_id, details)
  VALUES (
    p_operator_id,
    'merge_tags',
    p_target_tag_id,
    jsonb_build_object(
      'source_tag_id', p_source_tag_id,
      'target_tag_id', p_target_tag_id
    )
  );

  RETURN true;
END;
$$;

