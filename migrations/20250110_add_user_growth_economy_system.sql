-- ============================================
-- 易知 (Yi-Zhi) 用户成长与经济体系数据库迁移
-- PRD v1.0 - 数据库扩展
-- ============================================

-- 1. 扩展 profiles 表：添加用户成长与经济体系字段
-- ============================================

-- 修业值 (EXP) - 衡量用户活跃度
alter table public.profiles add column if not exists exp integer default 0;

-- 声望值 (Reputation) - 衡量用户专业水平（如果已存在则跳过）
-- 注意：如果之前的迁移已经添加了reputation字段，这里会跳过
alter table public.profiles add column if not exists reputation integer default 0;

-- 易币余额 (Yi Coins) - 平台内工具型代币
alter table public.profiles add column if not exists yi_coins integer default 0;

-- 现金余额 (Cash Balance) - 可提现的现金（单位：元）
alter table public.profiles add column if not exists cash_balance decimal(10,2) default 0.00;

-- 称号等级 (Title Level) - 1:白身, 2:学人, 3:术士, 4:方家, 5:先生, 6:国手
alter table public.profiles add column if not exists title_level integer default 1;

-- 最后签到日期 - 用于判断连续签到
alter table public.profiles add column if not exists last_checkin_date date;

-- 连续签到天数 - 用于计算连续签到奖励
alter table public.profiles add column if not exists consecutive_checkin_days integer default 0;

-- 添加约束：title_level 范围检查
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'profiles_title_level_check'
  ) then
    alter table public.profiles add constraint profiles_title_level_check 
      check (title_level >= 1 and title_level <= 6);
  end if;
end $$;

-- 添加约束：易币不能为负数
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'profiles_yi_coins_check'
  ) then
    alter table public.profiles add constraint profiles_yi_coins_check 
      check (yi_coins >= 0);
  end if;
end $$;

-- 添加约束：现金余额不能为负数
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'profiles_cash_balance_check'
  ) then
    alter table public.profiles add constraint profiles_cash_balance_check 
      check (cash_balance >= 0);
  end if;
end $$;

-- 创建索引以优化查询性能
create index if not exists idx_profiles_exp on public.profiles(exp desc);
create index if not exists idx_profiles_reputation_desc on public.profiles(reputation desc);
create index if not exists idx_profiles_title_level on public.profiles(title_level);
create index if not exists idx_profiles_yi_coins on public.profiles(yi_coins desc);

-- 添加字段注释
comment on column public.profiles.exp is '修业值 (EXP) - 衡量用户活跃度与平台熟悉度';
comment on column public.profiles.reputation is '声望值 - 衡量用户专业水平与预测准确度';
comment on column public.profiles.yi_coins is '易币余额 - 平台内工具型代币，用于流转与消耗';
comment on column public.profiles.cash_balance is '现金余额（单位：元）- 仅用于认证专家提现';
comment on column public.profiles.title_level is '称号等级：1=白身, 2=学人, 3=术士, 4=方家, 5=先生, 6=国手';
comment on column public.profiles.last_checkin_date is '最后签到日期，用于判断连续签到';
comment on column public.profiles.consecutive_checkin_days is '连续签到天数，用于计算连续签到奖励';

-- 2. 创建易币流水表 (coin_transactions)
-- ============================================
create table if not exists public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  amount integer not null, -- 正数为入账，负数为消费
  type text not null, -- 'check_in', 'bounty', 'recharge', 'service_payment', 'ai_assist', 'view_content', 'daily_task'
  description text,
  related_id uuid, -- 关联的业务ID（如post_id, consultation_id等）
  created_at timestamptz default now()
);

alter table public.coin_transactions enable row level security;

-- RLS策略：用户只能查看自己的易币流水
create policy "coin_transactions_select_own"
  on public.coin_transactions for select
  using (auth.uid() = user_id);

-- RLS策略：系统可以插入记录（通过service_role）
-- 注意：实际插入操作应该通过Edge Function或后台服务完成

-- 创建索引
create index if not exists idx_coin_transactions_user_id on public.coin_transactions(user_id, created_at desc);
create index if not exists idx_coin_transactions_type on public.coin_transactions(type);
create index if not exists idx_coin_transactions_created_at on public.coin_transactions(created_at desc);

-- 添加表注释
comment on table public.coin_transactions is '易币流水表 - 记录所有易币的获取和消耗';
comment on column public.coin_transactions.amount is '金额：正数为入账，负数为消费';
comment on column public.coin_transactions.type is '交易类型：check_in(签到), bounty(悬赏), recharge(充值), service_payment(服务支付), ai_assist(AI辅助), view_content(查看内容), daily_task(每日任务)';
comment on column public.coin_transactions.related_id is '关联的业务ID（如post_id, consultation_id等）';

-- 3. 创建每日任务记录表 (daily_tasks_log)
-- ============================================
create table if not exists public.daily_tasks_log (
  user_id uuid references auth.users(id) on delete cascade not null,
  date date default current_date not null,
  task_type text not null, -- 'login', 'reply', 'verify', 'publish', 'like'
  completed boolean default false,
  completed_at timestamptz,
  primary key (user_id, date, task_type)
);

alter table public.daily_tasks_log enable row level security;

-- RLS策略：用户只能查看自己的任务记录
create policy "daily_tasks_log_select_own"
  on public.daily_tasks_log for select
  using (auth.uid() = user_id);

-- RLS策略：用户可以插入和更新自己的任务记录
create policy "daily_tasks_log_insert_own"
  on public.daily_tasks_log for insert
  with check (auth.uid() = user_id);

create policy "daily_tasks_log_update_own"
  on public.daily_tasks_log for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 创建索引
create index if not exists idx_daily_tasks_log_user_date on public.daily_tasks_log(user_id, date desc);
create index if not exists idx_daily_tasks_log_task_type on public.daily_tasks_log(task_type);

-- 添加表注释
comment on table public.daily_tasks_log is '每日任务记录表 - 记录用户每日完成的任务';
comment on column public.daily_tasks_log.task_type is '任务类型：login(登录), reply(回复), verify(验证), publish(发布), like(点赞)';

-- 4. 创建现金提现申请表 (withdraw_requests)
-- ============================================
create table if not exists public.withdraw_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  amount decimal(10,2) not null,
  status text default 'pending', -- 'pending', 'approved', 'rejected', 'completed'
  payment_method text, -- 'wechat', 'alipay'
  payment_account text, -- 收款账号（微信/支付宝账号）
  payment_name text, -- 收款人姓名
  rejection_reason text, -- 拒绝原因
  reviewed_by uuid references auth.users(id), -- 审核人
  reviewed_at timestamptz, -- 审核时间
  completed_at timestamptz, -- 完成时间（打款时间）
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.withdraw_requests enable row level security;

-- RLS策略：用户只能查看自己的提现申请
create policy "withdraw_requests_select_own"
  on public.withdraw_requests for select
  using (auth.uid() = user_id);

-- RLS策略：用户可以创建自己的提现申请
create policy "withdraw_requests_insert_own"
  on public.withdraw_requests for insert
  with check (auth.uid() = user_id);

-- RLS策略：管理员可以查看和更新所有提现申请
-- 注意：这需要管理员角色检查，实际应该通过Edge Function或后台服务完成

-- 添加约束：金额必须大于0
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'withdraw_requests_amount_check'
  ) then
    alter table public.withdraw_requests add constraint withdraw_requests_amount_check 
      check (amount > 0);
  end if;
end $$;

-- 创建索引
create index if not exists idx_withdraw_requests_user_id on public.withdraw_requests(user_id, created_at desc);
create index if not exists idx_withdraw_requests_status on public.withdraw_requests(status);
create index if not exists idx_withdraw_requests_created_at on public.withdraw_requests(created_at desc);

-- 添加表注释
comment on table public.withdraw_requests is '现金提现申请表 - 记录认证专家的提现申请';
comment on column public.withdraw_requests.status is '状态：pending(待审核), approved(已批准), rejected(已拒绝), completed(已完成)';
comment on column public.withdraw_requests.payment_method is '支付方式：wechat(微信), alipay(支付宝)';

-- 5. 创建函数：计算用户等级（基于EXP）
-- ============================================
create or replace function public.calculate_user_level(exp_value integer)
returns integer
language plpgsql
immutable
as $$
begin
  case
    when exp_value >= 20000 then return 7; -- 一代宗师
    when exp_value >= 10000 then return 6; -- 出神入化
    when exp_value >= 5000 then return 5;  -- 融会贯通
    when exp_value >= 2000 then return 4;  -- 触类旁通
    when exp_value >= 500 then return 3;   -- 渐入佳境
    when exp_value >= 100 then return 2;   -- 登堂入室
    when exp_value >= 1 then return 1;      -- 初涉易途
    else return 0;                          -- 游客
  end case;
end;
$$;

comment on function public.calculate_user_level is '根据修业值(EXP)计算用户等级';

-- 6. 创建函数：计算用户称号等级（基于声望值）
-- ============================================
create or replace function public.calculate_title_level(reputation_value integer)
returns integer
language plpgsql
immutable
as $$
begin
  case
    when reputation_value >= 5000 then return 6; -- 国手（平台邀请制）
    when reputation_value >= 1000 then return 5; -- 先生
    when reputation_value >= 500 then return 4;  -- 方家
    when reputation_value >= 200 then return 3;  -- 术士
    when reputation_value >= 50 then return 2;   -- 学人
    else return 1;                                -- 白身
  end case;
end;
$$;

comment on function public.calculate_title_level is '根据声望值计算用户称号等级';

-- 7. 创建触发器：自动更新用户等级和称号等级
-- ============================================
create or replace function public.update_user_levels()
returns trigger
language plpgsql
as $$
declare
  calculated_level integer;
  calculated_title integer;
begin
  -- 计算并更新等级（基于EXP）
  calculated_level := public.calculate_user_level(coalesce(new.exp, 0));
  
  -- 计算并更新称号等级（基于声望值）
  calculated_title := public.calculate_title_level(coalesce(new.reputation, 0));
  
  -- 如果exp或reputation字段被更新，则更新对应的等级字段
  -- 注意：这里假设有level字段存储等级，如果没有则需要添加
  -- 由于PRD中没有明确提到level字段，我们暂时不更新，只更新title_level
  
  new.title_level := calculated_title;
  
  return new;
end;
$$;

-- 创建触发器（如果exp或reputation字段更新时自动计算等级）
-- 注意：由于PostgreSQL的限制，我们需要在UPDATE时触发
create trigger trigger_update_user_levels
  before update of exp, reputation on public.profiles
  for each row
  when (old.exp is distinct from new.exp or old.reputation is distinct from new.reputation)
  execute function public.update_user_levels();

-- 8. 初始化现有用户的默认值
-- ============================================
-- 为现有用户设置默认的exp和reputation值（如果为null）
update public.profiles
set 
  exp = coalesce(exp, 0),
  reputation = coalesce(reputation, 0),
  yi_coins = coalesce(yi_coins, 0),
  cash_balance = coalesce(cash_balance, 0.00),
  title_level = coalesce(title_level, 1)
where exp is null or reputation is null or yi_coins is null or cash_balance is null or title_level is null;

-- 9. 创建视图：用户成长统计视图（可选，用于快速查询）
-- ============================================
create or replace view public.user_growth_stats as
select 
  p.id,
  p.nickname,
  p.exp,
  p.reputation,
  p.yi_coins,
  p.cash_balance,
  public.calculate_user_level(p.exp) as level,
  p.title_level,
  p.last_checkin_date,
  p.consecutive_checkin_days,
  -- 统计易币交易总数
  (select count(*) from public.coin_transactions ct where ct.user_id = p.id) as total_transactions,
  -- 统计今日任务完成数
  (select count(*) from public.daily_tasks_log dtl 
   where dtl.user_id = p.id 
   and dtl.date = current_date 
   and dtl.completed = true) as today_tasks_completed
from public.profiles p;

comment on view public.user_growth_stats is '用户成长统计视图 - 汇总用户的成长数据';

-- 完成迁移
-- ============================================

