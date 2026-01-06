
-- Ensure tags exist
INSERT INTO public.tags (name, category, scope)
SELECT s.name, s.category, s.scope
FROM (
  VALUES
    -- Subject tags (Common)
    ('事业', 'subject', NULL::public.divination_method_type),
    ('财运', 'subject', NULL::public.divination_method_type),
    ('感情', 'subject', NULL::public.divination_method_type),
    ('婚姻', 'subject', NULL::public.divination_method_type),
    ('健康', 'subject', NULL::public.divination_method_type),
    ('学业', 'subject', NULL::public.divination_method_type),
    ('官非', 'subject', NULL::public.divination_method_type),
    ('寻人', 'subject', NULL::public.divination_method_type),
    ('寻物', 'subject', NULL::public.divination_method_type),
    ('择日', 'subject', NULL::public.divination_method_type),
    ('流年', 'subject', NULL::public.divination_method_type),
    ('其它', 'subject', NULL::public.divination_method_type),
    
    -- Technique tags (Liuyao)
    ('六冲', 'technique', 'liuyao'::public.divination_method_type),
    ('六合', 'technique', 'liuyao'::public.divination_method_type),
    ('伏吟', 'technique', 'liuyao'::public.divination_method_type),
    ('反吟', 'technique', 'liuyao'::public.divination_method_type),
    ('飞伏', 'technique', 'liuyao'::public.divination_method_type),
    ('进神', 'technique', 'liuyao'::public.divination_method_type),
    ('退神', 'technique', 'liuyao'::public.divination_method_type),
    ('空亡', 'technique', 'liuyao'::public.divination_method_type),
    ('月破', 'technique', 'liuyao'::public.divination_method_type),
    ('暗动', 'technique', 'liuyao'::public.divination_method_type),
    ('三合', 'technique', 'liuyao'::public.divination_method_type),
    
    -- Technique tags (Bazi)
    ('身旺', 'technique', 'bazi'::public.divination_method_type),
    ('身弱', 'technique', 'bazi'::public.divination_method_type),
    ('伤官见官', 'technique', 'bazi'::public.divination_method_type),
    ('食神制杀', 'technique', 'bazi'::public.divination_method_type),
    ('大运', 'technique', 'bazi'::public.divination_method_type),
    ('流年', 'technique', 'bazi'::public.divination_method_type),
    
    -- Technique tags (Qimen)
    ('伏吟局', 'technique', 'qimen'::public.divination_method_type),
    ('反吟局', 'technique', 'qimen'::public.divination_method_type),
    ('五不遇时', 'technique', 'qimen'::public.divination_method_type),
    ('击刑', 'technique', 'qimen'::public.divination_method_type),
    ('入墓', 'technique', 'qimen'::public.divination_method_type),
    
    -- Technique tags (Meihua)
    ('体用', 'technique', 'meihua'::public.divination_method_type),
    ('互卦', 'technique', 'meihua'::public.divination_method_type),
    ('变卦', 'technique', 'meihua'::public.divination_method_type),
    ('外应', 'technique', 'meihua'::public.divination_method_type)
) AS s(name, category, scope)
WHERE NOT EXISTS (
  SELECT 1 FROM public.tags t
  WHERE t.name = s.name AND t.category = s.category AND t.scope IS NOT DISTINCT FROM s.scope
);
