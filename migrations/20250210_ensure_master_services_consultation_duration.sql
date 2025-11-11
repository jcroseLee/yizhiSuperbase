-- Ensure consultation_duration_minutes column exists in master_services
-- This migration ensures the column exists and refreshes PostgREST schema cache

-- Drop and recreate the column to ensure it's properly recognized
DO $$
BEGIN
  -- Check if column exists
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'consultation_duration_minutes'
  ) THEN
    -- Column exists, ensure it has the correct type and constraints
    ALTER TABLE public.master_services
      ALTER COLUMN consultation_duration_minutes TYPE integer,
      DROP CONSTRAINT IF EXISTS master_services_consultation_duration_minutes_check,
      ADD CONSTRAINT master_services_consultation_duration_minutes_check 
        CHECK (consultation_duration_minutes IS NULL OR consultation_duration_minutes >= 0);
  ELSE
    -- Column doesn't exist, create it
    ALTER TABLE public.master_services
      ADD COLUMN consultation_duration_minutes integer 
        CHECK (consultation_duration_minutes IS NULL OR consultation_duration_minutes >= 0);
    
    COMMENT ON COLUMN public.master_services.consultation_duration_minutes IS '服务时长（分钟），用于展示剩余服务时长，可为空';
  END IF;
END $$;

-- Ensure consultation_session_count exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'consultation_session_count'
  ) THEN
    -- Ensure default and constraint
    ALTER TABLE public.master_services
      ALTER COLUMN consultation_session_count SET DEFAULT 1,
      DROP CONSTRAINT IF EXISTS master_services_consultation_session_count_check,
      ADD CONSTRAINT master_services_consultation_session_count_check 
        CHECK (consultation_session_count > 0);
  ELSE
    ALTER TABLE public.master_services
      ADD COLUMN consultation_session_count integer DEFAULT 1 
        CHECK (consultation_session_count > 0);
    
    COMMENT ON COLUMN public.master_services.consultation_session_count IS '包含的服务次数';
  END IF;
END $$;

-- Ensure requires_birth_info exists
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

-- Ensure question_min_length exists
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
      ADD COLUMN question_min_length integer DEFAULT 30 
        CHECK (question_min_length BETWEEN 10 AND 2000);
    
    COMMENT ON COLUMN public.master_services.question_min_length IS '问题描述最小字数要求';
  END IF;
END $$;

-- Ensure question_max_length exists
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
      ADD COLUMN question_max_length integer DEFAULT 500 
        CHECK (question_max_length BETWEEN 50 AND 2000);
    
    COMMENT ON COLUMN public.master_services.question_max_length IS '问题描述最大字数要求';
  END IF;
END $$;

-- Ensure question_max_length >= question_min_length constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_constraint 
    WHERE conrelid = 'public.master_services'::regclass
      AND conname = 'master_services_question_length_check'
  ) THEN
    ALTER TABLE public.master_services
      ADD CONSTRAINT master_services_question_length_check 
      CHECK (question_max_length >= question_min_length);
  END IF;
END $$;

-- Note: After applying this migration, PostgREST should automatically refresh its schema cache.
-- If the error persists, you may need to manually refresh the schema cache via Supabase Dashboard:
-- Go to Settings > API > and click "Reload schema" or restart the PostgREST service.

