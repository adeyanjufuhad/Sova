-- Phase 2: the circle lifecycle.
--
--   forming  --(full, and everyone accepted the rules)-->  fair draw  -->  active  -->  completed
--
-- Every rule that guards the money records lives in these functions, so the
-- API (or anything else) can only move a circle forward the agreed way.
-- Functions report problems with sova_fail(): SQLSTATE 'SV' + HTTP status,
-- a machine-readable code in HINT and a message safe to show to people.

create or replace function sova_fail(p_status int, p_code text, p_message text)
returns void
language plpgsql as $$
begin
  raise exception using errcode = 'SV' || p_status::text, message = p_message, hint = p_code;
end $$;

-- Circles wait in 'forming' until they are full.
alter table groups drop constraint if exists groups_status_check;
alter table groups add constraint groups_status_check check (status in ('forming', 'active', 'paused', 'completed'));
alter table groups alter column status set default 'forming';

-- Fair draw (commit-reveal) ----------------------------------------------------
-- At creation Sova picks a random 32-byte seed and publishes only its SHA-256
-- (the commitment). When the circle starts, positions are ordered by
-- SHA-256(seed_hex || ':' || user_id) and the seed is revealed, so any member
-- can check the order was fixed before anyone joined. The admin's
-- "collect last" pledge puts them last; everyone else is ordered by the hash.
create table if not exists circle_draws (
  group_id     uuid primary key references groups(id) on delete cascade,
  commitment   text not null check (commitment ~ '^[0-9a-f]{64}$'),
  seed         text not null check (seed ~ '^[0-9a-f]{64}$'),
  revealed_at  timestamptz,
  created_at   timestamptz not null default now(),
  constraint circle_draws_commitment_matches check (commitment = encode(sha256(decode(seed, 'hex')), 'hex'))
);

create or replace function draw_key(p_seed text, p_user_id uuid)
returns text
language sql immutable as $$
  select encode(sha256(convert_to(p_seed || ':' || p_user_id::text, 'UTF8')), 'hex');
$$;

create or replace function run_draw(p_group_id uuid)
returns void
language plpgsql as $$
declare
  g  groups%rowtype;
  d  circle_draws%rowtype;
begin
  select * into g from groups where id = p_group_id for update;
  if g.status <> 'forming' then perform sova_fail(409, 'circle_started', 'This circle has already started.'); end if;
  select * into d from circle_draws where group_id = p_group_id for update;
  if not found then perform sova_fail(409, 'no_draw', 'This circle has no draw commitment.'); end if;
  if d.revealed_at is not null then perform sova_fail(409, 'already_drawn', 'The turns were already drawn.'); end if;

  with ordered as (
    select user_id,
           row_number() over (
             -- byte order, whatever the database locale, so anyone can reproduce it
             order by (g.admin_collects_last and user_id = g.admin_id), draw_key(d.seed, user_id) collate "C"
           ) as position
      from group_members
     where group_id = p_group_id
  )
  update group_members m
     set payout_position = o.position
    from ordered o
   where m.group_id = p_group_id and m.user_id = o.user_id;

  update circle_draws set revealed_at = now() where group_id = p_group_id;
end $$;

-- Starts the circle when it is full and every member accepted the current
-- rules: draws the turns and opens round 1. Returns whether it started.
create or replace function try_start_circle(p_group_id uuid)
returns boolean
language plpgsql as $$
declare
  g           groups%rowtype;
  v_joined    int;
  v_rules_id  uuid;
  v_accepted  int;
begin
  select * into g from groups where id = p_group_id for update;
  if g.status <> 'forming' then return false; end if;

  select count(*) into v_joined from group_members where group_id = p_group_id;
  if v_joined < g.member_count then return false; end if;

  select id into v_rules_id from group_rules where group_id = p_group_id order by version desc limit 1;
  select count(*) into v_accepted
    from rule_acceptances a
    join group_members m on m.user_id = a.user_id and m.group_id = p_group_id
   where a.rules_id = v_rules_id;
  if v_accepted < v_joined then return false; end if;

  perform run_draw(p_group_id);
  -- A circle that filled up after its planned start date starts today.
  update groups set status = 'active', start_date = greatest(start_date, current_date) where id = p_group_id;
  perform force_advance_round(p_group_id);
  return true;
end $$;

-- Joining ---------------------------------------------------------------------
-- The newcomer accepts the rules version they read; an existing member may vouch.
create or replace function join_circle(p_user_id uuid, p_invite_code text, p_voucher_id uuid, p_rules_version int)
returns uuid
language plpgsql as $$
declare
  g        groups%rowtype;
  v_rules  group_rules%rowtype;
  v_count  int;
begin
  select * into g from groups where invite_code = upper(p_invite_code) for update;
  if not found then perform sova_fail(404, 'circle_not_found', 'No circle uses that code. Check it and try again.'); end if;
  if exists (select 1 from group_members where group_id = g.id and user_id = p_user_id) then
    perform sova_fail(409, 'already_member', 'You are already in this circle.');
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

-- A member accepts the current rules (for example after the admin changed them).
create or replace function accept_rules(p_user_id uuid, p_group_id uuid, p_version int)
returns boolean
language plpgsql as $$
declare
  v_rules  group_rules%rowtype;
begin
  if not exists (select 1 from group_members where group_id = p_group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Circle not found.');
  end if;
  select * into v_rules from group_rules where group_id = p_group_id order by version desc limit 1;
  if v_rules.version is distinct from p_version then
    perform sova_fail(409, 'rules_changed', 'The rules changed while you were reading. Please read them again.');
  end if;
  insert into rule_acceptances (rules_id, user_id) values (v_rules.id, p_user_id) on conflict do nothing;
  return try_start_circle(p_group_id);
end $$;

-- Paying ----------------------------------------------------------------------
-- A member says they sent this turn's contribution to the collector. The
-- amount is always the circle's contribution. Late payments into earlier
-- turns are allowed (that is how someone clears what they owe).
create or replace function record_contribution(p_user_id uuid, p_round_id uuid, p_bank_reference text, p_proof_url text)
returns uuid
language plpgsql as $$
declare
  r         rounds%rowtype;
  v_status  text;
  v_id      uuid;
begin
  select * into r from rounds where id = p_round_id;
  if not found or not exists (select 1 from group_members where group_id = r.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Turn not found.');
  end if;
  if r.status = 'pending' then perform sova_fail(409, 'round_not_open', 'This turn has not started yet.'); end if;
  if r.collector_id = p_user_id then
    perform sova_fail(409, 'own_turn', 'You collect this turn, so you don''t pay into it.');
  end if;

  select status into v_status from contributions where round_id = p_round_id and user_id = p_user_id for update;
  if v_status = 'fully_confirmed' then
    perform sova_fail(409, 'already_confirmed', 'The collector already confirmed this payment.');
  elsif v_status = 'disputed' then
    perform sova_fail(409, 'disputed', 'This payment is under dispute.');
  end if;

  insert into contributions (round_id, group_id, user_id, amount, payer_confirmed, payer_confirmed_at, status, bank_reference, proof_url)
  select r.id, r.group_id, p_user_id, g.contribution_amount, true, now(), 'payer_confirmed', p_bank_reference, p_proof_url
    from groups g where g.id = r.group_id
  on conflict (round_id, user_id) do update
     set payer_confirmed    = true,
         payer_confirmed_at = coalesce(contributions.payer_confirmed_at, now()),
         status             = 'payer_confirmed',
         bank_reference     = coalesce(excluded.bank_reference, contributions.bank_reference),
         proof_url          = coalesce(excluded.proof_url, contributions.proof_url)
  returning id into v_id;
  return v_id;
end $$;

-- The turn's collector confirms the money arrived.
create or replace function confirm_contribution(p_user_id uuid, p_contribution_id uuid)
returns void
language plpgsql as $$
declare
  c  contributions%rowtype;
  r  rounds%rowtype;
begin
  select * into c from contributions where id = p_contribution_id for update;
  if not found or not exists (select 1 from group_members where group_id = c.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Payment not found.');
  end if;
  select * into r from rounds where id = c.round_id;
  if r.collector_id <> p_user_id then
    perform sova_fail(403, 'not_collector', 'Only the collector for this turn can confirm payments.');
  end if;
  if c.status = 'fully_confirmed' then perform sova_fail(409, 'already_confirmed', 'You already confirmed this payment.'); end if;
  if c.status <> 'payer_confirmed' then
    perform sova_fail(409, 'not_paid', 'This member hasn''t marked the payment as sent yet.');
  end if;

  update contributions
     set collector_confirmed = true, collector_confirmed_at = now(), status = 'fully_confirmed'
   where id = p_contribution_id;
end $$;

-- Closing a turn --------------------------------------------------------------
-- The collector confirms what reached them. A shortfall opens a dispute
-- automatically; either way the circle moves to the next turn (or completes),
-- and everyone's Sova Score is recalculated.
create or replace function close_round(p_user_id uuid, p_round_id uuid, p_amount int)
returns table (shortfall int, dispute_id uuid, next_round int)
language plpgsql as $$
declare
  r           rounds%rowtype;
  g           groups%rowtype;
  v_expected  int;
begin
  select * into r from rounds where id = p_round_id for update;
  if not found or not exists (select 1 from group_members where group_id = r.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Turn not found.');
  end if;
  if r.collector_id <> p_user_id then
    perform sova_fail(403, 'not_collector', 'Only the collector for this turn can confirm the payout.');
  end if;
  if r.status <> 'active' then perform sova_fail(409, 'round_not_active', 'This is not the current turn.'); end if;
  if p_amount < 0 then perform sova_fail(422, 'invalid_amount', 'The amount cannot be negative.'); end if;

  select * into g from groups where id = r.group_id;
  v_expected := g.contribution_amount * greatest((select count(*)::int from group_members where group_id = g.id) - 1, 0);
  shortfall := confirm_payout(p_round_id, p_user_id, p_amount);
  dispute_id := null;

  if shortfall > 0 then
    insert into disputes (group_id, round_id, raised_by, reason)
    values (g.id, r.id, p_user_id,
            format('Turn %s payout was ₦%s short: expected ₦%s, received ₦%s.', r.round_number,
                   to_char(shortfall, 'FM999,999,999,990'), to_char(v_expected, 'FM999,999,999,990'),
                   to_char(p_amount, 'FM999,999,999,990')))
    returning id into dispute_id;
    insert into dispute_events (dispute_id, actor_id, kind, message)
    values (dispute_id, p_user_id, 'opened', 'Opened automatically when the collector confirmed a short payout.');
  end if;

  next_round := force_advance_round(g.id);
  perform calculate_sova_score(m.user_id) from group_members m where m.group_id = g.id;
  return next;
end $$;
