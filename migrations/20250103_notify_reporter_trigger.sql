-- ============================================
-- 举报处理自动通知触发器
-- ============================================
-- 功能：当举报状态更新为 closed 时，自动向举报者发送系统通知
-- 目的：提升用户参与感，让举报者知道他们的举报已被处理
-- ============================================

-- 创建函数：发送举报处理通知
CREATE OR REPLACE FUNCTION public.notify_reporter_on_resolution()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_post_title TEXT;
  v_post_id UUID;
  v_notification_content TEXT;
BEGIN
  -- 只在状态从 'open' 变为 'closed' 时触发
  IF (TG_OP = 'UPDATE' AND OLD.status = 'open' AND NEW.status = 'closed') THEN
    
    -- 获取被举报帖子的标题
    SELECT title, id INTO v_post_title, v_post_id
    FROM public.posts
    WHERE id = NEW.post_id;
    
    -- 如果帖子不存在，使用默认文本
    IF v_post_title IS NULL THEN
      v_post_title := '已删除的内容';
    END IF;
    
    -- 构建通知内容
    v_notification_content := '您举报的内容「' || v_post_title || '」已处理，感谢您的贡献。';
    
    -- 发送通知给举报者
    BEGIN
      PERFORM public.create_notification(
        NEW.reporter_id,              -- 举报者ID
        'system',                      -- 通知类型：系统通知
        COALESCE(v_post_id, NEW.post_id), -- 关联的帖子ID
        'post',                        -- 关联类型
        NEW.processed_by,              -- 处理人（管理员）ID
        v_notification_content,        -- 通知内容
        jsonb_build_object(
          'report_id', NEW.id,
          'post_id', NEW.post_id,
          'post_title', v_post_title,
          'action', 'report_processed',
          'processed_at', NEW.processed_at,
          'processed_by', NEW.processed_by
        )
      );
      
      -- 记录日志
      RAISE NOTICE 'Notification sent to reporter % for report %', NEW.reporter_id, NEW.id;
      
    EXCEPTION WHEN OTHERS THEN
      -- 即使通知发送失败，也不影响举报状态更新
      RAISE WARNING 'Failed to send notification for report %: %', NEW.id, SQLERRM;
    END;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- 创建触发器：在举报记录更新时触发
DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;
CREATE TRIGGER trigger_notify_reporter_on_resolution
  AFTER UPDATE ON public.post_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reporter_on_resolution();

-- 添加注释
COMMENT ON FUNCTION public.notify_reporter_on_resolution IS 
  '举报处理自动通知：当举报状态从 open 变为 closed 时，自动向举报者发送系统通知，感谢他们的贡献。';

COMMENT ON TRIGGER trigger_notify_reporter_on_resolution ON public.post_reports IS
  '自动通知举报者：当举报被处理时，发送感谢通知';

-- ============================================
-- 优化：更智能的通知内容
-- ============================================
-- 可以根据不同情况发送不同的通知内容

CREATE OR REPLACE FUNCTION public.notify_reporter_on_resolution_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_post_title TEXT;
  v_post_id UUID;
  v_post_status TEXT;
  v_notification_content TEXT;
  v_is_post_deleted BOOLEAN := FALSE;
  v_is_user_banned BOOLEAN := FALSE;
  v_post_author_id UUID;
BEGIN
  -- 只在状态从 'open' 变为 'closed' 时触发
  IF (TG_OP = 'UPDATE' AND OLD.status = 'open' AND NEW.status = 'closed') THEN
    
    -- 获取被举报帖子的信息
    SELECT title, id, status, user_id 
    INTO v_post_title, v_post_id, v_post_status, v_post_author_id
    FROM public.posts
    WHERE id = NEW.post_id;
    
    -- 检查帖子是否被删除
    IF v_post_status = 'deleted' OR v_post_title IS NULL THEN
      v_is_post_deleted := TRUE;
      v_post_title := COALESCE(v_post_title, '已删除的内容');
    END IF;
    
    -- 检查作者是否被封禁
    IF v_post_author_id IS NOT NULL THEN
      SELECT is_banned INTO v_is_user_banned
      FROM public.profiles
      WHERE id = v_post_author_id;
    END IF;
    
    -- 根据处理结果构建不同的通知内容
    IF v_is_user_banned THEN
      v_notification_content := '您举报的内容「' || v_post_title || '」已处理，违规用户已被封禁。感谢您维护社区秩序！';
    ELSIF v_is_post_deleted THEN
      v_notification_content := '您举报的内容「' || v_post_title || '」已处理，违规内容已被删除。感谢您的贡献！';
    ELSE
      v_notification_content := '您举报的内容「' || v_post_title || '」已处理，感谢您的贡献。';
    END IF;
    
    -- 发送通知给举报者
    BEGIN
      PERFORM public.create_notification(
        NEW.reporter_id,
        'system',
        COALESCE(v_post_id, NEW.post_id),
        'post',
        NEW.processed_by,
        v_notification_content,
        jsonb_build_object(
          'report_id', NEW.id,
          'post_id', NEW.post_id,
          'post_title', v_post_title,
          'action', 'report_processed',
          'processed_at', NEW.processed_at,
          'processed_by', NEW.processed_by,
          'post_deleted', v_is_post_deleted,
          'user_banned', v_is_user_banned
        )
      );
      
      RAISE NOTICE 'Notification sent to reporter % for report %', NEW.reporter_id, NEW.id;
      
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to send notification for report %: %', NEW.id, SQLERRM;
    END;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- ============================================
-- 选择使用哪个版本
-- ============================================
-- 
-- 版本1（默认）：简单版本，固定的感谢消息
-- 版本2：智能版本，根据处理结果显示不同消息
--
-- 要使用版本2，取消下面的注释：
--
-- DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;
-- CREATE TRIGGER trigger_notify_reporter_on_resolution
--   AFTER UPDATE ON public.post_reports
--   FOR EACH ROW
--   EXECUTE FUNCTION public.notify_reporter_on_resolution_v2();

-- ============================================
-- 测试查询
-- ============================================

-- 测试：模拟处理举报（请替换实际的 report_id 和 admin_id）
/*
UPDATE public.post_reports
SET 
  status = 'closed',
  processed_by = 'YOUR_ADMIN_ID',
  processed_at = NOW()
WHERE id = 'YOUR_REPORT_ID'
  AND status = 'open';
*/

-- 查看最近发送的通知
/*
SELECT 
  n.id,
  n.user_id,
  n.type,
  n.content,
  n.created_at,
  n.metadata->>'report_id' as report_id,
  n.metadata->>'post_title' as post_title
FROM public.notifications n
WHERE n.type = 'system'
  AND n.metadata->>'action' = 'report_processed'
ORDER BY n.created_at DESC
LIMIT 10;
*/

-- 统计举报处理通知发送情况
/*
SELECT 
  DATE(created_at) as date,
  COUNT(*) as notification_count,
  COUNT(DISTINCT user_id) as unique_reporters
FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
*/

-- ============================================
-- 注意事项
-- ============================================
--
-- 1. 触发器会在每次举报状态更新时自动执行
-- 2. 即使 CMS 代码中也发送通知，触发器也会执行（可能导致重复）
-- 3. 如果要避免重复，可以：
--    a. 只使用触发器（推荐）
--    b. 或只使用 CMS 代码
--    c. 或在触发器中检查是否已发送过通知
--
-- 4. 触发器使用 SECURITY DEFINER，可以绕过 RLS 限制
-- 5. 异常处理确保即使通知失败也不影响举报状态更新
--
-- ============================================
-- 优化建议
-- ============================================
--
-- 为了避免与 CMS 代码中的通知重复，建议：
--
-- 方案 1：只使用触发器（推荐）
--   - 删除 CMS 代码中的 sendReportNotification 调用
--   - 让触发器统一处理所有通知
--
-- 方案 2：触发器中检查重复
--   - 在发送通知前检查是否已存在相同通知
--   - 示例代码见下方
--
/*
-- 检查重复通知的示例
DECLARE
  v_existing_notification UUID;
BEGIN
  -- 检查是否已有相同的通知
  SELECT id INTO v_existing_notification
  FROM public.notifications
  WHERE user_id = NEW.reporter_id
    AND metadata->>'report_id' = NEW.id::TEXT
    AND created_at > NEW.processed_at - INTERVAL '1 minute'
  LIMIT 1;
  
  -- 如果没有重复通知，才发送
  IF v_existing_notification IS NULL THEN
    PERFORM public.create_notification(...);
  END IF;
END;
*/

