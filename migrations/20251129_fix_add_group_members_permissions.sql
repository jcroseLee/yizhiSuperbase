-- Fix and improve add_group_members RPC function
-- Issues:
-- 1. Better error handling and debugging
-- 2. Allow group owner to add members even if there's a slight delay in recognizing ownership
-- 3. Better error messages for debugging

create or replace function public.add_group_members(gid uuid, uids uuid[])
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_role text;
  current_user_id uuid;
  uid uuid;
  group_exists boolean;
begin
  -- Get current user ID
  current_user_id := auth.uid();
  
  if current_user_id is null then
    raise exception '用户未登录';
  end if;
  
  -- Check if group exists
  select exists(select 1 from public.chat_groups where id = gid) into group_exists;
  
  if not group_exists then
    raise exception '群组不存在';
  end if;
  
  -- Check if user is the group owner (by checking chat_groups table directly)
  -- This is more reliable than checking chat_group_members in case of timing issues
  -- This allows the group creator to add members immediately after creating the group
  select exists(
    select 1 from public.chat_groups 
    where id = gid and owner_id = current_user_id
  ) into group_exists;
  
  if group_exists then
    -- User is the group owner, allow adding members
    current_user_role := 'owner';
    
    -- Ensure owner is also in chat_group_members table (in case it wasn't added yet)
    -- This is idempotent - if already exists, ON CONFLICT will do nothing
    insert into public.chat_group_members (group_id, user_id, role)
    values (gid, current_user_id, 'owner')
    on conflict (group_id, user_id) do update set role = 'owner';
  else
    -- Check if current user is an admin or owner in chat_group_members
    select role into current_user_role
    from public.chat_group_members
    where group_id = gid and user_id = current_user_id;
    
    if current_user_role is null then
      raise exception '用户不是该群的成员。用户ID: %, 群组ID: %', current_user_id, gid;
    end if;
  end if;
  
  if current_user_role not in ('owner', 'admin') then
    raise exception '只有群主或管理员可以添加成员。当前用户角色: %, 用户ID: %, 群组ID: %', 
      coalesce(current_user_role, 'unknown'), current_user_id, gid;
  end if;
  
  -- Validate that uids array is not empty
  if uids is null or array_length(uids, 1) is null then
    raise exception '成员列表不能为空';
  end if;
  
  -- Add members (ignore already existing members)
  foreach uid in array uids
  loop
    -- Skip if trying to add self (owner is already a member)
    if uid = current_user_id then
      continue;
    end if;
    
    -- Insert member (ignore conflicts)
    insert into public.chat_group_members (group_id, user_id, role)
    values (gid, uid, 'member')
    on conflict (group_id, user_id) do nothing;
  end loop;
  
  return true;
end;
$$;

grant execute on function public.add_group_members(uuid, uuid[]) to anon, authenticated;

comment on function public.add_group_members(uuid, uuid[]) is '添加群组成员。只有群主或管理员可以添加成员。允许群主（根据chat_groups.owner_id）直接添加成员，即使chat_group_members表中还没有记录。';

