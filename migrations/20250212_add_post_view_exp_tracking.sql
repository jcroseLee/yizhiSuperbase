-- 创建帖子浏览EXP记录表（防刷机制）
-- 用于记录用户每天浏览每个帖子是否已获得EXP，确保每个帖子每天只能获得一次EXP

create table if not exists public.post_view_exp_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  post_id uuid references public.posts(id) on delete cascade not null,
  view_date date not null default current_date,
  created_at timestamptz default now(),
  unique(user_id, post_id, view_date)
);

-- 创建索引以优化查询性能
create index if not exists idx_post_view_exp_log_user_post_date 
  on public.post_view_exp_log(user_id, post_id, view_date desc);

create index if not exists idx_post_view_exp_log_post_date 
  on public.post_view_exp_log(post_id, view_date desc);

-- 启用RLS
alter table public.post_view_exp_log enable row level security;

-- RLS策略：用户只能查看自己的浏览记录
create policy "post_view_exp_log_select_own"
  on public.post_view_exp_log for select
  using (auth.uid() = user_id);

-- RLS策略：用户可以插入自己的浏览记录
create policy "post_view_exp_log_insert_own"
  on public.post_view_exp_log for insert
  with check (auth.uid() = user_id);

-- 添加表注释
comment on table public.post_view_exp_log is '帖子浏览EXP记录表 - 用于防刷机制，记录用户每天浏览每个帖子是否已获得EXP';
comment on column public.post_view_exp_log.view_date is '浏览日期（用于判断是否同一天）';

