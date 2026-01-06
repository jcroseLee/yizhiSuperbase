-- Verification script for reports table migration
-- Run this after applying 20250201_create_reports_table.sql to verify everything is set up correctly

-- 1. Check if table exists
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name = 'reports'
    ) THEN '✓ Table "reports" exists'
    ELSE '✗ Table "reports" does NOT exist'
  END AS table_check;

-- 2. Check table structure
SELECT 
  'Table Structure:' AS check_type,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'reports'
ORDER BY ordinal_position;

-- 3. Check indexes
SELECT 
  'Indexes:' AS check_type,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public' 
AND tablename = 'reports'
ORDER BY indexname;

-- 4. Check RLS policies
SELECT 
  'RLS Policies:' AS check_type,
  policyname,
  cmd AS command,
  CASE 
    WHEN qual IS NOT NULL THEN 'Has USING clause'
    ELSE 'No USING clause'
  END AS using_clause,
  CASE 
    WHEN with_check IS NOT NULL THEN 'Has WITH CHECK clause'
    ELSE 'No WITH CHECK clause'
  END AS with_check_clause
FROM pg_policies
WHERE schemaname = 'public' 
AND tablename = 'reports'
ORDER BY policyname;

-- 5. Check triggers
SELECT 
  'Triggers:' AS check_type,
  trigger_name,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND event_object_table = 'reports'
ORDER BY trigger_name;

-- 6. Check functions
SELECT 
  'Functions:' AS check_type,
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('update_reports_updated_at', 'auto_hide_reported_content')
ORDER BY routine_name;

-- 7. Summary check
SELECT 
  'Summary:' AS check_type,
  (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reports') AS table_exists,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'reports') AS column_count,
  (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'reports') AS index_count,
  (SELECT COUNT(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'reports') AS policy_count,
  (SELECT COUNT(*) FROM information_schema.triggers WHERE event_object_schema = 'public' AND event_object_table = 'reports') AS trigger_count;
