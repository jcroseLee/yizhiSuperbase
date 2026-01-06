-- Create wiki_categories table
CREATE TABLE IF NOT EXISTS wiki_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  parent_id UUID REFERENCES wiki_categories(id) ON DELETE CASCADE,
  type TEXT CHECK (type IN ('foundation', 'school', 'scenario', 'other')) NOT NULL DEFAULT 'other',
  description TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create wiki_articles table
CREATE TABLE IF NOT EXISTS wiki_articles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES wiki_categories(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  content TEXT, -- Markdown content
  sort_order INTEGER DEFAULT 0,
  is_published BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create wiki_tags table (for Scenarios/Layer 3)
CREATE TABLE IF NOT EXISTS wiki_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create wiki_article_tags junction table
CREATE TABLE IF NOT EXISTS wiki_article_tags (
  article_id UUID REFERENCES wiki_articles(id) ON DELETE CASCADE,
  tag_id UUID REFERENCES wiki_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);

-- Enable RLS
ALTER TABLE wiki_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE wiki_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE wiki_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE wiki_article_tags ENABLE ROW LEVEL SECURITY;

-- Policies

-- Public Read Policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_categories' AND policyname = 'Public can view categories'
    ) THEN
        CREATE POLICY "Public can view categories" ON wiki_categories FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_articles' AND policyname = 'Public can view published articles'
    ) THEN
        CREATE POLICY "Public can view published articles" ON wiki_articles FOR SELECT USING (is_published = true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_tags' AND policyname = 'Public can view tags'
    ) THEN
        CREATE POLICY "Public can view tags" ON wiki_tags FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_article_tags' AND policyname = 'Public can view article tags'
    ) THEN
        CREATE POLICY "Public can view article tags" ON wiki_article_tags FOR SELECT USING (true);
    END IF;
END
$$;

-- Admin All Policies
DO $$
BEGIN
    -- Wiki Categories Admin
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_categories' AND policyname = 'Admins can manage categories'
    ) THEN
        CREATE POLICY "Admins can manage categories" ON wiki_categories FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;

    -- Wiki Articles Admin
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_articles' AND policyname = 'Admins can manage articles'
    ) THEN
        CREATE POLICY "Admins can manage articles" ON wiki_articles FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;

    -- Wiki Tags Admin
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_tags' AND policyname = 'Admins can manage tags'
    ) THEN
        CREATE POLICY "Admins can manage tags" ON wiki_tags FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;

    -- Wiki Article Tags Admin
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'wiki_article_tags' AND policyname = 'Admins can manage article tags'
    ) THEN
        CREATE POLICY "Admins can manage article tags" ON wiki_article_tags FOR ALL USING (
            exists (
              select 1 from public.profiles
              where profiles.id = auth.uid()
              and profiles.role = 'admin'
            )
        );
    END IF;
END
$$;

-- Initial Data Seeding

-- 1. Layer 1: Foundation (易学基石)
INSERT INTO wiki_categories (name, slug, type, sort_order) VALUES 
('易学通识', 'foundation-core', 'foundation', 10)
ON CONFLICT (slug) DO NOTHING;

DO $$
DECLARE
    foundation_id UUID;
BEGIN
    SELECT id INTO foundation_id FROM wiki_categories WHERE slug = 'foundation-core';

    INSERT INTO wiki_categories (name, slug, parent_id, type, sort_order) VALUES 
    ('阴阳五行', 'yin-yang-wu-xing', foundation_id, 'foundation', 1),
    ('天干地支', 'tian-gan-di-zhi', foundation_id, 'foundation', 2),
    ('河图洛书与八卦', 'he-tu-luo-shu-ba-gua', foundation_id, 'foundation', 3),
    ('历法基础', 'li-fa-ji-chu', foundation_id, 'foundation', 4)
    ON CONFLICT (slug) DO NOTHING;
END $$;

-- 2. Layer 2: Schools (分门别类)
INSERT INTO wiki_categories (name, slug, type, sort_order) VALUES 
('六爻预测', 'liuyao-school', 'school', 20),
('奇门遁甲', 'qimen-school', 'school', 30),
('四柱八字', 'bazi-school', 'school', 40),
('梅花易数', 'meihua-school', 'school', 50)
ON CONFLICT (slug) DO NOTHING;

-- Subcategories for Schools (Example for Liu Yao)
DO $$
DECLARE
    liuyao_id UUID;
BEGIN
    SELECT id INTO liuyao_id FROM wiki_categories WHERE slug = 'liuyao-school';

    INSERT INTO wiki_categories (name, slug, parent_id, type, sort_order) VALUES 
    ('装卦体系', 'liuyao-zhuang-gua', liuyao_id, 'school', 1),
    ('六亲通辩', 'liuyao-liu-qin', liuyao_id, 'school', 2),
    ('进阶技法', 'liuyao-jin-jie', liuyao_id, 'school', 3)
    ON CONFLICT (slug) DO NOTHING;
END $$;

-- 3. Layer 3: Scenarios (Tags)
INSERT INTO wiki_tags (name, slug) VALUES 
('求财', 'wealth'),
('功名', 'career'),
('感情', 'relationship'),
('健康', 'health'),
('出行', 'travel')
ON CONFLICT (slug) DO NOTHING;
