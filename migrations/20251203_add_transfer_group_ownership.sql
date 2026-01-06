-- 添加群主转让功能
-- 允许群主将群主权限转让给其他成员

create or replace function public.transfer_group_ownership(
  gid uuid,
  new_owner_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_owner_id uuid;
  new_owner_role text;
begin
  -- 获取当前用户 ID
  current_user_id := auth.uid();
  
  if current_user_id is null then
    raise exception '用户未登录';
  end if;
  
  -- 检查群组是否存在
  if not exists (select 1 from public.chat_groups where id = gid) then
    raise exception '群组不存在';
  end if;
  
  -- 获取当前群主 ID（从 chat_groups 表）
  select owner_id into current_owner_id
  from public.chat_groups
  where id = gid;
  
  -- 检查当前用户是否是群主
  if current_owner_id != current_user_id then
    raise exception '只有群主可以转让群主权限';
  end if;
  
  -- 检查新群主是否是群成员
  select role into new_owner_role
  from public.chat_group_members
  where group_id = gid and user_id = new_owner_id;
  
  if new_owner_role is null then
    raise exception '目标用户不是该群的成员';
  end if;
  
  -- 不能转让给自己
  if new_owner_id = current_user_id then
    raise exception '不能将群主权限转让给自己';
  end if;
  
  -- 更新 chat_groups 表的 owner_id
  update public.chat_groups
  set owner_id = new_owner_id,
      updated_at = now()
  where id = gid;
  
  -- 更新 chat_group_members 表：原群主变为普通成员，新群主变为 owner
  -- 原群主
  update public.chat_group_members
  set role = 'member'
  where group_id = gid and user_id = current_user_id;
  
  -- 新群主
  update public.chat_group_members
  set role = 'owner'
  where group_id = gid and user_id = new_owner_id;
  
  -- 如果新群主不在成员表中（理论上不应该发生），则插入
  if not found then
    insert into public.chat_group_members (group_id, user_id, role)
    values (gid, new_owner_id, 'owner')
    on conflict (group_id, user_id) do update set role = 'owner';
  end if;
  
  return true;
end;
$$;

grant execute on function public.transfer_group_ownership(uuid, uuid) to anon, authenticated;

comment on function public.transfer_group_ownership(uuid, uuid) is '转让群主权限。只有当前群主可以执行此操作。会将 chat_groups.owner_id 和 chat_group_members.role 都更新。';

