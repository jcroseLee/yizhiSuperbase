-- Add cover_image_url column to posts table for article cover images
alter table public.posts
  add column if not exists cover_image_url text;

