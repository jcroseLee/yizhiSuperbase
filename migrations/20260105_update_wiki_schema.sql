-- Create library_books table if not exists
CREATE TABLE IF NOT EXISTS public.library_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  author TEXT,
  dynasty TEXT,
  category TEXT,
  status TEXT,
  cover_url TEXT,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.library_books ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'library_books' AND policyname = 'Public can view library books'
    ) THEN
        CREATE POLICY "Public can view library books" ON public.library_books FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'library_books' AND policyname = 'Admins can manage library books'
    ) THEN
        CREATE POLICY "Admins can manage library books" ON public.library_books FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;
END
$$;

-- Update wiki_articles
ALTER TABLE public.wiki_articles 
ADD COLUMN IF NOT EXISTS summary TEXT,
ADD COLUMN IF NOT EXISTS compiled_html TEXT,
ADD COLUMN IF NOT EXISTS related_book_ids UUID[],
ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'draft' CHECK (status IN ('published', 'draft', 'archived'));

-- Migrate is_published to status (if column exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'wiki_articles' AND column_name = 'is_published') THEN
        UPDATE public.wiki_articles SET status = 'published' WHERE is_published = true;
        ALTER TABLE public.wiki_articles DROP COLUMN is_published;
    END IF;
END $$;

-- Create wiki_versions
CREATE TABLE IF NOT EXISTS public.wiki_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id UUID REFERENCES public.wiki_articles(id) ON DELETE CASCADE,
  editor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  content_snapshot TEXT,
  change_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.wiki_versions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_versions' AND policyname = 'Admins can manage versions'
    ) THEN
        CREATE POLICY "Admins can manage versions" ON public.wiki_versions FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;
END
$$;

-- Drop wiki_tags and use public.tags
DROP TABLE IF EXISTS public.wiki_article_tags;
DROP TABLE IF EXISTS public.wiki_tags;

-- Recreate wiki_article_tags linking to public.tags
CREATE TABLE IF NOT EXISTS public.wiki_article_tags (
  article_id UUID REFERENCES public.wiki_articles(id) ON DELETE CASCADE,
  tag_id UUID REFERENCES public.tags(id) ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);

ALTER TABLE public.wiki_article_tags ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_article_tags' AND policyname = 'Public can view article tags'
    ) THEN
        CREATE POLICY "Public can view article tags" ON public.wiki_article_tags FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_article_tags' AND policyname = 'Admins can manage article tags'
    ) THEN
        CREATE POLICY "Admins can manage article tags" ON public.wiki_article_tags FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;
END
$$;

-- Seed some books if empty
INSERT INTO public.library_books (title, author, dynasty, category, status)
SELECT '增删卜易', '野鹤老人', '清', '六爻', '精校版'
WHERE NOT EXISTS (SELECT 1 FROM public.library_books WHERE title = '增删卜易');

INSERT INTO public.library_books (title, author, dynasty, category, status)
SELECT '卜筮正宗', '王洪绪', '清', '六爻', '全本'
WHERE NOT EXISTS (SELECT 1 FROM public.library_books WHERE title = '卜筮正宗');
