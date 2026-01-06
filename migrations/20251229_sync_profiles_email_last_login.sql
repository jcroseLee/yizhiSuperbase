create or replace function public.handle_new_user()
returns trigger as $$
declare
  default_nickname text;
begin
  if new.raw_user_meta_data->>'nickname' is not null then
    default_nickname := new.raw_user_meta_data->>'nickname';
  elsif new.email is not null then
    default_nickname := split_part(new.email, '@', 1) || '_' || substring(new.id::text, 1, 8);
  else
    default_nickname := '用户_' || substring(new.id::text, 1, 8);
  end if;

  insert into public.profiles (
    id,
    nickname,
    avatar_url,
    role,
    wechat_openid,
    wechat_unionid,
    phone,
    email,
    last_login_at,
    created_at
  )
  values (
    new.id,
    default_nickname,
    coalesce(new.raw_user_meta_data->>'avatar_url', null),
    'user',
    coalesce(new.raw_user_meta_data->>'wechat_openid', null),
    coalesce(new.raw_user_meta_data->>'wechat_unionid', null),
    coalesce(new.phone, null),
    coalesce(new.email, null),
    coalesce(new.last_sign_in_at, null),
    new.created_at
  )
  on conflict (id) do nothing;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

create or replace function public.sync_profile_email_last_login_from_auth_user()
returns trigger as $$
begin
  update public.profiles p
  set
    email = coalesce(new.email, p.email),
    last_login_at = coalesce(new.last_sign_in_at, p.last_login_at)
  where p.id = new.id;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_updated_sync_profile_email_last_login on auth.users;
create trigger on_auth_user_updated_sync_profile_email_last_login
  after update of email, last_sign_in_at on auth.users
  for each row
  execute function public.sync_profile_email_last_login_from_auth_user();

