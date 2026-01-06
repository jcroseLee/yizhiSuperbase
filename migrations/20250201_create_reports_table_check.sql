-- Quick diagnostic check for reports table
-- Run this FIRST to see what's missing

-- Check if table exists
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name = 'reports'
    ) THEN '✓ Table "reports" EXISTS - Migration has been applied'
    ELSE '✗ Table "reports" does NOT exist - You need to apply the migration'
  END AS status;

-- If table doesn't exist, show this message:
SELECT 
  'NEXT STEP: Copy and run the migration file: supabase/migrations/20250201_create_reports_table.sql' AS instruction
WHERE NOT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'reports'
);

