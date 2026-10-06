-- Phase 4: disputes decided by the circle.
--
-- Two kinds of dispute:
--   shortfall  opened automatically when a collector confirms a short payout
--              (close_round). It closes by itself once every missing payment
--              for that turn is confirmed, or when the collector marks it settled.
--   payment    about one payment marked as sent: the collector says it hasn't
--              arrived, or the payer says it isn't being confirmed. The payment
--              is frozen as 'disputed' while the circle votes.
--
-- Voting (payment disputes only): every member except the payer and the
-- collector may vote on "did the money arrive?". Votes are open (they go in the
-- ledger) and can be changed while the dispute is open. A side wins when more
-- than half of the eligible voters back it. Either party can also settle it by
-- agreeing with the other side.
--
-- Outcome on the record (Sova never moves money):
--   resolved_for_payer      the payment counts as confirmed
--   resolved_for_collector  the payment goes back to unpaid; the payer can pay again

alter table disputes add column if not exists kind text not null default 'shortfall';
alter table disputes drop constraint if exists disputes_kind_check;
alter table disputes add constraint disputes_kind_check check (kind in ('shortfall', 'payment'));
alter table disputes drop constraint if exists disputes_payment_has_contribution;
alter table disputes add constraint disputes_payment_has_contribution check (kind <> 'payment' or contribution_id is not null);

-- One open dispute per payment.
create unique index if not exists disputes_open_payment_idx on disputes (contribution_id) where status = 'open';

create table if not exists dispute_votes (
  dispute_id  uuid not null references disputes(id) on delete cascade,
  voter_id    uuid not null references users(id),
  side        text not null check (side in ('payer', 'collector')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (dispute_id, voter_id)
);

-- Who is on each side ---------------------------------------------------------

-- The collector of the dispute's turn.
create or replace function dispute_collector(p_dispute_id uuid)
returns uuid
language sql stable as $$
  select r.collector_id from disputes d join rounds r on r.id = d.round_id where d.id = p_dispute_id;
$$;

-- The payer(s): the payment's payer, or for a shortfall the members whose
-- payment for that turn is still not confirmed.
create or replace function dispute_payers(p_dispute_id uuid)
returns setof uuid
language sql stable as $$
  select c.user_id from disputes d join contributions c on c.id = d.contribution_id
   where d.id = p_dispute_id and d.kind = 'payment'
  union all
  select m.user_id
    from disputes d
    join rounds r on r.id = d.round_id
    join group_members m on m.group_id = d.group_id and m.user_id <> r.collector_id
   where d.id = p_dispute_id and d.kind = 'shortfall'
     and not exists (select 1 from contributions c
                      where c.round_id = r.id and c.user_id = m.user_id and c.status = 'fully_confirmed');
$$;

-- Members who may vote: everyone in the circle except the payer and the collector.
create or replace function dispute_eligible_voters(p_dispute_id uuid)
returns int
language sql stable as $$
  select count(*)::int
    from disputes d join group_members m on m.group_id = d.group_id
   where d.id = p_dispute_id
     and m.user_id <> dispute_collector(d.id)
     and m.user_id not in (select dispute_payers(d.id));
$$;

-- Resolving --------------------------------------------------------------------

create or replace function resolve_dispute(p_dispute_id uuid, p_status text, p_actor uuid, p_note text)
returns void
language plpgsql as $$
declare
  d  disputes%rowtype;
begin
  select * into d from disputes where id = p_dispute_id for update;
  if d.status <> 'open' then perform sova_fail(409, 'dispute_closed', 'This dispute is already closed.'); end if;

  update disputes
     set status = p_status, resolution_note = p_note, resolved_by = p_actor, resolved_at = now()
   where id = p_dispute_id;
  insert into dispute_events (dispute_id, actor_id, kind, message) values (p_dispute_id, p_actor, 'resolved', p_note);

  if d.kind = 'payment' then
    if p_status = 'resolved_for_payer' then
      update contributions
         set status = 'fully_confirmed', collector_confirmed = true, collector_confirmed_at = now()
       where id = d.contribution_id;
    elsif p_status = 'resolved_for_collector' then
      update contributions
         set status = 'pending', payer_confirmed = false, payer_confirmed_at = null
       where id = d.contribution_id;
    end if;
    perform calculate_sova_score(c.user_id) from contributions c where c.id = d.contribution_id;
  end if;
end $$;

-- A shortfall closes by itself once nobody's payment for that turn is missing.
create or replace function settle_shortfalls(p_round_id uuid)
returns void
language plpgsql as $$
declare
  v_id  uuid;
begin
  for v_id in
    select d.id from disputes d
     where d.round_id = p_round_id and d.kind = 'shortfall' and d.status = 'open'
       and not exists (select dispute_payers(d.id))
  loop
    perform resolve_dispute(v_id, 'resolved_for_payer', dispute_collector(v_id),
                            'Made up: every missing payment for this turn is now confirmed.');
  end loop;
end $$;

create or replace function settle_shortfalls_on_confirm()
returns trigger
language plpgsql as $$
begin
  perform settle_shortfalls(new.round_id);
  return null;
end $$;

drop trigger if exists contributions_settle_shortfalls on contributions;
create trigger contributions_settle_shortfalls after insert or update of status on contributions
  for each row when (new.status = 'fully_confirmed') execute function settle_shortfalls_on_confirm();

-- Member actions ----------------------------------------------------------------

-- The collector says a payment marked as sent hasn't arrived, or the payer says
-- it isn't being confirmed. The payment is frozen until the dispute closes.
create or replace function raise_payment_dispute(p_user_id uuid, p_contribution_id uuid, p_reason text)
returns uuid
language plpgsql as $$
declare
  c          contributions%rowtype;
  r          rounds%rowtype;
  v_against  uuid;
  v_id       uuid;
begin
  select * into c from contributions where id = p_contribution_id for update;
  if not found or not exists (select 1 from group_members where group_id = c.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Payment not found.');
  end if;
  select * into r from rounds where id = c.round_id;
  if p_user_id = r.collector_id then
    v_against := c.user_id;
  elsif p_user_id = c.user_id then
    v_against := r.collector_id;
  else
    perform sova_fail(403, 'not_party', 'Only the payer or the collector can dispute this payment.');
  end if;
  if c.status = 'disputed' then perform sova_fail(409, 'disputed', 'This payment is already under dispute.'); end if;
  if c.status = 'fully_confirmed' then perform sova_fail(409, 'already_confirmed', 'This payment is already confirmed.'); end if;
  if c.status <> 'payer_confirmed' then
    perform sova_fail(409, 'not_paid', 'Only a payment marked as sent can be disputed.');
  end if;

  insert into disputes (group_id, contribution_id, round_id, raised_by, against_user_id, reason, kind)
  values (c.group_id, c.id, r.id, p_user_id, v_against, p_reason, 'payment')
  returning id into v_id;
  insert into dispute_events (dispute_id, actor_id, kind, message) values (v_id, p_user_id, 'opened', p_reason);
  update contributions set status = 'disputed' where id = c.id;
  return v_id;
end $$;

-- A member who is neither payer nor collector votes; a strict majority of the
-- eligible voters decides. Returns the dispute's status afterwards.
create or replace function cast_dispute_vote(p_user_id uuid, p_dispute_id uuid, p_side text)
returns text
language plpgsql as $$
declare
  d           disputes%rowtype;
  v_eligible  int;
  v_count     int;
begin
  select * into d from disputes where id = p_dispute_id for update;
  if not found or not exists (select 1 from group_members where group_id = d.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Dispute not found.');
  end if;
  if d.status <> 'open' then perform sova_fail(409, 'dispute_closed', 'This dispute is already closed.'); end if;
  if d.kind <> 'payment' then
    perform sova_fail(409, 'no_vote', 'A shortfall closes when the missing payments are confirmed; there is nothing to vote on.');
  end if;
  if p_user_id = dispute_collector(d.id) or p_user_id in (select dispute_payers(d.id)) then
    perform sova_fail(403, 'party_cannot_vote', 'You are part of this dispute, so the other members decide it.');
  end if;
  if p_side not in ('payer', 'collector') then perform sova_fail(422, 'invalid_side', 'Choose a side.'); end if;

  insert into dispute_votes (dispute_id, voter_id, side) values (d.id, p_user_id, p_side)
  on conflict (dispute_id, voter_id) do update set side = excluded.side, updated_at = now()
  where dispute_votes.side <> excluded.side;

  v_eligible := dispute_eligible_voters(d.id);
  select count(*)::int into v_count from dispute_votes where dispute_id = d.id and side = p_side;
  if v_count * 2 > v_eligible then
    perform resolve_dispute(d.id, 'resolved_for_' || p_side, p_user_id,
                            format('Decided by the circle: %s of %s members voted that %s.', v_count, v_eligible,
                                   case p_side when 'payer' then 'the money arrived' else 'the money did not arrive' end));
  end if;
  return (select status from disputes where id = d.id);
end $$;

-- A party settles the dispute by agreeing with the other side: the collector
-- says the money arrived (or, for a shortfall, that it is settled), or the
-- payer agrees their payment did not arrive.
create or replace function concede_dispute(p_user_id uuid, p_dispute_id uuid)
returns text
language plpgsql as $$
declare
  d       disputes%rowtype;
  v_name  text;
begin
  select * into d from disputes where id = p_dispute_id for update;
  if not found or not exists (select 1 from group_members where group_id = d.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Dispute not found.');
  end if;
  if d.status <> 'open' then perform sova_fail(409, 'dispute_closed', 'This dispute is already closed.'); end if;
  select coalesce(split_part(full_name, ' ', 1), 'A member') into v_name from users where id = p_user_id;

  if p_user_id = dispute_collector(d.id) then
    perform resolve_dispute(d.id, 'resolved_for_payer', p_user_id,
      case d.kind when 'payment' then format('%s confirmed the money arrived.', v_name)
                  else format('%s marked the shortfall as settled.', v_name) end);
  elsif d.kind = 'payment' and p_user_id in (select dispute_payers(d.id)) then
    perform resolve_dispute(d.id, 'resolved_for_collector', p_user_id,
      format('%s agreed the payment did not arrive and can pay again.', v_name));
  else
    perform sova_fail(403, 'not_party', 'Only the payer or the collector can settle this dispute.');
  end if;
  return (select status from disputes where id = d.id);
end $$;

create or replace function add_dispute_comment(p_user_id uuid, p_dispute_id uuid, p_message text)
returns void
language plpgsql as $$
declare
  d  disputes%rowtype;
begin
  select * into d from disputes where id = p_dispute_id;
  if not found or not exists (select 1 from group_members where group_id = d.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Dispute not found.');
  end if;
  if d.status <> 'open' then perform sova_fail(409, 'dispute_closed', 'This dispute is already closed.'); end if;
  insert into dispute_events (dispute_id, actor_id, kind, message) values (d.id, p_user_id, 'comment', p_message);
end $$;

-- Ledger -------------------------------------------------------------------------

create or replace function ledger_on_dispute()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'dispute_opened', jsonb_build_object(
    'at', ledger_ts(new.created_at), 'turn', (select round_number from rounds where id = new.round_id),
    'raisedBy', ledger_who(new.raised_by), 'reason', new.reason, 'kind', new.kind,
    'payer', (select ledger_who(c.user_id) from contributions c where c.id = new.contribution_id)));
  return null;
end $$;

create or replace function ledger_on_dispute_resolved()
returns trigger
language plpgsql as $$
begin
  perform ledger_append(new.group_id, 'dispute_resolved', jsonb_build_object(
    'at', ledger_ts(coalesce(new.resolved_at, now())), 'turn', (select round_number from rounds where id = new.round_id),
    'outcome', case new.status when 'resolved_for_payer' then 'payer' when 'resolved_for_collector' then 'collector' else new.status end,
    'note', new.resolution_note));
  return null;
end $$;

drop trigger if exists ledger_dispute_resolved on disputes;
create trigger ledger_dispute_resolved after update of status on disputes
  for each row when (old.status = 'open' and new.status <> 'open') execute function ledger_on_dispute_resolved();

create or replace function ledger_on_dispute_vote()
returns trigger
language plpgsql as $$
declare
  d  disputes%rowtype;
begin
  select * into d from disputes where id = new.dispute_id;
  perform ledger_append(d.group_id, 'dispute_vote', jsonb_build_object(
    'at', ledger_ts(new.updated_at), 'turn', (select round_number from rounds where id = d.round_id),
    'voter', ledger_who(new.voter_id), 'side', new.side));
  return null;
end $$;

drop trigger if exists ledger_dispute_vote on dispute_votes;
create trigger ledger_dispute_vote after insert or update of side on dispute_votes
  for each row execute function ledger_on_dispute_vote();

-- A payment confirmed by the circle's decision says so in the ledger.
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
      'collector', ledger_who(v_collector), 'amount', new.amount)
      || case when tg_op = 'UPDATE' and old.status = 'disputed' then jsonb_build_object('decidedBy', 'dispute') else '{}'::jsonb end);
  end if;
  return null;
end $$;
