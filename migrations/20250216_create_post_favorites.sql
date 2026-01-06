-- 创建帖子收藏表
create table if not exists public.post_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  unique (user_id, post_id)
);

-- 启用行级安全
alter table public.post_favorites enable row level security;

-- 用户可以查看自己的收藏
create policy "post_favorites_select_own"
  on public.post_favorites for select
  using (auth.uid() = user_id);

-- 用户可以添加自己的收藏
create policy "post_favorites_insert_own"
  on public.post_favorites for insert
  with check (auth.uid() = user_id);

-- 用户可以删除自己的收藏
create policy "post_favorites_delete_own"
  on public.post_favorites for delete
  using (auth.uid() = user_id);

-- 创建索引以提高查询性能
create index if not exists post_favorites_user_id_idx on public.post_favorites(user_id);
create index if not exists post_favorites_post_id_idx on public.post_favorites(post_id);
create index if not exists post_favorites_created_at_idx on public.post_favorites(created_at desc);

