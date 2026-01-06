-- Add metadata column to messages for rich media support
-- Safe to re-run: uses IF NOT EXISTS

alter table public.messages
  add column if not exists metadata jsonb;

-- Optional GIN index for querying metadata
create index if not exists idx_messages_metadata_gin
  on public.messages
  using gin (metadata);

comment on column public.messages.metadata is 'Arbitrary JSON metadata for messages (e.g., { kind: \"image\"|\"audio\", url, durationMs, width, height })';


