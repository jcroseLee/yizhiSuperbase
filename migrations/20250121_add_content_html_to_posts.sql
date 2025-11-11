-- Add content_html column to posts table for rich text support
alter table public.posts
  add column if not exists content_html text;

