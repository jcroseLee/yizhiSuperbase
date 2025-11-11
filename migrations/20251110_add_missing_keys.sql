-- Add missing key columns to divination_records table if they don't exist

ALTER TABLE public.divination_records
  ADD COLUMN IF NOT EXISTS original_key text;

ALTER TABLE public.divination_records
  ADD COLUMN IF NOT EXISTS changed_key text;