create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists public.chat_group_members (
  group_id uuid not null,
  user_id uuid not null,
  role text not null check (role in ('owner','admin','member')),
  joined_at timestamp with time zone default now(),
  primary key (group_id, user_id)
);

alter table public.messages add column if not exists group_id uuid;

create index if not exists idx_messages_group_id on public.messages(group_id);
create index if not exists idx_messages_group_id_created_at on public.messages(group_id, created_at);

create table if not exists public.message_reads (
  message_id uuid not null,
  user_id uuid not null,
  read_at timestamp with time zone default now(),
  primary key (message_id, user_id)
);

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.message_reads enable row level security;

drop policy if exists chat_groups_select on public.chat_groups;
create policy chat_groups_select on public.chat_groups
  for select using (
    owner_id = auth.uid() or exists (
      select 1 from public.chat_group_members m where m.group_id = chat_groups.id and m.user_id = auth.uid()
    )
  );

drop policy if exists chat_groups_insert on public.chat_groups;
create policy chat_groups_insert on public.chat_groups
  for insert with check (owner_id = auth.uid());

drop policy if exists chat_group_members_select on public.chat_group_members;
create policy chat_group_members_select on public.chat_group_members
  for select using (user_id = auth.uid());

drop policy if exists chat_group_members_insert on public.chat_group_members;
-- 允许用户添加自己为成员（用于创建群组时添加自己）
-- 添加其他成员应该通过 RPC 函数 add_group_members
create policy chat_group_members_insert on public.chat_group_members
  for insert with check (user_id = auth.uid());

drop policy if exists chat_group_members_delete on public.chat_group_members;
-- 允许用户删除自己的成员记录（退出群聊）
create policy chat_group_members_delete on public.chat_group_members
  for delete using (user_id = auth.uid());

drop policy if exists chat_groups_update on public.chat_groups;
create policy chat_groups_update on public.chat_groups
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists message_reads_select on public.message_reads;
create policy message_reads_select on public.message_reads
  for select using (user_id = auth.uid());

drop policy if exists message_reads_insert on public.message_reads;
create policy message_reads_insert on public.message_reads
  for insert with check (user_id = auth.uid());

drop policy if exists messages_group_select on public.messages;
create policy messages_group_select on public.messages
  for select using (
    group_id is not null and exists (
      select 1 from public.chat_group_members m where m.group_id = messages.group_id and m.user_id = auth.uid()
    )
  );

drop policy if exists messages_group_insert on public.messages;
create policy messages_group_insert on public.messages
  for insert with check (
    group_id is not null and sender_id = auth.uid() and exists (
      select 1 from public.chat_group_members m where m.group_id = messages.group_id and m.user_id = auth.uid()
    )
  );

-- RPC: get_unread_group_count(uid)
create or replace function public.get_unread_group_count(uid uuid)
returns integer
language sql
security definer
as $$
  select count(*)::int
  from public.messages m
  join public.chat_group_members gm on gm.group_id = m.group_id and gm.user_id = uid
  where m.group_id is not null
    and m.sender_id <> uid
    and not exists (
      select 1 from public.message_reads r where r.message_id = m.id and r.user_id = uid
    );
$$;

grant execute on function public.get_unread_group_count(uuid) to anon, authenticated;

-- RPC: get_group_members(gid, uid)
create or replace function public.get_group_members(gid uuid, uid uuid)
returns table(user_id uuid, role text, nickname text, avatar_url text)
language sql
security definer
as $$
  select m.user_id, m.role, p.nickname, p.avatar_url
  from public.chat_group_members m
  join public.profiles p on p.id = m.user_id
  where m.group_id = gid
    and exists (
      select 1 from public.chat_group_members gm where gm.group_id = gid and gm.user_id = uid
    );
$$;

grant execute on function public.get_group_members(uuid, uuid) to anon, authenticated;

-- RPC: get_unread_group_count_by_group(uid)
create or replace function public.get_unread_group_count_by_group(uid uuid)
returns table(group_id uuid, count integer)
language sql
security definer
as $$
  select m.group_id, count(*)::int as count
  from public.messages m
  join public.chat_group_members gm on gm.group_id = m.group_id and gm.user_id = uid
  where m.group_id is not null
    and m.sender_id <> uid
    and not exists (
      select 1 from public.message_reads r where r.message_id = m.id and r.user_id = uid
    )
  group by m.group_id;
$$;

grant execute on function public.get_unread_group_count_by_group(uuid) to anon, authenticated;

-- RPC: leave_group(gid, uid)
-- 允许用户退出群聊（删除自己的成员记录）
create or replace function public.leave_group(gid uuid, uid uuid)
returns boolean
language plpgsql
security definer
as $$
begin
  -- 检查用户是否是群成员
  if not exists (
    select 1 from public.chat_group_members
    where group_id = gid and user_id = uid
  ) then
    raise exception '用户不是该群的成员';
  end if;
  
  -- 删除成员的成员记录
  delete from public.chat_group_members
  where group_id = gid and user_id = uid;
  
  return true;
end;
$$;

grant execute on function public.leave_group(uuid, uuid) to anon, authenticated;

-- RPC: add_group_members(gid, uids)
-- 允许群主或管理员添加成员（使用 security definer 绕过 RLS）
create or replace function public.add_group_members(gid uuid, uids uuid[])
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_role text;
  uid uuid;
begin
  -- 检查当前用户是否是群主或管理员（使用 security definer，绕过 RLS）
  select role into current_user_role
  from public.chat_group_members
  where group_id = gid and user_id = auth.uid();
  
  if current_user_role is null then
    raise exception '用户不是该群的成员';
  end if;
  
  if current_user_role not in ('owner', 'admin') then
    raise exception '只有群主或管理员可以添加成员';
  end if;
  
  -- 添加成员（忽略已存在的成员）
  foreach uid in array uids
  loop
    insert into public.chat_group_members (group_id, user_id, role)
    values (gid, uid, 'member')
    on conflict (group_id, user_id) do nothing;
  end loop;
  
  return true;
end;
$$;

grant execute on function public.add_group_members(uuid, uuid[]) to anon, authenticated;