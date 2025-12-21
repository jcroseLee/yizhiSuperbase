-- ============================================
-- 验证反馈系统数据库迁移
-- 用于实现PRD中的"验证反馈"功能
-- ============================================

-- 1. 在comments表中添加验证相关字段
-- ============================================

-- 验证结果：'accurate'（准）, 'inaccurate'（不准）, null（未验证）
alter table public.comments add column if not exists verification_result text;

-- 验证时间
alter table public.comments add column if not exists verified_at timestamptz;

-- 验证人（题主ID）
alter table public.comments add column if not exists verified_by uuid references auth.users(id);

-- 添加约束：verification_result只能是'accurate'或'inaccurate'
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'comments_verification_result_check'
  ) then
    alter table public.comments add constraint comments_verification_result_check 
      check (verification_result is null or verification_result in ('accurate', 'inaccurate'));
  end if;
end $$;

-- 创建索引
create index if not exists idx_comments_verification_result on public.comments(verification_result) 
  where verification_result is not null;
create index if not exists idx_comments_verified_by on public.comments(verified_by) 
  where verified_by is not null;

-- 添加字段注释
comment on column public.comments.verification_result is '验证结果：accurate(准), inaccurate(不准), null(未验证)';
comment on column public.comments.verified_at is '验证时间';
comment on column public.comments.verified_by is '验证人（题主）ID';

-- 2. 创建验证记录表（可选，用于记录验证历史）
-- ============================================
create table if not exists public.verification_logs (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid references public.comments(id) on delete cascade not null,
  post_id uuid references public.posts(id) on delete cascade not null,
  verifier_id uuid references auth.users(id) on delete cascade not null, -- 验证人（题主）
  commenter_id uuid references auth.users(id) on delete cascade not null, -- 被验证的评论者
  verification_result text not null check (verification_result in ('accurate', 'inaccurate')),
  created_at timestamptz default now()
);

alter table public.verification_logs enable row level security;

-- RLS策略：用户可以查看自己相关的验证记录
create policy "verification_logs_select_own"
  on public.verification_logs for select
  using (auth.uid() = verifier_id or auth.uid() = commenter_id);

-- 创建索引
create index if not exists idx_verification_logs_comment_id on public.verification_logs(comment_id);
create index if not exists idx_verification_logs_post_id on public.verification_logs(post_id);
create index if not exists idx_verification_logs_verifier_id on public.verification_logs(verifier_id);
create index if not exists idx_verification_logs_commenter_id on public.verification_logs(commenter_id);
create index if not exists idx_verification_logs_result on public.verification_logs(verification_result);

-- 添加表注释
comment on table public.verification_logs is '验证记录表 - 记录所有验证反馈历史';

-- 3. 创建函数：更新用户声望值（当评论被验证时）
-- ============================================
create or replace function public.update_reputation_on_verification()
returns trigger
language plpgsql
as $$
declare
  commenter_user_id uuid;
  current_reputation integer;
begin
  -- 获取评论者ID
  commenter_user_id := new.user_id;
  
  -- 如果验证结果为"准"，增加声望值
  if new.verification_result = 'accurate' and (old.verification_result is null or old.verification_result != 'accurate') then
    -- 获取当前声望值
    select reputation into current_reputation
    from public.profiles
    where id = commenter_user_id;
    
    -- 增加声望值（+20，根据PRD）
    update public.profiles
    set reputation = coalesce(current_reputation, 0) + 20
    where id = commenter_user_id;
    
    -- 记录验证日志
    insert into public.verification_logs (
      comment_id,
      post_id,
      verifier_id,
      commenter_id,
      verification_result
    ) values (
      new.id,
      new.post_id,
      new.verified_by,
      commenter_user_id,
      'accurate'
    );
  end if;
  
  -- 如果验证结果为"不准"，不扣声望值（根据PRD），但记录日志
  if new.verification_result = 'inaccurate' and (old.verification_result is null or old.verification_result != 'inaccurate') then
    -- 记录验证日志
    insert into public.verification_logs (
      comment_id,
      post_id,
      verifier_id,
      commenter_id,
      verification_result
    ) values (
      new.id,
      new.post_id,
      new.verified_by,
      commenter_user_id,
      'inaccurate'
    );
  end if;
  
  return new;
end;
$$;

comment on function public.update_reputation_on_verification is '当评论被验证时，自动更新评论者的声望值';

-- 创建触发器
drop trigger if exists trigger_update_reputation_on_verification on public.comments;
create trigger trigger_update_reputation_on_verification
  after update of verification_result on public.comments
  for each row
  when (old.verification_result is distinct from new.verification_result)
  execute function public.update_reputation_on_verification();

-- 4. 创建函数：计算用户准确率
-- ============================================
create or replace function public.calculate_user_accuracy(user_id_param uuid)
returns numeric
language plpgsql
stable
as $$
declare
  total_verified integer;
  accurate_count integer;
  accuracy_rate numeric;
begin
  -- 统计该用户所有被验证的评论
  select count(*)
  into total_verified
  from public.comments
  where user_id = user_id_param
    and verification_result is not null;
  
  -- 如果没有验证记录，返回0
  if total_verified = 0 then
    return 0;
  end if;
  
  -- 统计被验证为"准"的数量
  select count(*)
  into accurate_count
  from public.comments
  where user_id = user_id_param
    and verification_result = 'accurate';
  
  -- 计算准确率（百分比）
  accuracy_rate := round((accurate_count::numeric / total_verified::numeric) * 100, 2);
  
  return accuracy_rate;
end;
$$;

comment on function public.calculate_user_accuracy is '计算用户的预测准确率（基于已验证的评论）';

-- 完成迁移
-- ============================================

