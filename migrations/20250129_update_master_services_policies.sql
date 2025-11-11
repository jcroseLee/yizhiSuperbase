-- Update RLS policies on master_services to allow admin access
DO $$
BEGIN
  -- Update insert policy
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'master_services'
      AND policyname = 'master_services_insert_own'
  ) THEN
    DROP POLICY "master_services_insert_own" ON public.master_services;
  END IF;

  CREATE POLICY "master_services_insert_admin_or_owner"
    ON public.master_services FOR INSERT
    WITH CHECK (
      auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    );

  -- Update update policy
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'master_services'
      AND policyname = 'master_services_update_own'
  ) THEN
    DROP POLICY "master_services_update_own" ON public.master_services;
  END IF;

  CREATE POLICY "master_services_update_admin_or_owner"
    ON public.master_services FOR UPDATE
    USING (
      auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    )
    WITH CHECK (
      auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    );

  -- Update delete policy
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'master_services'
      AND policyname = 'master_services_delete_own'
  ) THEN
    DROP POLICY "master_services_delete_own" ON public.master_services;
  END IF;

  CREATE POLICY "master_services_delete_admin_or_owner"
    ON public.master_services FOR DELETE
    USING (
      auth.uid() IN (SELECT user_id FROM public.masters WHERE id = master_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
      )
    );
END $$;

