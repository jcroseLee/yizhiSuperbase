-- Create remove_group_member RPC function
-- Allows group owner or admin to remove members (bypasses RLS)
-- Similar to add_group_members, but for removing members

create or replace function public.remove_group_member(gid uuid, uid_to_remove uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_role text;
  current_user_id uuid;
  member_to_remove_role text;
  group_exists boolean;
  is_owner_by_table boolean;
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
  
  -- Check if trying to remove self (should use leave_group instead)
  if uid_to_remove = current_user_id then
    raise exception '不能移除自己，请使用退出群聊功能';
  end if;
  
  -- Check if user is the group owner (by checking chat_groups table directly)
  -- This is more reliable than checking chat_group_members in case of timing issues
  select exists(
    select 1 from public.chat_groups 
    where id = gid and owner_id = current_user_id
  ) into is_owner_by_table;
  
  if is_owner_by_table then
    -- User is the group owner, allow removing members
    current_user_role := 'owner';
    
    -- Ensure owner is also in chat_group_members table (in case it wasn't added yet)
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
  
  -- Only owner or admin can remove members
  if current_user_role not in ('owner', 'admin') then
    raise exception '只有群主或管理员可以移除成员。当前用户角色: %, 用户ID: %, 群组ID: %', 
      coalesce(current_user_role, 'unknown'), current_user_id, gid;
  end if;
  
  -- Get the role of the member to be removed
  select role into member_to_remove_role
  from public.chat_group_members
  where group_id = gid and user_id = uid_to_remove;
  
  if member_to_remove_role is null then
    raise exception '要移除的用户不是该群的成员。用户ID: %, 群组ID: %', uid_to_remove, gid;
  end if;
  
  -- Cannot remove group owner
  if member_to_remove_role = 'owner' then
    raise exception '不能移除群主';
  end if;
  
  -- Admin cannot remove other admins (only owner can)
  if current_user_role = 'admin' and member_to_remove_role = 'admin' then
    raise exception '管理员不能移除其他管理员';
  end if;
  
  -- Remove the member (using security definer to bypass RLS)
  delete from public.chat_group_members
  where group_id = gid and user_id = uid_to_remove;
  
  -- Check if deletion was successful
  if not found then
    raise exception '移除成员失败';
  end if;
  
  return true;
end;
$$;

grant execute on function public.remove_group_member(uuid, uuid) to anon, authenticated;

comment on function public.remove_group_member(uuid, uuid) is '移除群组成员。只有群主或管理员可以移除成员。群主可以移除任何成员（包括管理员），管理员只能移除普通成员。不能移除群主。';

