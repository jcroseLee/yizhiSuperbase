-- 移除卦师管理模块
-- 删除所有卦师相关的表、函数、触发器等

BEGIN;

-- ============================================
-- 1. 删除触发器
-- ============================================

-- 删除 master_reviews 相关的触发器
DROP TRIGGER IF EXISTS update_master_stats_trigger ON public.master_reviews;
DROP TRIGGER IF EXISTS update_master_review_updated_at_trigger ON public.master_reviews;

-- 删除 masters 相关的触发器
DROP TRIGGER IF EXISTS update_master_updated_at_trigger ON public.masters;

-- 删除 master_services 相关的触发器
DROP TRIGGER IF EXISTS update_master_service_updated_at_trigger ON public.master_services;

-- ============================================
-- 2. 删除函数
-- ============================================

-- 删除卦师相关的函数
DROP FUNCTION IF EXISTS update_master_stats() CASCADE;
DROP FUNCTION IF EXISTS update_master_updated_at() CASCADE;
DROP FUNCTION IF EXISTS update_master_review_updated_at() CASCADE;
DROP FUNCTION IF EXISTS update_master_service_updated_at() CASCADE;

-- ============================================
-- 3. 删除表（按依赖关系顺序）
-- ============================================

-- 删除结算相关表（依赖 consultations）
DROP TABLE IF EXISTS public.master_settlements CASCADE;

-- 删除平台托管账户表（依赖 consultations）
DROP TABLE IF EXISTS public.platform_escrow CASCADE;

-- 删除咨询订单表（依赖 master_services 和 masters）
DROP TABLE IF EXISTS public.consultations CASCADE;

-- 删除大师服务表（依赖 masters）
DROP TABLE IF EXISTS public.master_services CASCADE;

-- 删除用户关注大师表（依赖 masters）
DROP TABLE IF EXISTS public.master_follows CASCADE;

-- 删除大师评价表（依赖 masters）
DROP TABLE IF EXISTS public.master_reviews CASCADE;

-- 删除大师表
DROP TABLE IF EXISTS public.masters CASCADE;

-- ============================================
-- 4. 更新 risk_control_violations 表
-- 移除 consultation_id 列（如果存在）
-- ============================================

-- 删除 consultation_id 外键约束（如果存在）
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_schema = 'public' 
    AND table_name = 'risk_control_violations' 
    AND constraint_name = 'risk_control_violations_consultation_id_fkey'
  ) THEN
    ALTER TABLE public.risk_control_violations 
    DROP CONSTRAINT risk_control_violations_consultation_id_fkey;
  END IF;
END $$;

-- 删除 consultation_id 列（如果存在）
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'risk_control_violations' 
    AND column_name = 'consultation_id'
  ) THEN
    ALTER TABLE public.risk_control_violations 
    DROP COLUMN consultation_id;
  END IF;
END $$;

-- 删除 consultation_id 索引（如果存在）
DROP INDEX IF EXISTS public.idx_risk_control_consultation;

-- 更新 violation_type 约束，移除 'private_transaction'
DO $$
BEGIN
  -- 检查约束是否存在
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conrelid = 'public.risk_control_violations'::regclass 
    AND conname = 'risk_control_violations_violation_type_check'
  ) THEN
    -- 删除旧约束
    ALTER TABLE public.risk_control_violations 
    DROP CONSTRAINT risk_control_violations_violation_type_check;
    
    -- 添加新约束（移除 private_transaction）
    ALTER TABLE public.risk_control_violations 
    ADD CONSTRAINT risk_control_violations_violation_type_check 
    CHECK (violation_type IN ('inappropriate_content', 'spam'));
  END IF;
END $$;

-- ============================================
-- 4. 清理 modules 表中的卦师模块记录（如果存在）
-- ============================================

DELETE FROM public.modules 
WHERE name = 'masters' OR display_name = '卦师功能';

COMMIT;

