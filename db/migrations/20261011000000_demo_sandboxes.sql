-- Private demos: every "Try the demo" gets its own copy of the demo world.
--
-- Until now every visitor signed into one shared account, so what one person
-- paid, voted or joined changed the demo for the next. Now the API creates a
-- sandbox per visit: a fresh copy of the seeded people and circles, tagged
-- with the sandbox's id, and signs the visitor into that copy's demo member.
--
-- A sandbox is a closed world: its invite codes only reach its own circles,
-- and a handover can't reach a real person (nor a real person a sandbox). The
-- shared seeded demo (reserved +2348000000xxx numbers) stays as it is, for the
-- public verify page. Sandboxes expire after a day; the API purges expired
-- ones before creating a new one, so no scheduler is needed.

create table if not exists demo_sandboxes (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index if not exists demo_sandboxes_expiry_idx on demo_sandboxes (expires_at);

alter table users add column if not exists sandbox_id uuid references demo_sandboxes(id);
alter table groups add column if not exists sandbox_id uuid references demo_sandboxes(id);
create index if not exists users_sandbox_idx on users (sandbox_id) where sandbox_id is not null;
create index if not exists groups_sandbox_idx on groups (sandbox_id) where sandbox_id is not null;

-- A circle belongs to its admin's world.
create or replace function groups_set_sandbox()
returns trigger
language plpgsql as $$
begin
  new.sandbox_id := (select sandbox_id from users where id = new.admin_id);
  return new;
end $$;

drop trigger if exists groups_sandbox on groups;
create trigger groups_sandbox before insert on groups
  for each row execute function groups_set_sandbox();

-- Invite codes are unique within a world, so every sandbox can use the demo's codes.
alter table groups drop constraint if exists groups_invite_code_key;
drop index if exists groups_invite_code_key;
create unique index groups_invite_code_key
  on groups (invite_code, coalesce(sandbox_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Joining looks the code up in the joiner's own world (otherwise as in 20261010000000).
create or replace function join_circle(p_user_id uuid, p_invite_code text, p_voucher_id uuid, p_rules_version int)
returns uuid
language plpgsql as $$
declare
  g        groups%rowtype;
  v_rules  group_rules%rowtype;
  v_count  int;
begin
  select * into g from groups
   where invite_code = upper(p_invite_code)
     and sandbox_id is not distinct from (select sandbox_id from users where id = p_user_id)
     for update;
  if not found then perform sova_fail(404, 'circle_not_found', 'No circle uses that code. Check it and try again.'); end if;
  if exists (select 1 from group_members where group_id = g.id and user_id = p_user_id) then
    perform sova_fail(409, 'already_member', 'You are already in this circle.');
  end if;
  if g.status = 'cancelled' then
    perform sova_fail(409, 'circle_cancelled', 'The admin cancelled this circle before it started.');
  end if;
  if g.status <> 'forming' then
    perform sova_fail(409, 'circle_started', 'This circle has already started. Ask the admin about the next one.');
  end if;
  select count(*) into v_count from group_members where group_id = g.id;
  if v_count >= g.member_count then perform sova_fail(409, 'circle_full', 'This circle is full.'); end if;
  if p_voucher_id is not null
     and not exists (select 1 from group_members where group_id = g.id and user_id = p_voucher_id) then
    perform sova_fail(422, 'invalid_voucher', 'The person vouching for you must already be in this circle.');
  end if;

  select * into v_rules from group_rules where group_id = g.id order by version desc limit 1;
  if v_rules.version is distinct from p_rules_version then
    perform sova_fail(409, 'rules_changed', 'The rules changed while you were reading. Please read them again.');
  end if;

  insert into group_members (group_id, user_id) values (g.id, p_user_id);
  insert into rule_acceptances (rules_id, user_id) values (v_rules.id, p_user_id);
  if p_voucher_id is not null then
    insert into vouches (group_id, voucher_id, vouchee_id) values (g.id, p_voucher_id, p_user_id);
  end if;

  perform try_start_circle(g.id);
  return g.id;
end $$;

-- A handover stays inside its world (otherwise as in 20261008000000).
create or replace function request_handover(p_user_id uuid, p_group_id uuid, p_phone text, p_reason text)
returns uuid
language plpgsql as $$
declare
  g        groups%rowtype;
  v_pos    int;
  v_repl   uuid;
  v_id     uuid;
begin
  select * into g from groups where id = p_group_id;
  if not found or not exists (select 1 from group_members where group_id = p_group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Circle not found.');
  end if;
  if g.status not in ('forming', 'active') then perform sova_fail(409, 'not_active', 'This circle has finished.'); end if;
  if g.admin_id = p_user_id then
    perform sova_fail(409, 'admin_cannot_leave', 'The admin can''t hand over their place yet.');
  end if;
  if g.sandbox_id is not null then
    perform sova_fail(409, 'demo_handover', 'In the demo, places can''t be handed to a real phone number.');
  end if;
  select payout_position into v_pos from group_members where group_id = p_group_id and user_id = p_user_id;
  if not position_is_open(p_group_id, v_pos) then
    perform sova_fail(409, 'turn_started', 'You have already collected or are collecting, so you need to finish the cycle.');
  end if;
  select id into v_repl from users where phone = p_phone and full_name is not null and sandbox_id is null;
  if v_repl is null then
    perform sova_fail(404, 'no_account', 'Nobody with that number uses Sova yet. Ask them to sign up first.');
  end if;
  if v_repl = p_user_id or exists (select 1 from group_members where group_id = p_group_id and user_id = v_repl) then
    perform sova_fail(409, 'already_member', 'That person is already in this circle.');
  end if;
  if exists (select 1 from handover_requests where group_id = p_group_id and leaving_user_id = p_user_id
               and status in ('pending', 'accepted', 'approved')) then
    perform sova_fail(409, 'already_asked', 'You already have a handover in progress. Cancel it first.');
  end if;
  insert into handover_requests (group_id, leaving_user_id, replacement_user_id, reason)
  values (p_group_id, p_user_id, v_repl, nullif(trim(p_reason), ''))
  returning id into v_id;
  return v_id;
end $$;

-- The ledger may be purged for the seeded demo and for sandboxes, nothing else
-- (otherwise as in 20261005000000_ledger.sql).
create or replace function ledger_guard()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE'
     and current_setting('sova.purge_demo', true) = 'on'
     and exists (select 1 from groups g join users u on u.id = g.admin_id
                  where g.id = old.group_id and (u.phone like '+2348000000%' or g.sandbox_id is not null)) then
    return old;
  end if;
  raise exception using errcode = 'SV409', hint = 'ledger_append_only',
    message = 'The ledger is append-only: entries can''t be changed or removed.';
end $$;

-- Removes expired sandboxes and everything in them. Runs as the migration's
-- owner, because the API's role may not delete ledger entries; it only ever
-- touches sandbox rows.
create or replace function purge_demo_sandboxes()
returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ids  uuid[];
begin
  select array_agg(id) into v_ids from demo_sandboxes where expires_at < now();
  if v_ids is null then return 0; end if;
  perform set_config('sova.purge_demo', 'on', true);
  perform set_config('sova.seeding', 'on', true);
  delete from ledger_entries where group_id in (select id from groups where sandbox_id = any(v_ids));
  delete from groups where sandbox_id = any(v_ids);
  delete from users where sandbox_id = any(v_ids);
  delete from demo_sandboxes where id = any(v_ids);
  perform set_config('sova.purge_demo', 'off', true);
  perform set_config('sova.seeding', 'off', true);
  return cardinality(v_ids);
end $$;
