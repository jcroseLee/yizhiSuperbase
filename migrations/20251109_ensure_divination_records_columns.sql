-- Ensure divination_records table and required jsonb columns exist

-- Create table if it doesn't exist (idempotent)
CREATE TABLE IF NOT EXISTS public.divination_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  question text,
  divination_time timestamptz NOT NULL DEFAULT now(),
  method smallint NOT NULL,
  lines text[] NOT NULL,
  changing_flags boolean[] NOT NULL,
  original_key text NOT NULL,
  changed_key text NOT NULL,
  original_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  changed_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Add jsonb columns if missing on existing table
ALTER TABLE public.divination_records
  ADD COLUMN IF NOT EXISTS original_json jsonb;

ALTER TABLE public.divination_records
  ADD COLUMN IF NOT EXISTS changed_json jsonb;

-- Set defaults and backfill nulls
ALTER TABLE public.divination_records
  ALTER COLUMN original_json SET DEFAULT '{}'::jsonb;

ALTER TABLE public.divination_records
  ALTER COLUMN changed_json SET DEFAULT '{}'::jsonb;

UPDATE public.divination_records
SET original_json = '{}'::jsonb
WHERE original_json IS NULL;

UPDATE public.divination_records
SET changed_json = '{}'::jsonb
WHERE changed_json IS NULL;

-- Set NOT NULL constraints if possible
DO $$
BEGIN
  BEGIN
    ALTER TABLE public.divination_records ALTER COLUMN original_json SET NOT NULL;
  EXCEPTION WHEN others THEN
    -- Ignore if existing rows prevent NOT NULL; defaults and backfill applied above
    NULL;
  END;

  BEGIN
    ALTER TABLE public.divination_records ALTER COLUMN changed_json SET NOT NULL;
  EXCEPTION WHEN others THEN
    NULL;
  END;
END$$;