-- ============================================
-- 清理旧的举报通知（CMS 代码发送的）
-- ============================================
-- 目的：删除 CMS 代码发送的举报通知，只保留触发器发送的系统通知
-- 
-- 区别：
-- - CMS 通知：type = 'report_resolved' 或 'report_rejected'
-- - 触发器通知：type = 'system', metadata->>'action' = 'report_processed'
-- ============================================

-- 1️⃣ 查看所有举报相关通知
SELECT 
  id,
  type,
  content,
  metadata->>'action' as action,
  metadata->>'post_title' as post_title,
  metadata->>'source' as source,
  created_at,
  is_read
FROM public.notifications
WHERE (
  type IN ('report_resolved', 'report_rejected')  -- CMS 发送的
  OR metadata->>'action' = 'report_processed'     -- 触发器发送的
)
ORDER BY created_at DESC;

-- 2️⃣ 统计不同类型的通知数量
SELECT 
  CASE 
    WHEN type = 'report_resolved' THEN 'CMS: 举报已处理'
    WHEN type = 'report_rejected' THEN 'CMS: 举报已驳回'
    WHEN type = 'system' AND metadata->>'action' = 'report_processed' THEN '触发器: 系统通知'
    ELSE '其他'
  END as notification_source,
  COUNT(*) as count,
  COUNT(CASE WHEN is_read = FALSE THEN 1 END) as unread_count
FROM public.notifications
WHERE (
  type IN ('report_resolved', 'report_rejected')
  OR metadata->>'action' = 'report_processed'
)
GROUP BY notification_source;

-- 3️⃣ 删除 CMS 发送的举报通知（保留触发器通知）
-- ⚠️ 请先执行上面的查询确认要删除的内容
DELETE FROM public.notifications
WHERE type IN ('report_resolved', 'report_rejected');

-- 4️⃣ 验证删除结果
SELECT 
  type,
  COUNT(*) as count
FROM public.notifications
WHERE (
  type IN ('report_resolved', 'report_rejected')
  OR metadata->>'action' = 'report_processed'
)
GROUP BY type;

-- 5️⃣ 查看剩余的系统通知（应该只有触发器发送的）
SELECT 
  id,
  user_id,
  content,
  metadata->>'post_title' as post_title,
  metadata->>'source' as source,
  created_at
FROM public.notifications
WHERE metadata->>'action' = 'report_processed'
ORDER BY created_at DESC
LIMIT 10;

-- ============================================
-- 可选：删除特定帖子的 CMS 通知
-- ============================================

-- 删除"科技活动数据库和抽卡打撤"帖子的 CMS 通知
/*
DELETE FROM public.notifications
WHERE type IN ('report_resolved', 'report_rejected')
  AND metadata->>'post_title' = '科技活动数据库和抽卡打撤';
*/

-- ============================================
-- 总结
-- ============================================

-- 执行步骤：
-- 1. 先运行第 1、2 步查询，确认要删除的通知
-- 2. 运行第 3 步删除 CMS 通知
-- 3. 运行第 4、5 步验证删除结果
-- 
-- 预期结果：
-- - 删除所有 type = 'report_resolved' 或 'report_rejected' 的通知
-- - 保留所有 type = 'system' 且 metadata->>'action' = 'report_processed' 的通知
-- - 以后只会有触发器发送的系统通知，不会有重复通知

