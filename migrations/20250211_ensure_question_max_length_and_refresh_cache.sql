-- Ensure question_max_length column exists in master_services
-- This migration ensures the column exists and attempts to refresh PostgREST schema cache

-- First, ensure question_min_length exists (prerequisite)
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
  -- Check if column exists
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name = 'question_max_length'
  ) THEN
    -- Column exists, ensure it has correct type and constraints
    ALTER TABLE public.master_services
      ALTER COLUMN question_max_length TYPE integer,
      ALTER COLUMN question_max_length SET DEFAULT 500,
      DROP CONSTRAINT IF EXISTS master_services_question_max_length_check,
      ADD CONSTRAINT master_services_question_max_length_check 
        CHECK (question_max_length BETWEEN 50 AND 2000);
  ELSE
    -- Column doesn't exist, create it
    ALTER TABLE public.master_services
      ADD COLUMN question_max_length integer DEFAULT 500 
        CHECK (question_max_length BETWEEN 50 AND 2000);
    
    COMMENT ON COLUMN public.master_services.question_max_length IS '问题描述最大字数要求';
  END IF;
END $$;

-- Ensure question_max_length >= question_min_length constraint exists
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

-- Ensure requires_birth_info exists (for schema cache refresh)
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

-- Force PostgREST to reload schema by creating a dummy function and dropping it
-- This sometimes helps refresh the schema cache
DO $$
BEGIN
  -- Create a temporary function that checks multiple columns to force schema reload
  CREATE OR REPLACE FUNCTION pg_temp._refresh_schema_cache()
  RETURNS void
  LANGUAGE plpgsql
  AS $function$
  BEGIN
    -- This function checks multiple columns to force a schema reload
    PERFORM 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'master_services' 
      AND column_name IN (
        'question_max_length',
        'question_min_length',
        'requires_birth_info',
        'consultation_duration_minutes',
        'consultation_session_count'
      );
  END;
  $function$;
  
  -- Execute it
  PERFORM pg_temp._refresh_schema_cache();
  
  -- Drop it
  DROP FUNCTION IF EXISTS pg_temp._refresh_schema_cache();
END $$;

-- Note: After applying this migration, if the error persists, you MUST manually refresh 
-- the PostgREST schema cache via Supabase Dashboard:
-- 1. Go to Settings > API
-- 2. Click "Reload schema" button
-- 3. Or restart the PostgREST service
--
-- The schema cache refresh is required because PostgREST caches table schemas for performance,
-- and it doesn't automatically detect column additions in some cases.

