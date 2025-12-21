-- 完善删除会话功能
-- 1. 添加触发器：新消息自动唤醒隐藏的会话
-- 2. 完善 leave_group 函数：禁止群主退出

-- ============================================
-- 1. 新消息唤醒隐藏会话的触发器
-- ============================================
-- 当有新私信消息时，自动取消接收者的隐藏状态
-- 这样即使会话被隐藏，收到新消息后也会自动显示

create or replace function public.handle_new_message_unhide_conversation()
returns trigger as $$
begin
  -- 仅针对私信 (group_id is null)
  if new.group_id is null and new.receiver_id is not null then
    -- 更新接收者的设置，将 is_hidden 设为 false
    -- 这样新消息会自动"唤醒"被隐藏的会话
    insert into public.conversation_settings (user_id, other_user_id, is_hidden, updated_at)
    values (new.receiver_id, new.sender_id, false, now())
    on conflict (user_id, other_user_id)
    do update set 
      is_hidden = false,
      updated_at = now();
      
    -- 同时更新发送者的 updated_at，确保会话排到最前
    -- 这样发送方也能看到会话更新
    insert into public.conversation_settings (user_id, other_user_id, is_hidden, updated_at)
    values (new.sender_id, new.receiver_id, false, now())
    on conflict (user_id, other_user_id)
    do update set updated_at = now();
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- 创建触发器（如果不存在）
drop trigger if exists on_new_message_unhide on public.messages;
create trigger on_new_message_unhide
  after insert on public.messages
  for each row
  execute function public.handle_new_message_unhide_conversation();

comment on function public.handle_new_message_unhide_conversation() is '当有新私信消息时，自动取消接收者的隐藏状态，确保新消息能唤醒被隐藏的会话';

-- ============================================
-- 2. 完善 leave_group 函数：禁止群主退出
-- ============================================
-- 防止群主退出导致群组无主，必须先转让群主权限

create or replace function public.leave_group(gid uuid, uid uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_is_owner_by_table boolean;
begin
  -- 检查用户是否是群成员
  if not exists (
    select 1 from public.chat_group_members
    where group_id = gid and user_id = uid
  ) then
    raise exception '用户不是该群的成员';
  end if;
  
  -- 获取用户在群组中的角色
  select role into v_role
  from public.chat_group_members
  where group_id = gid and user_id = uid;
  
  -- 双重检查：也检查 chat_groups 表中的 owner_id
  -- 这可以防止时序问题（如果成员表还没更新但群组表已更新）
  select exists(
    select 1 from public.chat_groups 
    where id = gid and owner_id = uid
  ) into v_is_owner_by_table;
  
  -- 如果用户是群主，禁止退出
  if v_role = 'owner' or v_is_owner_by_table then
    raise exception '群主不能退出群聊。请先转让群主权限，或解散群聊。';
  end if;
  
  -- 删除成员的成员记录
  delete from public.chat_group_members
  where group_id = gid and user_id = uid;
  
  -- 检查删除是否成功
  if not found then
    raise exception '退出群聊失败';
  end if;
  
  return true;
end;
$$;

-- 更新函数注释
comment on function public.leave_group(uuid, uuid) is '退出群聊。群主不能退出，必须先转让群主权限。普通成员和管理员可以退出。';

