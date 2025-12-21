-- Add admin policies for profiles table to allow admins to update any user's profile
-- This is needed for CMS operations like awarding reputation

-- Use the existing is_admin() function to avoid recursion
-- Ensure the function exists
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  );
$$;

-- Add admin update policy for profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'profiles' 
    AND policyname = 'profiles_admin_update_all'
  ) THEN
    CREATE POLICY "profiles_admin_update_all"
      ON public.profiles FOR UPDATE
      USING (public.is_admin())
      WITH CHECK (public.is_admin());
  END IF;
END $$;

-- Add admin insert policy for reputation_logs (if not already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reputation_logs' 
    AND policyname = 'reputation_logs_admin_insert'
  ) THEN
    CREATE POLICY "reputation_logs_admin_insert"
      ON public.reputation_logs FOR INSERT
      WITH CHECK (public.is_admin());
  END IF;
END $$;

