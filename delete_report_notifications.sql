-- ============================================
-- 删除举报处理通知
-- ============================================

-- 方法 1：删除特定帖子的举报通知
-- 适用于：删除某个特定帖子相关的举报通知
DELETE FROM public.notifications
WHERE metadata->>'post_title' = '测试again'
  AND type = 'system'
  AND (metadata->>'action' = 'report_processed' OR content LIKE '%举报%已处理%');

-- 方法 2：删除所有举报处理通知
-- 适用于：清空所有举报相关的系统通知
DELETE FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed';

-- 方法 3：删除最近的举报处理通知（最近1小时内）
-- 适用于：只删除刚刚测试产生的通知
DELETE FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed'
  AND created_at > NOW() - INTERVAL '1 hour';

-- 方法 4：查看所有举报处理通知（先查看再决定删除哪些）
SELECT 
  id,
  user_id,
  content,
  metadata->>'post_title' as post_title,
  metadata->>'report_id' as report_id,
  created_at,
  is_read
FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed'
ORDER BY created_at DESC;

-- 方法 5：标记为已读（不删除，只是标记为已读）
UPDATE public.notifications
SET is_read = TRUE
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed'
  AND is_read = FALSE;

-- ============================================
-- 如果要禁用举报处理通知功能
-- ============================================

-- 选项 A：临时禁用触发器（不推荐，会影响所有通知）
-- ALTER TABLE public.post_reports DISABLE TRIGGER trigger_notify_reporter_on_resolution;

-- 选项 B：删除触发器（如果完全不需要这个功能）
-- DROP TRIGGER IF EXISTS trigger_notify_reporter_on_resolution ON public.post_reports;

-- 选项 C：重新启用触发器
-- ALTER TABLE public.post_reports ENABLE TRIGGER trigger_notify_reporter_on_resolution;
-- 或
-- CREATE TRIGGER trigger_notify_reporter_on_resolution
--   AFTER UPDATE ON public.post_reports
--   FOR EACH ROW
--   EXECUTE FUNCTION public.notify_reporter_on_resolution_dedup();

-- ============================================
-- 推荐操作
-- ============================================

-- 1️⃣ 先查看有哪些通知（推荐先执行这个）
SELECT 
  id,
  content,
  metadata->>'post_title' as post_title,
  created_at
FROM public.notifications
WHERE type = 'system'
  AND content LIKE '%举报%已处理%'
ORDER BY created_at DESC
LIMIT 20;

-- 2️⃣ 然后根据需要选择上面的删除方法

-- 3️⃣ 验证删除结果
SELECT COUNT(*) as remaining_report_notifications
FROM public.notifications
WHERE type = 'system'
  AND metadata->>'action' = 'report_processed';

