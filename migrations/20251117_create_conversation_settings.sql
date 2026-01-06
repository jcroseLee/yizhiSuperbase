-- 用户私信会话设置与会话列表支持（置顶 / 免打扰 / 隐藏 / 未读计算优化）
-- 可重复执行：使用 IF NOT EXISTS / ON CONFLICT 以保证幂等

-- 1) 用户会话设置表
create table if not exists public.conversation_settings (
  user_id uuid not null,
  other_user_id uuid not null,
  is_pinned boolean not null default false,
  is_muted boolean not null default false,
  mute_until timestamptz null,
  is_hidden boolean not null default false,
  last_read_at timestamptz null,
  updated_at timestamptz not null default now(),
  primary key (user_id, other_user_id)
);

comment on table public.conversation_settings is '用户与他人的私信会话设置：置顶、免打扰、隐藏、最后阅读时间等';

alter table public.conversation_settings enable row level security;

-- RLS
drop policy if exists conversation_settings_select on public.conversation_settings;
create policy conversation_settings_select on public.conversation_settings
  for select using (user_id = auth.uid());

drop policy if exists conversation_settings_upsert on public.conversation_settings;
create policy conversation_settings_upsert on public.conversation_settings
  for insert with check (user_id = auth.uid());

drop policy if exists conversation_settings_update on public.conversation_settings;
create policy conversation_settings_update on public.conversation_settings
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 2) 提示索引
create index if not exists idx_conversation_settings_user on public.conversation_settings(user_id, is_pinned desc, updated_at desc);

-- 3) 会话列表 RPC：返回对每个对端用户的最新一条消息、未读数与设置
-- - 仅统计 DM（group_id is null）
-- - 支持隐藏过滤（is_hidden = true 的会话不返回）
-- - 未读数以 messages.is_read=false 统计（与现有前端一致）
create or replace function public.get_dm_conversations(
  uid uuid,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  other_user_id uuid,
  last_message_id uuid,
  last_message_created_at timestamptz,
  last_message_content text,
  last_message_type text,
  unread_count integer,
  is_pinned boolean,
  is_muted boolean,
  mute_until timestamptz,
  is_hidden boolean
)
language sql
security definer
set search_path = public
as $$
  with dm as (
    select
      case 
        when m.sender_id = uid then m.receiver_id
        else m.sender_id
      end as other_id,
      m.id,
      m.created_at,
      m.content,
      null::text as message_type,
      m.sender_id,
      m.receiver_id,
      m.is_read
    from public.messages m
    where m.group_id is null
      and (m.sender_id = uid or m.receiver_id = uid)
  ),
  last_msg as (
    select distinct on (other_id)
      other_id,
      id as last_id,
      created_at as last_created_at,
      content as last_content,
      message_type as last_type
    from dm
    order by other_id, created_at desc
  ),
  unread as (
    select
      other_id,
      count(*)::int as cnt
    from dm
    where receiver_id = uid and is_read = false
    group by other_id
  ),
  settings as (
    select
      cs.other_user_id as other_id,
      cs.is_pinned,
      cs.is_muted,
      cs.mute_until,
      cs.is_hidden
    from public.conversation_settings cs
    where cs.user_id = uid
  ),
  merged as (
    select
      coalesce(l.other_id, s.other_id) as other_user_id,
      l.last_id,
      l.last_created_at,
      l.last_content,
      l.last_type,
      coalesce(u.cnt, 0) as unread_count,
      coalesce(s.is_pinned, false) as is_pinned,
      coalesce(s.is_muted, false) as is_muted,
      s.mute_until,
      coalesce(s.is_hidden, false) as is_hidden
    from last_msg l
    full outer join settings s on s.other_id = l.other_id
    left join unread u on u.other_id = coalesce(l.other_id, s.other_id)
  )
  select
    m.other_user_id,
    m.last_id as last_message_id,
    m.last_created_at as last_message_created_at,
    m.last_content as last_message_content,
    m.last_type as last_message_type,
    m.unread_count,
    m.is_pinned,
    m.is_muted,
    m.mute_until,
    m.is_hidden
  from merged m
  where coalesce(m.is_hidden, false) = false
  -- 注意：在同一层级中，不能以 m. 前缀引用上面 select 的别名列，直接使用别名或使用 CTE 中的原列
  order by m.is_pinned desc, m.last_created_at desc nulls last
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.get_dm_conversations(uuid, integer, integer) to anon, authenticated;

-- 4) 免打扰 / 置顶 / 隐藏 / 最后阅读时间 更新 RPC（幂等）
create or replace function public.set_conversation_setting(
  other_id uuid,
  p_is_pinned boolean default null,
  p_is_muted boolean default null,
  p_mute_until timestamptz default null,
  p_is_hidden boolean default null,
  p_last_read_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.conversation_settings as cs (user_id, other_user_id, is_pinned, is_muted, mute_until, is_hidden, last_read_at, updated_at)
  values (auth.uid(), other_id, coalesce(p_is_pinned, false), coalesce(p_is_muted, false), p_mute_until, coalesce(p_is_hidden, false), p_last_read_at, now())
  on conflict (user_id, other_user_id)
  do update set
    is_pinned   = coalesce(p_is_pinned, cs.is_pinned),
    is_muted    = coalesce(p_is_muted, cs.is_muted),
    mute_until  = coalesce(p_mute_until, cs.mute_until),
    is_hidden   = coalesce(p_is_hidden, cs.is_hidden),
    last_read_at= coalesce(p_last_read_at, cs.last_read_at),
    updated_at  = now();
  return true;
end;
$$;

grant execute on function public.set_conversation_setting(uuid, boolean, boolean, timestamptz, boolean, timestamptz) to anon, authenticated;

-- 5) 可选：创建一个便捷 RPC，用于进入会话时批量标记为已读（同时更新 last_read_at）
create or replace function public.mark_dm_read(other_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 更新消息 is_read（接收方是当前用户，且来自该对端）
  update public.messages
  set is_read = true
  where receiver_id = auth.uid()
    and sender_id = other_id
    and is_read = false
    and group_id is null;

  -- 更新 last_read_at
  perform public.set_conversation_setting(other_id, null, null, null, null, now());
  return true;
end;
$$;

grant execute on function public.mark_dm_read(uuid) to anon, authenticated;


