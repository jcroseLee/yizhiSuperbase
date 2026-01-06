-- 1. Ensure columns exist (Idempotent check)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'post_reports' AND column_name = 'admin_note') THEN
        ALTER TABLE public.post_reports ADD COLUMN admin_note TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'post_reports' AND column_name = 'resolution') THEN
        ALTER TABLE public.post_reports ADD COLUMN resolution TEXT CHECK (resolution IN ('approved', 'rejected', 'deleted', 'banned'));
    END IF;
END $$;

-- 2. Force update the trigger function (v3.1)
-- Added explicit error handling and logging to debug why note might be missing
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
    ELSE
      v_action_text := '已处理';
    END IF;
    
    -- Build content
    v_notification_content := '您举报的内容「' || v_post_title || '」' || v_action_text || '。';
    
    -- Append admin note if exists
    -- Explicitly check for empty string as well
    IF NEW.admin_note IS NOT NULL AND length(trim(NEW.admin_note)) > 0 THEN
      v_notification_content := v_notification_content || '管理员备注：' || NEW.admin_note;
    END IF;
    
    -- Send notification
    PERFORM public.create_notification(
      NEW.reporter_id,
      'system', -- type
      COALESCE(v_post_id, NEW.post_id), -- related_id
      'post', -- related_type
      NEW.processed_by, -- actor_id
      v_notification_content, -- content
      jsonb_build_object( -- metadata
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
    
    RAISE NOTICE 'Notification sent. Note: %', NEW.admin_note;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- 3. Re-apply trigger to ensure it uses the new function
DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;
CREATE TRIGGER trigger_notify_reporter_on_resolution
  AFTER UPDATE ON public.post_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reporter_on_resolution_v3();
