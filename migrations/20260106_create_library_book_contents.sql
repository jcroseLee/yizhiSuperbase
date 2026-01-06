CREATE TABLE IF NOT EXISTS public.library_book_contents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES public.library_books(id) ON DELETE CASCADE,
  volume_no INTEGER,
  volume_title TEXT,
  chapter_no INTEGER,
  chapter_title TEXT,
  content TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT library_book_contents_unique_position UNIQUE (book_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_library_book_contents_book_order
ON public.library_book_contents (book_id, sort_order);

ALTER TABLE public.library_book_contents ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'library_book_contents' AND policyname = 'Public can view library book contents'
    ) THEN
        CREATE POLICY "Public can view library book contents" ON public.library_book_contents FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'library_book_contents' AND policyname = 'Admins can manage library book contents'
    ) THEN
        CREATE POLICY "Admins can manage library book contents" ON public.library_book_contents FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;
END
$$;

