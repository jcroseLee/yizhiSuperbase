create or replace function public.search_cases(
  p_q text default null,
  p_gua_name text default null,
  p_accuracy text default null,
  p_tag_ids uuid[] default null,
  p_divination_method integer default null,
  p_is_liu_chong boolean default null,
  p_is_liu_he boolean default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_order text default 'featured'
)
returns table (
  post_id uuid,
  title text,
  content text,
  content_html text,
  view_count integer,
  like_count integer,
  comment_count integer,
  created_at timestamptz,
  user_id uuid,
  author_nickname text,
  author_avatar_url text,
  author_exp integer,
  author_title_level integer,
  feedback_content text,
  accuracy_rating text,
  occurred_at timestamptz,
  gua_original_code varchar,
  gua_changed_code varchar,
  gua_original_name varchar,
  gua_changed_name varchar,
  divination_method integer,
  is_liu_chong boolean,
  is_liu_he boolean,
  yong_shen varchar,
  original_key text,
  changed_key text,
  changing_flags jsonb,
  tags jsonb,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
with filtered as (
  select
    p.id as post_id,
    p.title,
    p.content,
    p.content_html,
    p.view_count,
    p.like_count,
    p.comment_count,
    p.created_at,
    p.user_id,
    pr.nickname as author_nickname,
    pr.avatar_url as author_avatar_url,
    pr.exp as author_exp,
    pr.title_level as author_title_level,
    cm.feedback_content,
    cm.accuracy_rating,
    cm.occurred_at,
    cm.gua_original_code,
    cm.gua_changed_code,
    cm.gua_original_name,
    cm.gua_changed_name,
    cm.divination_method,
    cm.is_liu_chong,
    cm.is_liu_he,
    cm.yong_shen,
    dr.original_key,
    dr.changed_key,
    to_jsonb(dr.changing_flags) as changing_flags
  from public.case_metadata cm
  join public.posts p on p.id = cm.post_id
  left join public.profiles pr on pr.id = p.user_id
  left join public.divination_records dr on dr.id = p.divination_record_id
  where
    (p_q is null or btrim(p_q) = '' or (
      p.title ilike ('%' || btrim(p_q) || '%')
      or p.content ilike ('%' || btrim(p_q) || '%')
      or coalesce(p.content_html, '') ilike ('%' || btrim(p_q) || '%')
      or cm.feedback_content ilike ('%' || btrim(p_q) || '%')
    ))
    and (p_gua_name is null or btrim(p_gua_name) = '' or cm.gua_original_name ilike ('%' || btrim(p_gua_name) || '%'))
    and (p_accuracy is null or btrim(p_accuracy) = '' or cm.accuracy_rating = btrim(p_accuracy))
    and (p_divination_method is null or cm.divination_method = p_divination_method)
    and (p_is_liu_chong is null or cm.is_liu_chong = p_is_liu_chong)
    and (p_is_liu_he is null or cm.is_liu_he = p_is_liu_he)
    and (
      p_tag_ids is null
      or array_length(p_tag_ids, 1) is null
      or not exists (
        select 1
        from unnest(p_tag_ids) as tid
        where not exists (
          select 1
          from public.post_tags pt
          where pt.post_id = p.id and pt.tag_id = tid
        )
      )
    )
)
select
  f.*,
  (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'name', t.name,
          'category', t.category,
          'scope', t.scope
        )
        order by t.usage_count desc, t.name asc
      ),
      '[]'::jsonb
    )
    from public.post_tags pt
    join public.tags t on t.id = pt.tag_id
    where pt.post_id = f.post_id
  ) as tags,
  count(*) over() as total_count
from filtered f
order by
  case when p_order = 'latest' then f.created_at end desc nulls last,
  case when p_order = 'hot' then f.view_count end desc nulls last,
  case when p_order = 'featured' then f.like_count end desc nulls last,
  f.created_at desc
limit greatest(p_limit, 1)
offset greatest(p_offset, 0);
$$;
