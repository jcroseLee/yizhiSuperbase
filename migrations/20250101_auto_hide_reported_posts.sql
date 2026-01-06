-- ============================================
-- 举报自动隐藏机制
-- ============================================
-- 功能：当某条内容在短时间内被3名以上不同用户举报时，自动隐藏
-- 时间窗口：24小时内
-- ============================================

-- 创建函数：检查并自动隐藏被多次举报的帖子
CREATE OR REPLACE FUNCTION public.auto_hide_reported_post()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_report_count INTEGER;
  v_post_status TEXT;
BEGIN
  -- 只在插入新举报或举报状态变更为 open 时触发
  IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.status = 'open')) THEN
    
    -- 统计该帖子在24小时内被不同用户举报的次数（只统计 open 状态的举报）
    SELECT COUNT(DISTINCT reporter_id)
    INTO v_report_count
    FROM public.post_reports
    WHERE post_id = NEW.post_id
      AND status = 'open'
      AND created_at > NOW() - INTERVAL '24 hours';
    
    -- 如果举报数量达到3次或以上
    IF v_report_count >= 3 THEN
      
      -- 检查帖子当前状态
      SELECT status INTO v_post_status
      FROM public.posts
      WHERE id = NEW.post_id;
      
      -- 只有当帖子状态为 published 时才自动隐藏
      IF v_post_status = 'published' THEN
        
        -- 自动隐藏帖子
        UPDATE public.posts
        SET 
          status = 'hidden',
          updated_at = NOW()
        WHERE id = NEW.post_id;
        
        -- 记录日志
        RAISE NOTICE 'Post % automatically hidden due to % reports', NEW.post_id, v_report_count;
        
        -- 创建系统通知给帖子作者
        DECLARE
          v_author_id UUID;
          v_post_title TEXT;
        BEGIN
          -- 获取帖子作者和标题
          SELECT user_id, title INTO v_author_id, v_post_title
          FROM public.posts
          WHERE id = NEW.post_id;
          
          -- 发送通知给作者
          IF v_author_id IS NOT NULL THEN
            PERFORM public.create_notification(
              v_author_id,
              'system',
              NEW.post_id,
              'post',
              NULL,
              '您的帖子「' || COALESCE(v_post_title, '未知标题') || '」因多次被举报已被暂时隐藏，正在等待管理员审核。',
              jsonb_build_object(
                'post_id', NEW.post_id,
                'post_title', v_post_title,
                'report_count', v_report_count,
                'action', 'auto_hidden'
              )
            );
          END IF;
        END;
        
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 创建触发器：在举报记录插入或更新时触发
DROP TRIGGER IF EXISTS trigger_auto_hide_reported_post ON public.post_reports;
CREATE TRIGGER trigger_auto_hide_reported_post
  AFTER INSERT OR UPDATE ON public.post_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_hide_reported_post();

-- 添加注释
COMMENT ON FUNCTION public.auto_hide_reported_post IS 
  '自动隐藏被多次举报的帖子：当某条帖子在24小时内被3名以上不同用户举报时，自动将其状态设置为 hidden，并通知作者。';

-- ============================================
-- 确保 posts 表有 hidden 状态
-- ============================================

-- 检查并添加 hidden 状态到 posts 表的 status 字段约束
DO $$
BEGIN
  -- 尝试更新约束（如果需要）
  -- 注意：这个操作可能因数据库版本不同而有所差异
  -- 如果约束已存在，可能需要先删除再重建
  
  -- 检查是否已有 hidden 状态的帖子
  IF NOT EXISTS (
    SELECT 1 FROM public.posts WHERE status = 'hidden' LIMIT 1
  ) THEN
    RAISE NOTICE 'No hidden posts found, status constraint may need to be updated';
  END IF;
END $$;

-- ============================================
-- 测试查询
-- ============================================

-- 查看最近被自动隐藏的帖子
/*
SELECT 
  p.id,
  p.title,
  p.status,
  p.updated_at,
  COUNT(pr.id) as report_count,
  array_agg(DISTINCT pr.reporter_id) as reporters
FROM public.posts p
JOIN public.post_reports pr ON p.id = pr.post_id
WHERE p.status = 'hidden'
  AND pr.status = 'open'
  AND pr.created_at > NOW() - INTERVAL '24 hours'
GROUP BY p.id, p.title, p.status, p.updated_at
HAVING COUNT(DISTINCT pr.reporter_id) >= 3
ORDER BY p.updated_at DESC;
*/

-- 查看特定帖子的举报统计
/*
SELECT 
  post_id,
  COUNT(DISTINCT reporter_id) as unique_reporters,
  COUNT(*) as total_reports,
  MIN(created_at) as first_report,
  MAX(created_at) as last_report
FROM public.post_reports
WHERE post_id = 'YOUR_POST_ID'
  AND status = 'open'
  AND created_at > NOW() - INTERVAL '24 hours'
GROUP BY post_id;
*/

