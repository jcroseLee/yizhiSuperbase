-- 确保聊天记录永久保存（除非用户手动删除）
-- 修改 messages 表的外键约束，从 CASCADE 改为 SET NULL，这样即使用户被删除，消息也会保留

-- 1. 删除现有的外键约束（尝试常见的约束名称）
alter table public.messages
  drop constraint if exists messages_sender_id_fkey;

alter table public.messages
  drop constraint if exists messages_receiver_id_fkey;

-- 如果约束名称不同，通过系统表查找并删除
do $$
declare
  constraint_name text;
begin
  -- 查找 sender_id 的外键约束
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'public.messages'::regclass
    and contype = 'f'
    and confrelid = 'auth.users'::regclass
    and array_length(conkey, 1) = 1
    and (select attname from pg_attribute where attrelid = 'public.messages'::regclass and attnum = conkey[1]) = 'sender_id';
  
  if constraint_name is not null then
    execute format('alter table public.messages drop constraint if exists %I', constraint_name);
  end if;
  
  -- 查找 receiver_id 的外键约束
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'public.messages'::regclass
    and contype = 'f'
    and confrelid = 'auth.users'::regclass
    and array_length(conkey, 1) = 1
    and (select attname from pg_attribute where attrelid = 'public.messages'::regclass and attnum = conkey[1]) = 'receiver_id';
  
  if constraint_name is not null then
    execute format('alter table public.messages drop constraint if exists %I', constraint_name);
  end if;
end $$;

-- 2. 确保 sender_id 和 receiver_id 可以为 NULL（如果还没有的话）
alter table public.messages
  alter column sender_id drop not null;

alter table public.messages
  alter column receiver_id drop not null;

-- 3. 重新创建外键约束，使用 SET NULL 而不是 CASCADE
alter table public.messages
  add constraint messages_sender_id_fkey
  foreign key (sender_id) references auth.users(id) on delete set null;

alter table public.messages
  add constraint messages_receiver_id_fkey
  foreign key (receiver_id) references auth.users(id) on delete set null;

-- 4. 添加 DELETE 策略，只允许用户删除自己发送的消息（手动删除）
drop policy if exists messages_delete_own on public.messages;
create policy messages_delete_own on public.messages
  for delete using (auth.uid() = sender_id);

-- 5. 确保没有自动清理消息的触发器或函数
-- 检查并删除任何可能自动删除消息的触发器
do $$
declare
  trigger_record record;
begin
  for trigger_record in
    select trigger_name, event_manipulation, event_object_table
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table = 'messages'
      and (trigger_name like '%delete%' or trigger_name like '%cleanup%' or trigger_name like '%retention%')
  loop
    execute format('drop trigger if exists %I on public.messages', trigger_record.trigger_name);
  end loop;
end $$;

-- 6. 确保群聊消息的 group_id 外键也不会级联删除消息
-- 检查并修改 group_id 的外键约束（如果存在）
do $$
declare
  constraint_name text;
begin
  -- 查找 group_id 的外键约束
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'public.messages'::regclass
    and contype = 'f'
    and confrelid = 'public.chat_groups'::regclass
    and array_length(conkey, 1) = 1
    and (select attname from pg_attribute where attrelid = 'public.messages'::regclass and attnum = conkey[1]) = 'group_id';
  
  if constraint_name is not null then
    -- 删除现有的外键约束
    execute format('alter table public.messages drop constraint if exists %I', constraint_name);
    -- 重新创建，使用 SET NULL 而不是 CASCADE
    alter table public.messages
      add constraint messages_group_id_fkey
      foreign key (group_id) references public.chat_groups(id) on delete set null;
  end if;
end $$;

-- 7. 添加注释说明消息永久保存策略
comment on table public.messages is '聊天消息表，消息永久保存，除非用户手动删除。即使用户账户被删除或群组被删除，消息也会保留（sender_id/receiver_id/group_id 会变为 NULL）。';

