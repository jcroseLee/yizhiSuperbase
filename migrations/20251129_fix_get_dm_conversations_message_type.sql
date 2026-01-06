-- Fix get_dm_conversations function to properly read message_type from messages table
-- Issue: The function was using null::text instead of reading from m.message_type
-- This was causing the function to always return null for message_type, and potentially
-- causing 502 errors if the function had issues processing the data

-- First, ensure message_type column exists (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'messages' 
    AND column_name = 'message_type'
  ) THEN
    ALTER TABLE public.messages 
    ADD COLUMN message_type text DEFAULT 'chat' CHECK (message_type IN ('chat', 'system'));
  END IF;
END $$;

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
stable
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
      coalesce(m.message_type, 'chat')::text as message_type,
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
  order by m.is_pinned desc, m.last_created_at desc nulls last
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.get_dm_conversations(uuid, integer, integer) to anon, authenticated;

comment on function public.get_dm_conversations(uuid, integer, integer) is '获取用户的私信会话列表，包含最后一条消息、未读数和会话设置（置顶、免打扰等）';

