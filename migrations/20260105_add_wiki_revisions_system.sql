
-- Create wiki_revisions table
CREATE TABLE IF NOT EXISTS wiki_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id UUID REFERENCES wiki_articles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT,
  summary TEXT,
  author_name TEXT,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  change_description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE wiki_revisions ENABLE ROW LEVEL SECURITY;

-- Policies for wiki_revisions

-- Public can create revisions (insert)
CREATE POLICY "Public can create revisions" ON wiki_revisions FOR INSERT WITH CHECK (true);

-- Users can view their own revisions (optional, but good practice)
-- But since we have anonymous submissions (author_name), we might not be able to link back unless we rely on session.
-- For now, let's allow admins to see all.
CREATE POLICY "Admins can view all revisions" ON wiki_revisions FOR SELECT USING (
  exists (
    select 1 from public.profiles
    where profiles.id = auth.uid()
    and profiles.role = 'admin'
  )
);

CREATE POLICY "Admins can update revisions" ON wiki_revisions FOR UPDATE USING (
  exists (
    select 1 from public.profiles
    where profiles.id = auth.uid()
    and profiles.role = 'admin'
  )
);

-- Add last_revision_id and contributors to wiki_articles
ALTER TABLE wiki_articles 
ADD COLUMN IF NOT EXISTS last_revision_id UUID REFERENCES wiki_revisions(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS contributors JSONB DEFAULT '[]'::jsonb;

