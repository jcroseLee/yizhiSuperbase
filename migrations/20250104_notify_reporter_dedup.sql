-- ============================================
-- 举报通知去重优化
-- ============================================
-- 解决 CMS 代码和触发器可能导致的重复通知问题
-- ============================================

-- 创建函数：检查并发送举报处理通知（带去重）
CREATE OR REPLACE FUNCTION public.notify_reporter_on_resolution_dedup()
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
  v_existing_notification UUID;
BEGIN
  -- 只在状态从 'open' 变为 'closed' 时触发
  IF (TG_OP = 'UPDATE' AND OLD.status = 'open' AND NEW.status = 'closed') THEN
    
    -- 首先检查是否已经有相同的通知（防止重复）
    SELECT id INTO v_existing_notification
    FROM public.notifications
    WHERE user_id = NEW.reporter_id
      AND metadata->>'report_id' = NEW.id::TEXT
      AND type = 'system'
      AND created_at > NEW.processed_at - INTERVAL '2 minutes' -- 2分钟内的通知算重复
    LIMIT 1;
    
    -- 如果已经有通知，跳过
    IF v_existing_notification IS NOT NULL THEN
      RAISE NOTICE 'Notification already exists for report %, skipping', NEW.id;
      RETURN NEW;
    END IF;
    
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
      
      IF v_is_user_banned IS NULL THEN
        v_is_user_banned := FALSE;
      END IF;
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
          'user_banned', v_is_user_banned,
          'source', 'trigger' -- 标记通知来源
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

-- 替换触发器为去重版本
DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;
CREATE TRIGGER trigger_notify_reporter_on_resolution
  AFTER UPDATE ON public.post_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reporter_on_resolution_dedup();

-- 添加注释
COMMENT ON FUNCTION public.notify_reporter_on_resolution_dedup IS 
  '举报处理自动通知（带去重）：当举报状态从 open 变为 closed 时，自动向举报者发送系统通知。内置去重机制，避免重复通知。';

-- ============================================
-- 清理旧的通知（可选）
-- ============================================
-- 如果之前有重复通知，可以使用这个查询清理

/*
-- 查找重复的举报通知
WITH duplicate_notifications AS (
  SELECT 
    id,
    user_id,
    metadata->>'report_id' as report_id,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, metadata->>'report_id' 
      ORDER BY created_at ASC
    ) as rn
  FROM public.notifications
  WHERE type = 'system'
    AND metadata->>'action' = 'report_processed'
)
SELECT 
  id,
  user_id,
  report_id,
  created_at
FROM duplicate_notifications
WHERE rn > 1
ORDER BY created_at DESC;

-- 删除重复的通知（保留最早的那一条）
-- 请谨慎使用，建议先用上面的查询确认要删除的记录
DELETE FROM public.notifications
WHERE id IN (
  SELECT id
  FROM (
    SELECT 
      id,
      ROW_NUMBER() OVER (
        PARTITION BY user_id, metadata->>'report_id' 
        ORDER BY created_at ASC
      ) as rn
    FROM public.notifications
    WHERE type = 'system'
      AND metadata->>'action' = 'report_processed'
  ) t
  WHERE rn > 1
);
*/

-- ============================================
-- 验证触发器是否正常工作
-- ============================================

-- 1. 查看触发器信息
/*
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trigger_notify_reporter_on_resolution';
*/

-- 2. 测试触发器（请替换实际ID）
/*
-- 创建测试举报（如果需要）
INSERT INTO public.post_reports (
  reporter_id,
  post_id,
  reason_category,
  reason_detail,
  status
) VALUES (
  'REPORTER_USER_ID',
  'POST_ID',
  '其他',
  '测试举报',
  'open'
);

-- 模拟处理举报
UPDATE public.post_reports
SET 
  status = 'closed',
  processed_by = 'ADMIN_USER_ID',
  processed_at = NOW()
WHERE id = 'REPORT_ID'
  AND status = 'open';

-- 检查是否生成了通知
SELECT 
  id,
  user_id,
  content,
  metadata,
  created_at
FROM public.notifications
WHERE user_id = 'REPORTER_USER_ID'
  AND metadata->>'action' = 'report_processed'
ORDER BY created_at DESC
LIMIT 1;
*/

-- ============================================
-- 性能优化：为通知表添加索引
-- ============================================

-- 为 metadata 中的 report_id 创建索引（如果不存在）
CREATE INDEX IF NOT EXISTS idx_notifications_metadata_report_id 
  ON public.notifications USING GIN ((metadata->'report_id'));

-- 为 type 和 user_id 的组合创建索引
CREATE INDEX IF NOT EXISTS idx_notifications_type_user_id 
  ON public.notifications (type, user_id, created_at DESC);

-- ============================================
-- 统计信息
-- ============================================

-- 查看触发器发送的通知统计
/*
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_notifications,
  COUNT(DISTINCT user_id) as unique_recipients,
  COUNT(DISTINCT metadata->>'report_id') as unique_reports
FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed'
  AND metadata->>'source' = 'trigger'
  AND created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
*/

-- 查看通知发送成功率（通过检查是否有对应的举报记录）
/*
SELECT 
  COUNT(DISTINCT n.id) as total_notifications,
  COUNT(DISTINCT pr.id) as valid_reports,
  ROUND(COUNT(DISTINCT pr.id)::NUMERIC / COUNT(DISTINCT n.id) * 100, 2) as success_rate_percent
FROM public.notifications n
LEFT JOIN public.post_reports pr ON (n.metadata->>'report_id')::UUID = pr.id
WHERE n.type = 'system'
  AND n.metadata->>'action' = 'report_processed'
  AND n.created_at > NOW() - INTERVAL '7 days';
*/

