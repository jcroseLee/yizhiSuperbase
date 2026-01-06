-- Create reports table for user reports on posts, comments, and users

CREATE TABLE IF NOT EXISTS public.reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
  
  -- Target (polymorphic association)
  target_id uuid NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('post', 'comment', 'user')),
  
  -- Report details
  reason_category text NOT NULL CHECK (reason_category IN (
    'compliance',      -- Illegal / Sensitive content
    'superstition',    -- Superstition / Supernatural claims
    'scam',            -- Advertising / Fraud
    'attack',          -- Personal attack / Trolling
    'spam'             -- Spam / Inappropriate content
  )),
  description text, -- Additional description (max 200 chars)
  
  -- Processing status
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'rejected')) NOT NULL,
  admin_note text, -- Admin processing note
  resolved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, -- Resolver
  resolved_at timestamptz, -- Resolution time
  
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_reports_status ON public.reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON public.reports(target_id, target_type);
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON public.reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON public.reports(created_at DESC);

-- Note: Duplicate report prevention is implemented in application layer (submitReport function)
-- Because index WHERE clauses cannot use non-IMMUTABLE functions (like now())
-- If database-level constraint is needed, use a trigger

-- Enable RLS
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
  -- Users can only view their own reports
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reports' 
    AND policyname = 'reports_select_own'
  ) THEN
    CREATE POLICY "reports_select_own"
      ON public.reports FOR SELECT
      USING (auth.uid() = reporter_id);
  END IF;
  
  -- Users can only submit their own reports
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reports' 
    AND policyname = 'reports_insert_own'
  ) THEN
    CREATE POLICY "reports_insert_own"
      ON public.reports FOR INSERT
      WITH CHECK (auth.uid() = reporter_id);
  END IF;
  
  -- Admins can view and process all reports
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'reports' 
    AND policyname = 'reports_admin_all'
  ) THEN
    CREATE POLICY "reports_admin_all"
      ON public.reports FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_reports_updated_at_trigger ON public.reports;
CREATE TRIGGER update_reports_updated_at_trigger
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION update_reports_updated_at();

-- Auto-hide mechanism: Hide content if reported by 3+ different users within 1 hour
CREATE OR REPLACE FUNCTION auto_hide_reported_content()
RETURNS TRIGGER AS $$
DECLARE
  report_count INTEGER;
BEGIN
  -- Count distinct reporters in the last hour
  SELECT COUNT(DISTINCT reporter_id) INTO report_count
  FROM public.reports
  WHERE target_id = NEW.target_id
    AND target_type = NEW.target_type
    AND status = 'pending'
    AND created_at > now() - interval '1 hour';
  
  -- Auto-hide if 3+ reports
  IF report_count >= 3 THEN
    IF NEW.target_type = 'post' THEN
      -- Hide post (if status column exists)
      IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'posts' 
        AND column_name = 'status'
      ) THEN
        UPDATE public.posts
        SET status = 'hidden'
        WHERE id = NEW.target_id
          AND (status IS NULL OR status != 'hidden');
      END IF;
    ELSIF NEW.target_type = 'comment' THEN
      -- Hide comment (if status column exists)
      IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'comments' 
        AND column_name = 'status'
      ) THEN
        UPDATE public.comments
        SET status = 'hidden'
        WHERE id = NEW.target_id
          AND (status IS NULL OR status != 'hidden');
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS auto_hide_reported_content_trigger ON public.reports;
CREATE TRIGGER auto_hide_reported_content_trigger
  AFTER INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION auto_hide_reported_content();

-- Table comments
COMMENT ON TABLE public.reports IS 'Reports table for storing user reports on posts, comments, and users';
COMMENT ON COLUMN public.reports.reason_category IS 'Report reason category: compliance(illegal), superstition(supernatural), scam(advertising/fraud), attack(personal attack), spam(inappropriate)';
COMMENT ON COLUMN public.reports.status IS 'Processing status: pending(awaiting), resolved(processed), rejected(dismissed)';
