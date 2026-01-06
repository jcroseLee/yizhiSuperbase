-- Add contributors column to wiki_articles if not exists
ALTER TABLE wiki_articles 
ADD COLUMN IF NOT EXISTS contributors JSONB DEFAULT '[]'::jsonb;

-- Add last_revision_id column to wiki_articles if not exists
-- This depends on wiki_revisions table being created first
ALTER TABLE wiki_articles
ADD COLUMN IF NOT EXISTS last_revision_id UUID REFERENCES wiki_revisions(id) ON DELETE SET NULL;

-- Comment on columns
COMMENT ON COLUMN wiki_articles.contributors IS 'List of contributors with name, id (optional), and date';
COMMENT ON COLUMN wiki_articles.last_revision_id IS 'ID of the last applied revision';
