-- 创建增加修业值（EXP）的RPC函数
-- 这是一个原子操作，确保并发安全

create or replace function public.increment_exp(
  user_id_param uuid,
  amount_param integer
)
returns void
language plpgsql
security definer
as $$
begin
  -- 原子性地增加用户的EXP
  update public.profiles
  set exp = coalesce(exp, 0) + amount_param
  where id = user_id_param;
end;
$$;

-- 添加函数注释
comment on function public.increment_exp is '原子性地增加用户的修业值（EXP），用于确保并发安全';

