-- 声望段位体系完善
-- 添加评论采纳功能和声望记录表

-- 1. 添加评论采纳字段
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS is_adopted BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS adopted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS adopted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_comments_is_adopted ON public.comments(is_adopted) WHERE is_adopted = TRUE;
CREATE INDEX IF NOT EXISTS idx_comments_adopted_by ON public.comments(adopted_by) WHERE adopted_by IS NOT NULL;

-- 2. 创建声望变化记录表（用于审计和统计）
CREATE TABLE IF NOT EXISTS public.reputation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL, -- 声望变化量（正数为增加，负数为扣除）
  reason TEXT NOT NULL, -- 原因说明
  related_id UUID, -- 关联ID（如评论ID、帖子ID等）
  related_type TEXT, -- 关联类型：'comment', 'post', 'verification', 'violation', 'admin'
  reputation_before INTEGER NOT NULL, -- 变化前的声望值
  reputation_after INTEGER NOT NULL, -- 变化后的声望值
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_reputation_logs_user_id ON public.reputation_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_reputation_logs_created_at ON public.reputation_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reputation_logs_related ON public.reputation_logs(related_id, related_type) WHERE related_id IS NOT NULL;

-- 启用RLS
ALTER TABLE public.reputation_logs ENABLE ROW LEVEL SECURITY;

-- RLS策略：用户只能查看自己的声望记录
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reputation_logs' 
    AND policyname = 'reputation_logs_select_own'
  ) THEN
    CREATE POLICY "reputation_logs_select_own"
      ON public.reputation_logs FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- RLS策略：管理员可以查看所有记录
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reputation_logs' 
    AND policyname = 'reputation_logs_admin_all'
  ) THEN
    CREATE POLICY "reputation_logs_admin_all"
      ON public.reputation_logs FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- 3. 创建函数：当评论被采纳时，自动增加评论作者的声望值
CREATE OR REPLACE FUNCTION public.add_reputation_on_comment_adopted()
RETURNS TRIGGER AS $$
BEGIN
  -- 只有当评论被采纳（is_adopted 从 false 变为 true）时才增加声望
  IF NEW.is_adopted = TRUE AND (OLD.is_adopted IS NULL OR OLD.is_adopted = FALSE) THEN
    -- 增加评论作者的声望值 +10
    UPDATE public.profiles
    SET reputation = COALESCE(reputation, 0) + 10
    WHERE id = NEW.user_id;
    
    -- 记录声望变化日志
    INSERT INTO public.reputation_logs (
      user_id,
      amount,
      reason,
      related_id,
      related_type,
      reputation_before,
      reputation_after
    )
    SELECT 
      NEW.user_id,
      10,
      '断语被题主采纳',
      NEW.id,
      'comment',
      COALESCE(reputation, 0),
      COALESCE(reputation, 0) + 10
    FROM public.profiles
    WHERE id = NEW.user_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 创建触发器
DROP TRIGGER IF EXISTS trigger_add_reputation_on_comment_adopted ON public.comments;
CREATE TRIGGER trigger_add_reputation_on_comment_adopted
  AFTER UPDATE OF is_adopted ON public.comments
  FOR EACH ROW
  WHEN (NEW.is_adopted IS DISTINCT FROM OLD.is_adopted)
  EXECUTE FUNCTION public.add_reputation_on_comment_adopted();

-- 4. 创建函数：当评论被折叠/违规时，扣除评论作者的声望值
CREATE OR REPLACE FUNCTION public.deduct_reputation_on_comment_violation()
RETURNS TRIGGER AS $$
BEGIN
  -- 如果评论被标记为违规（is_folded = true 或 violation_detected = true）
  -- 注意：需要根据实际的违规标记字段调整
  IF NEW.is_folded = TRUE AND (OLD.is_folded IS NULL OR OLD.is_folded = FALSE) THEN
    -- 扣除评论作者的声望值 -5
    UPDATE public.profiles
    SET reputation = GREATEST(COALESCE(reputation, 0) - 5, 0) -- 声望值不能为负数
    WHERE id = NEW.user_id;
    
    -- 记录声望变化日志
    INSERT INTO public.reputation_logs (
      user_id,
      amount,
      reason,
      related_id,
      related_type,
      reputation_before,
      reputation_after
    )
    SELECT 
      NEW.user_id,
      -5,
      '断语被折叠/违规',
      NEW.id,
      'comment',
      COALESCE(reputation, 0),
      GREATEST(COALESCE(reputation, 0) - 5, 0)
    FROM public.profiles
    WHERE id = NEW.user_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 创建触发器（如果 comments 表有 is_folded 字段）
-- 注意：如果表结构中没有 is_folded 字段，需要先添加
-- ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS is_folded BOOLEAN DEFAULT FALSE;

-- 5. 更新验证函数，使用新的声望记录表
-- 注意：这个函数已经在之前的迁移中创建，这里只是确保它使用新的日志表
CREATE OR REPLACE FUNCTION public.update_reputation_on_verification()
RETURNS TRIGGER AS $$
DECLARE
  current_reputation INTEGER;
  new_reputation INTEGER;
BEGIN
  -- 如果验证结果为"准"，增加声望值
  IF NEW.verification_result = 'accurate' AND (OLD.verification_result IS NULL OR OLD.verification_result != 'accurate') THEN
    -- 获取当前声望值
    SELECT COALESCE(reputation, 0) INTO current_reputation
    FROM public.profiles
    WHERE id = NEW.user_id;
    
    -- 增加声望值（+20，根据PRD）
    new_reputation := current_reputation + 20;
    
    UPDATE public.profiles
    SET reputation = new_reputation
    WHERE id = NEW.user_id;
    
    -- 记录声望变化日志
    INSERT INTO public.reputation_logs (
      user_id,
      amount,
      reason,
      related_id,
      related_type,
      reputation_before,
      reputation_after
    ) VALUES (
      NEW.user_id,
      20,
      '断语被验证为"准"',
      NEW.id,
      'comment',
      current_reputation,
      new_reputation
    );
  END IF;
  
  -- 如果验证结果为"不准"，不扣声望值（根据PRD），但记录日志用于计算准确率
  -- 这里不需要做任何操作，因为PRD规定不扣分
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. 添加注释
COMMENT ON TABLE public.reputation_logs IS '声望变化记录表，用于审计和统计用户的声望变化历史';
COMMENT ON COLUMN public.reputation_logs.amount IS '声望变化量：正数为增加，负数为扣除';
COMMENT ON COLUMN public.reputation_logs.reason IS '声望变化的原因说明';
COMMENT ON COLUMN public.reputation_logs.related_type IS '关联类型：comment（评论）、post（帖子）、verification（验证）、violation（违规）、admin（管理员操作）';

COMMENT ON COLUMN public.comments.is_adopted IS '是否被题主采纳';
COMMENT ON COLUMN public.comments.adopted_at IS '采纳时间';
COMMENT ON COLUMN public.comments.adopted_by IS '采纳者ID（题主）';

