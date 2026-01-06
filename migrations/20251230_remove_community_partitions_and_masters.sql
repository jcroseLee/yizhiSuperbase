-- 1. Drop Certified Diviner related tables
DROP TABLE IF EXISTS public.risk_control_violations CASCADE;
DROP TABLE IF EXISTS public.master_settlements CASCADE;
DROP TABLE IF EXISTS public.master_follows CASCADE;
DROP TABLE IF EXISTS public.master_services CASCADE;
DROP TABLE IF EXISTS public.consultations CASCADE;
DROP TABLE IF EXISTS public.masters CASCADE;

-- 2. Drop Community Sections and Subsections tables
DROP TABLE IF EXISTS public.community_subsections CASCADE;
DROP TABLE IF EXISTS public.community_sections CASCADE;

-- 3. Remove columns from posts table
ALTER TABLE public.posts DROP COLUMN IF EXISTS subsection;
ALTER TABLE public.posts DROP COLUMN IF EXISTS section;
