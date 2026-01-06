-- ============================================
-- Fix Report System Issues (Final Comprehensive Fix)
-- ============================================

-- 1. Ensure RLS policies allow users to check for duplicates
-- We need to make sure users can SELECT their own reports to verify if they've already reported a post.

ALTER TABLE public.post_reports ENABLE ROW LEVEL SECURITY;

-- Allow users to select their own reports (CRITICAL for duplicate checking)
DROP POLICY IF EXISTS "post_reports_select_own" ON public.post_reports;
CREATE POLICY "post_reports_select_own"
  ON public.post_reports FOR SELECT
  USING (auth.uid() = reporter_id);

-- Allow users to insert their own reports
DROP POLICY IF EXISTS "post_reports_insert_own" ON public.post_reports;
CREATE POLICY "post_reports_insert_own"
  ON public.post_reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

-- Allow admins to do everything
DROP POLICY IF EXISTS "post_reports_admin_all" ON public.post_reports;
CREATE POLICY "post_reports_admin_all"
  ON public.post_reports FOR ALL
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

-- 2. Ensure columns exist (Idempotent check)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'post_reports' AND column_name = 'admin_note') THEN
        ALTER TABLE public.post_reports ADD COLUMN admin_note TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'post_reports' AND column_name = 'resolution') THEN
        ALTER TABLE public.post_reports ADD COLUMN resolution TEXT CHECK (resolution IN ('approved', 'rejected', 'deleted', 'banned'));
    END IF;
END $$;

-- 3. Update the notification trigger function (Force update)
-- This ensures the admin_note is included in the notification
CREATE OR REPLACE FUNCTION public.notify_reporter_on_resolution_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_post_title TEXT;
  v_post_id UUID;
  v_notification_content TEXT;
  v_action_text TEXT;
  v_notification_type TEXT;
BEGIN
  -- Trigger when status changes to closed
  IF (TG_OP = 'UPDATE' AND OLD.status = 'open' AND NEW.status = 'closed') THEN
    
    -- Get post info
    SELECT title, id INTO v_post_title, v_post_id
    FROM public.posts
    WHERE id = NEW.post_id;
    
    IF v_post_title IS NULL THEN
      v_post_title := '已删除的内容';
    END IF;
    
    -- Determine action text based on resolution
    IF NEW.resolution = 'rejected' THEN
      v_action_text := '已驳回';
      v_notification_type := 'report_rejected';
    ELSE
      v_action_text := '已处理';
      v_notification_type := 'report_resolved';
    END IF;
    
    -- Build content
    v_notification_content := '您举报的内容「' || v_post_title || '」' || v_action_text || '。';
    
    -- Append admin note if exists (Explicit check)
    IF NEW.admin_note IS NOT NULL AND length(trim(NEW.admin_note)) > 0 THEN
      v_notification_content := v_notification_content || ' 管理员备注：' || NEW.admin_note;
    END IF;
    
    -- Send notification
    PERFORM public.create_notification(
      NEW.reporter_id,
      v_notification_type,
      COALESCE(v_post_id, NEW.post_id),
      'post',
      NEW.processed_by,
      v_notification_content,
      jsonb_build_object(
        'report_id', NEW.id,
        'post_id', NEW.post_id,
        'post_title', v_post_title,
        'action', 'report_processed',
        'resolution', NEW.resolution,
        'admin_note', NEW.admin_note,
        'processed_at', NEW.processed_at,
        'processed_by', NEW.processed_by
      )
    );
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- 4. Re-apply the trigger
DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;
CREATE TRIGGER trigger_notify_reporter_on_resolution
  AFTER UPDATE ON public.post_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reporter_on_resolution_v3();
