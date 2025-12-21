-- RPC: get_user_profiles(uids)
-- 获取多个用户的 profiles 信息（用于联系人列表）
-- 使用 security definer 绕过 RLS 限制
create or replace function public.get_user_profiles(uids uuid[])
returns table(id uuid, nickname text, avatar_url text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.nickname, p.avatar_url
  from public.profiles p
  where p.id = any(uids);
$$;

grant execute on function public.get_user_profiles(uuid[]) to anon, authenticated;

