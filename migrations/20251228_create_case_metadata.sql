create extension if not exists vector;

create table if not exists public.case_metadata (
  post_id uuid primary key references public.posts(id) on delete cascade,
  feedback_content text not null,
  accuracy_rating text check (accuracy_rating in ('accurate', 'inaccurate', 'partial')),
  occurred_at timestamptz,
  gua_original_code varchar(6),
  gua_changed_code varchar(6),
  gua_original_name varchar(20),
  gua_changed_name varchar(20),
  divination_method integer,
  is_liu_chong boolean not null default false,
  is_liu_he boolean not null default false,
  yong_shen varchar(20),
  embedding vector(1536),
  archived_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_case_metadata_gua_original_code on public.case_metadata(gua_original_code);
create index if not exists idx_case_metadata_accuracy_rating on public.case_metadata(accuracy_rating);
create index if not exists idx_case_metadata_archived_at on public.case_metadata(archived_at desc);

alter table public.case_metadata enable row level security;

create policy "Case metadata is readable"
  on public.case_metadata for select
  using (true);

create policy "Authors and admins can insert case metadata"
  on public.case_metadata for insert
  with check (
    exists (
      select 1
      from public.posts p
      where p.id = post_id
        and p.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.profiles pr
      where pr.id = auth.uid()
        and pr.role = 'admin'
    )
  );

create policy "Authors and admins can update case metadata"
  on public.case_metadata for update
  using (
    exists (
      select 1
      from public.posts p
      where p.id = post_id
        and p.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.profiles pr
      where pr.id = auth.uid()
        and pr.role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from public.posts p
      where p.id = post_id
        and p.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.profiles pr
      where pr.id = auth.uid()
        and pr.role = 'admin'
    )
  );

create policy "Authors and admins can delete case metadata"
  on public.case_metadata for delete
  using (
    exists (
      select 1
      from public.posts p
      where p.id = post_id
        and p.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.profiles pr
      where pr.id = auth.uid()
        and pr.role = 'admin'
    )
  );

create or replace function public.handle_case_metadata_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_case_metadata_updated_at on public.case_metadata;
create trigger set_case_metadata_updated_at
  before update on public.case_metadata
  for each row
  execute function public.handle_case_metadata_updated_at();

create or replace function public.search_cases(
  p_q text default null,
  p_gua_name text default null,
  p_accuracy text default null,
  p_tag_ids uuid[] default null,
  p_divination_method integer default null,
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
