-- Add motto column to profiles table
alter table public.profiles add column if not exists motto text;

