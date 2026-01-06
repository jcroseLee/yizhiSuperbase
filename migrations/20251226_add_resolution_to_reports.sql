-- Add resolution column to reports table
-- This column is required by the CMS to track specific resolution actions (approved, rejected, deleted, banned)

ALTER TABLE public.reports
ADD COLUMN IF NOT EXISTS resolution TEXT CHECK (resolution IN ('approved', 'rejected', 'deleted', 'banned'));

COMMENT ON COLUMN public.reports.resolution IS 'Resolution type: approved, rejected, deleted, banned';

-- Update the reports table definition comments
COMMENT ON TABLE public.reports IS 'Reports table for storing user reports on posts, comments, and users';
