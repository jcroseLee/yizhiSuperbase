-- Ensure master_services table has all required columns from consultation workflow enhancement
-- This migration ensures the columns exist even if the previous migration wasn't applied

-- Add consultation_duration_minutes column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'consultation_duration_minutes'
  ) THEN
    ALTER TABLE public.master_services
      ADD COLUMN consultation_duration_minutes integer CHECK (consultation_duration_minutes >= 0);
    
    COMMENT ON COLUMN public.master_services.consultation_duration_minutes IS '服务时长（分钟），用于展示剩余服务时长';
  END IF;
END $$;

-- Add consultation_session_count column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'consultation_session_count'
  ) THEN
    ALTER TABLE public.master_services
      ADD COLUMN consultation_session_count integer DEFAULT 1 CHECK (consultation_session_count > 0);
    
    COMMENT ON COLUMN public.master_services.consultation_session_count IS '包含的服务次数';
  END IF;
END $$;

-- Add requires_birth_info column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'requires_birth_info'
  ) THEN
    ALTER TABLE public.master_services
      ADD COLUMN requires_birth_info boolean DEFAULT true;
    
    COMMENT ON COLUMN public.master_services.requires_birth_info IS '是否要求填写出生信息';
  END IF;
END $$;

-- Add question_min_length column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'question_min_length'
  ) THEN
    ALTER TABLE public.master_services
      ADD COLUMN question_min_length integer DEFAULT 30 CHECK (question_min_length BETWEEN 10 AND 2000);
    
    COMMENT ON COLUMN public.master_services.question_min_length IS '问题描述最小字数要求';
  END IF;
END $$;

-- Add question_max_length column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'question_max_length'
  ) THEN
    ALTER TABLE public.master_services
      ADD COLUMN question_max_length integer DEFAULT 500 CHECK (question_max_length BETWEEN 50 AND 2000 AND question_max_length >= question_min_length);
    
    COMMENT ON COLUMN public.master_services.question_max_length IS '问题描述最大字数要求';
  END IF;
END $$;

