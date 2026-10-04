-- Phase 3: the tamper-evident ledger.
--
-- Every event that matters to a circle's money is appended, by trigger, to a
-- per-circle hash chain:
--
--   hash = SHA-256( prev_hash || '|' || seq || '|' || kind || '|' || body )
--
-- where body is the event's JSON exactly as stored (text, not re-serialised),
-- and the first entry's prev_hash is 64 zeros. Changing, removing or
-- reordering any entry breaks every hash after it, which anyone can check
-- from the public chain. The ledger is tamper-evident, not tamper-proof:
-- whoever controls the database could rewrite the whole chain, which is why
-- publishing chain heads elsewhere is on the roadmap.
--
-- Entries can't be updated, deleted or truncated (triggers below, for every
-- role; the API's role also loses those privileges). The one exception is
-- purging the seeded demo circles, which requires an explicit session flag
-- and only touches circles run by the reserved demo phone numbers.

create table if not exists ledger_entries (
  id          bigserial primary key,
  group_id    uuid not null references groups(id),  -- no cascade: a circle with a ledger can't be deleted
  seq         int not null check (seq > 0),
  kind        text not null,
  body        text not null,
  prev_hash   text not null check (prev_hash ~ '^[0-9a-f]{64}$'),
  hash        text not null check (hash ~ '^[0-9a-f]{64}$'),
  created_at  timestamptz not null default now(),
  unique (group_id, seq)
);

-- Tables the migration runner makes read-only for the API role (no UPDATE, DELETE, TRUNCATE).
create table if not exists append_only_tables (name text primary key);
insert into append_only_tables values ('ledger_entries') on conflict do nothing;

create or replace function ledger_hash(p_prev text, p_seq int, p_kind text, p_body text)
returns text
language sql immutable as $$
  select encode(sha256(convert_to(p_prev || '|' || p_seq || '|' || p_kind || '|' || p_body, 'UTF8')), 'hex');
$$;

create or replace function ledger_append(p_group_id uuid, p_kind text, p_payload jsonb)
returns void
language plpgsql as $$
declare
  v_last  ledger_entries%rowtype;
  v_seq   int;
  v_prev  text;
  v_body  text := p_payload::text;
begin
  -- One writer per circle at a time, so sequence numbers never clash.
  perform pg_advisory_xact_lock(hashtext('ledger:' || p_group_id::text));
  select * into v_last from ledger_entries where group_id = p_group_id order by seq desc limit 1;
  v_seq  := coalesce(v_last.seq, 0) + 1;
  v_prev := coalesce(v_last.hash, repeat('0', 64));
  insert into ledger_entries (group_id, seq, kind, body, prev_hash, hash)
  values (p_group_id, v_seq, p_kind, v_body, v_prev, ledger_hash(v_prev, v_seq, p_kind, v_body));
end $$;

-- How a person appears in the public ledger: their id (needed to check the
-- draw) and first name plus initial. Never phone numbers or bank details.
create or replace function ledger_who(p_user_id uuid)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', u.id,
    'name', coalesce(split_part(u.full_name, ' ', 1) || coalesce(' ' || left(nullif(split_part(u.full_name, ' ', 2), ''), 1) || '.', ''), 'Member'))
  from users u where u.id = p_user_id;
$$;

create or replace function ledger_ts(p timestamptz)
returns text
language sql immutable as $$
  select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

-- Append-only guard ------------------------------------------------------------
create or replace function ledger_guard()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE'
     and current_setting('sova.purge_demo', true) = 'on'
     and exists (select 1 from groups g join users u on u.id = g.admin_id
                  where g.id = old.group_id and u.phone like '+2348000000%') then
    return old;  -- resetting the seeded demo circles only
  end if;
  raise exception using errcode = 'SV409', hint = 'ledger_append_only',
    message = 'The ledger is append-only: entries can''t be changed or removed.';
end $$;

drop trigger if exists ledger_no_update on ledger_entries;
create trigger ledger_no_update before update or delete on ledger_entries
  for each row execute function ledger_guard();

create or replace function ledger_no_truncate_fn()
returns trigger
language plpgsql as $$
begin
  raise exception using errcode = 'SV409', hint = 'ledger_append_only',
    message = 'The ledger is append-only: entries can''t be changed or removed.';
end $$;

drop trigger if exists ledger_no_truncate on ledger_entries;
create trigger ledger_no_truncate before truncate on ledger_entries
  for each statement execute function ledger_no_truncate_fn();

-- Events -------------------------------------------------------------------------

create or replace function ledger_on_group()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    perform ledger_append(new.id, 'circle_created', jsonb_build_object(
      'at', ledger_ts(new.created_at), 'name', new.name, 'admin', ledger_who(new.admin_id),
      'contribution', new.contribution_amount, 'members', new.member_count, 'cycle', new.cycle_type,
      'startDate', new.start_date, 'adminCollectsLast', new.admin_collects_last));
  elsif new.status = 'completed' and old.status <> 'completed' then
    perform ledger_append(new.id, 'circle_completed', jsonb_build_object('at', ledger_ts(now())));
  end if;
  return null;
end $$;

drop trigger if exists ledger_group on groups;
create trigger ledger_group after insert or update of status on groups
  for each row execute function ledger_on_group();

create or replace function ledger_on_draw()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    perform ledger_append(new.group_id, 'draw_committed',
      jsonb_build_object('at', ledger_ts(new.created_at), 'commitment', new.commitment));
  end if;
  if new.revealed_at is not null and (tg_op = 'INSERT' or old.revealed_at is null) then
    perform ledger_append(new.group_id, 'draw_revealed', jsonb_build_object(
      'at', ledger_ts(new.revealed_at), 'seed', new.seed,
      'order', (select jsonb_agg(ledger_who(m.user_id) order by m.payout_position)
                  from group_members m where m.group_id = new.group_id)));
  end if;
  return null;
end $$;

drop trigger if exists ledger_draw on circle_draws;
create trigger ledger_draw after insert or update of revealed_at on circle_draws
  for each row execute function ledger_on_draw();

create or replace function ledger_on_member()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'member_joined',
    jsonb_build_object('at', ledger_ts(new.joined_at), 'member', ledger_who(new.user_id)));
  return null;
end $$;

drop trigger if exists ledger_member on group_members;
create trigger ledger_member after insert on group_members
  for each row execute function ledger_on_member();

create or replace function ledger_on_vouch()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'member_vouched', jsonb_build_object(
    'at', ledger_ts(new.created_at), 'voucher', ledger_who(new.voucher_id), 'member', ledger_who(new.vouchee_id)));
  return null;
end $$;

drop trigger if exists ledger_vouch on vouches;
create trigger ledger_vouch after insert on vouches
  for each row execute function ledger_on_vouch();

create or replace function ledger_on_rules()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'rules_published', jsonb_build_object(
    'at', ledger_ts(new.created_at), 'version', new.version, 'lateFee', new.late_fee, 'graceDays', new.grace_days,
    'earlyExit', new.early_exit_policy, 'emergency', new.emergency_policy, 'other', new.other_rules));
  return null;
end $$;

drop trigger if exists ledger_rules on group_rules;
create trigger ledger_rules after insert on group_rules
  for each row execute function ledger_on_rules();

create or replace function ledger_on_acceptance()
returns trigger
language plpgsql as $$
declare
  r group_rules%rowtype;
begin
  select * into r from group_rules where id = new.rules_id;
  perform ledger_append(r.group_id, 'rules_accepted', jsonb_build_object(
    'at', ledger_ts(new.accepted_at), 'member', ledger_who(new.user_id), 'version', r.version));
  return null;
end $$;

drop trigger if exists ledger_acceptance on rule_acceptances;
create trigger ledger_acceptance after insert on rule_acceptances
  for each row execute function ledger_on_acceptance();

create or replace function ledger_on_round()
returns trigger
language plpgsql as $$
declare
  v_expected int;
begin
  if tg_op = 'INSERT' then
    perform ledger_append(new.group_id, 'turn_opened', jsonb_build_object(
      'at', ledger_ts(new.created_at), 'turn', new.round_number, 'collector', ledger_who(new.collector_id),
      'due', new.due_date));
  elsif new.status = 'active' and old.status <> 'active' then
    perform ledger_append(new.group_id, 'turn_opened', jsonb_build_object(
      'at', ledger_ts(now()), 'turn', new.round_number, 'collector', ledger_who(new.collector_id), 'due', new.due_date));
  end if;
  if new.payout_confirmed_at is not null and (tg_op = 'INSERT' or old.payout_confirmed_at is null) then
    select g.contribution_amount * greatest(count(m.*) - 1, 0) into v_expected
      from groups g join group_members m on m.group_id = g.id where g.id = new.group_id group by g.contribution_amount;
    perform ledger_append(new.group_id, 'payout_confirmed', jsonb_build_object(
      'at', ledger_ts(new.payout_confirmed_at), 'turn', new.round_number, 'collector', ledger_who(new.collector_id),
      'expected', v_expected, 'received', new.payout_received, 'shortfall', greatest(v_expected - new.payout_received, 0)));
  end if;
  return null;
end $$;

drop trigger if exists ledger_round on rounds;
create trigger ledger_round after insert or update of status, payout_confirmed_at on rounds
  for each row execute function ledger_on_round();

create or replace function ledger_on_contribution()
returns trigger
language plpgsql as $$
declare
  v_turn       int;
  v_collector  uuid;
begin
  select round_number, collector_id into v_turn, v_collector from rounds where id = new.round_id;
  if new.status in ('payer_confirmed', 'fully_confirmed') and (tg_op = 'INSERT' or old.status = 'pending') then
    perform ledger_append(new.group_id, 'payment_marked', jsonb_build_object(
      'at', ledger_ts(coalesce(new.payer_confirmed_at, now())), 'turn', v_turn, 'payer', ledger_who(new.user_id),
      'amount', new.amount, 'hasReference', new.bank_reference is not null));
  end if;
  if new.status = 'fully_confirmed' and (tg_op = 'INSERT' or old.status <> 'fully_confirmed') then
    perform ledger_append(new.group_id, 'payment_confirmed', jsonb_build_object(
      'at', ledger_ts(coalesce(new.collector_confirmed_at, now())), 'turn', v_turn, 'payer', ledger_who(new.user_id),
      'collector', ledger_who(v_collector), 'amount', new.amount));
  end if;
  return null;
end $$;

drop trigger if exists ledger_contribution on contributions;
create trigger ledger_contribution after insert or update of status on contributions
  for each row execute function ledger_on_contribution();

create or replace function ledger_on_dispute()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'dispute_opened', jsonb_build_object(
    'at', ledger_ts(new.created_at), 'turn', (select round_number from rounds where id = new.round_id),
    'raisedBy', ledger_who(new.raised_by), 'reason', new.reason));
  return null;
end $$;

drop trigger if exists ledger_dispute on disputes;
create trigger ledger_dispute after insert on disputes
  for each row execute function ledger_on_dispute();
