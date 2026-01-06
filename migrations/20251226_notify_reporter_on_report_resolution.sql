-- Create a trigger to notify the reporter when their report is resolved or rejected
-- This ensures the reporter always gets feedback regardless of where the resolution action comes from (CMS, API, etc.)

CREATE OR REPLACE FUNCTION public.notify_reporter_on_report_resolution()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_target_title TEXT;
  v_notification_content TEXT;
  v_action_text TEXT;
  v_target_preview_len INT := 20;
BEGIN
  -- Trigger when status changes from pending to resolved or rejected
  IF (TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status IN ('resolved', 'rejected')) THEN
    
    -- Determine target title/preview based on target_type
    IF NEW.target_type = 'post' THEN
      SELECT title INTO v_target_title FROM public.posts WHERE id = NEW.target_id;
      IF v_target_title IS NULL THEN v_target_title := '已删除的帖子'; END IF;
    ELSIF NEW.target_type = 'comment' THEN
      SELECT substring(content from 1 for v_target_preview_len) INTO v_target_title FROM public.comments WHERE id = NEW.target_id;
      IF v_target_title IS NULL THEN v_target_title := '已删除的评论'; END IF;
    ELSIF NEW.target_type = 'user' THEN
      SELECT nickname INTO v_target_title FROM public.profiles WHERE id = NEW.target_id;
      IF v_target_title IS NULL THEN v_target_title := '未知用户'; END IF;
    ELSE
      v_target_title := '未知内容';
    END IF;

    -- Determine action text
    IF NEW.status = 'rejected' THEN
      v_action_text := '已驳回';
    ELSE
      v_action_text := '已处理';
    END IF;

    -- Build content
    v_notification_content := '您举报的' || 
      CASE NEW.target_type 
        WHEN 'post' THEN '帖子' 
        WHEN 'comment' THEN '评论' 
        WHEN 'user' THEN '用户' 
        ELSE '内容' 
      END || 
      '「' || COALESCE(v_target_title, '') || '」' || v_action_text || '。';

    -- Append admin note if exists
    IF NEW.admin_note IS NOT NULL AND length(trim(NEW.admin_note)) > 0 THEN
      v_notification_content := v_notification_content || '管理员备注：' || NEW.admin_note;
    END IF;

    -- Send notification using create_notification function
    -- We use PERFORM to ignore the returned uuid
    PERFORM public.create_notification(
      NEW.reporter_id,
      'system',
      NEW.target_id,
      NEW.target_type,
      NEW.resolved_by, -- actor_id (admin)
      v_notification_content,
      jsonb_build_object(
        'report_id', NEW.id,
        'target_id', NEW.target_id,
        'target_type', NEW.target_type,
        'target_title', v_target_title,
        'action', 'report_processed',
        'resolution', NEW.resolution,
        'status', NEW.status,
        'admin_note', NEW.admin_note,
        'processed_at', NEW.resolved_at,
        'processed_by', NEW.resolved_by
      )
    );

  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists (to avoid duplicates or conflicts)
DROP TRIGGER IF EXISTS trigger_notify_reporter_on_report_resolution ON public.reports;

-- Create the trigger
CREATE TRIGGER trigger_notify_reporter_on_report_resolution
  AFTER UPDATE ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reporter_on_report_resolution();

-- Comment on trigger
COMMENT ON TRIGGER trigger_notify_reporter_on_report_resolution ON public.reports IS
  'Automatically notify the reporter when their report is resolved or rejected';
