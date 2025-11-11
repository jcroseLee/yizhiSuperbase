-- Ensure all required columns exist in divination_records table
-- This migration is idempotent and safe to run multiple times

-- Add changed_json column if it doesn't exist
ALTER TABLE public.divination_records 
ADD COLUMN IF NOT EXISTS changed_json jsonb;

-- Add original_json column if it doesn't exist  
ALTER TABLE public.divination_records 
ADD COLUMN IF NOT EXISTS original_json jsonb;

-- Update existing rows to have default values if needed
UPDATE public.divination_records 
SET changed_json = '{}'::jsonb 
WHERE changed_json IS NULL;

UPDATE public.divination_records 
SET original_json = '{}'::jsonb 
WHERE original_json IS NULL;
