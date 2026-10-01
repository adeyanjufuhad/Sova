-- Trust features: group rules, vouching, proof of payment, payout receipts,
-- swap requests, slot handover and disputes.

-- Group rules -----------------------------------------------------------------
-- Rules are versioned; members accept a specific version. Changing the rules
-- means a new version that everyone accepts again.
create table if not exists group_rules (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null references groups(id) on delete cascade,
  version            int not null check (version > 0),
  late_fee           int not null default 0 check (late_fee >= 0),           -- naira per late payment
  grace_days         int not null default 0 check (grace_days between 0 and 30),
  early_exit_policy  text not null default 'find_replacement'
                     check (early_exit_policy in ('find_replacement', 'refund_after_cycle', 'forfeit_fee')),
  emergency_policy   text check (char_length(emergency_policy) <= 1000),     -- sickness, death, travel
  other_rules        text check (char_length(other_rules) <= 2000),
  created_by         uuid not null references users(id),
  created_at         timestamptz not null default now(),
  unique (group_id, version)
);

create table if not exists rule_acceptances (
  rules_id     uuid not null references group_rules(id) on delete cascade,
  user_id      uuid not null references users(id) on delete cascade,
  accepted_at  timestamptz not null default now(),
  primary key (rules_id, user_id)
);

-- Vouching --------------------------------------------------------------------
-- An existing member vouches for a newcomer. If the newcomer defaults after
-- collecting, the vouch is marked 'defaulted' and shows on the voucher's record.
create table if not exists vouches (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  voucher_id  uuid not null references users(id) on delete cascade,
  vouchee_id  uuid not null references users(id) on delete cascade,
  status      text not null default 'active' check (status in ('active', 'honoured', 'defaulted')),
  created_at  timestamptz not null default now(),
  unique (group_id, vouchee_id),
  check (voucher_id <> vouchee_id)
);
create index if not exists vouches_voucher_idx on vouches (voucher_id);

-- Proof of payment ------------------------------------------------------------
alter table contributions add column if not exists proof_url text;
alter table contributions add column if not exists bank_reference text check (char_length(bank_reference) <= 60);

-- Payout receipt --------------------------------------------------------------
-- The collector of a round confirms how much actually reached them.
alter table rounds add column if not exists payout_received int check (payout_received >= 0);
alter table rounds add column if not exists payout_confirmed_at timestamptz;

-- Swap requests ---------------------------------------------------------------
create table if not exists swap_requests (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  requester_id  uuid not null references users(id) on delete cascade,
  target_id     uuid not null references users(id) on delete cascade,
  reason        text check (char_length(reason) <= 500),
  status        text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  check (requester_id <> target_id)
);
create index if not exists swap_requests_group_idx on swap_requests (group_id) where status = 'pending';

-- Slot handover ---------------------------------------------------------------
create table if not exists handover_requests (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references groups(id) on delete cascade,
  leaving_user_id      uuid not null references users(id) on delete cascade,
  replacement_user_id  uuid not null references users(id) on delete cascade,
  reason               text check (char_length(reason) <= 500),
  status               text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by           uuid references users(id),
  created_at           timestamptz not null default now(),
  decided_at           timestamptz,
  check (leaving_user_id <> replacement_user_id)
);

-- Disputes --------------------------------------------------------------------
create table if not exists disputes (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references groups(id) on delete cascade,
  contribution_id  uuid references contributions(id) on delete set null,
  round_id         uuid references rounds(id) on delete set null,
  raised_by        uuid not null references users(id),
  against_user_id  uuid references users(id),
  reason           text not null check (char_length(reason) between 3 and 1000),
  status           text not null default 'open'
                   check (status in ('open', 'resolved_for_payer', 'resolved_for_collector', 'withdrawn')),
  resolution_note  text,
  resolved_by      uuid references users(id),
  created_at       timestamptz not null default now(),
  resolved_at      timestamptz
);
create index if not exists disputes_group_open_idx on disputes (group_id) where status = 'open';

-- Timeline of everything that happened in a dispute.
create table if not exists dispute_events (
  id              uuid primary key default gen_random_uuid(),
  dispute_id      uuid not null references disputes(id) on delete cascade,
  actor_id        uuid not null references users(id),
  kind            text not null check (kind in ('opened', 'evidence', 'comment', 'resolved', 'withdrawn')),
  message         text check (char_length(message) <= 1000),
  attachment_url  text,
  created_at      timestamptz not null default now()
);
create index if not exists dispute_events_dispute_idx on dispute_events (dispute_id, created_at);

-- New notification types -------------------------------------------------------
alter table notifications drop constraint if exists notifications_type_check;
alter table notifications add constraint notifications_type_check check (type in (
  'payment_due', 'payment_confirmed', 'reminder', 'dispute', 'group_update',
  'swap_request', 'handover_request', 'vouch', 'rules_updated', 'payout_shortfall'
));

-- Functions -------------------------------------------------------------------

-- Positions whose round hasn't started yet can be swapped or handed over.
create or replace function position_is_open(p_group_id uuid, p_position int)
returns boolean
language sql stable as $$
  select not exists (
    select 1 from rounds
     where group_id = p_group_id and round_number = p_position and status in ('active', 'completed')
  );
$$;

-- The target member accepts a swap: the two members trade payout positions.
create or replace function accept_swap(p_swap_id uuid, p_user_id uuid)
returns void
language plpgsql as $$
declare
  s      swap_requests%rowtype;
  pos_a  int;
  pos_b  int;
begin
  select * into s from swap_requests where id = p_swap_id for update;
  if not found then raise exception 'swap request not found'; end if;
  if s.status <> 'pending' then raise exception 'swap request is %', s.status; end if;
  if s.target_id <> p_user_id then raise exception 'only the asked member can accept'; end if;

  select payout_position into pos_a from group_members where group_id = s.group_id and user_id = s.requester_id for update;
  select payout_position into pos_b from group_members where group_id = s.group_id and user_id = s.target_id for update;
  if pos_a is null or pos_b is null then raise exception 'both people must be members of the group'; end if;
  if not position_is_open(s.group_id, pos_a) or not position_is_open(s.group_id, pos_b) then
    raise exception 'one of these turns has already started';
  end if;

  -- the unique (group_id, payout_position) constraint is deferred, so a direct swap is fine
  update group_members set payout_position = pos_b where group_id = s.group_id and user_id = s.requester_id;
  update group_members set payout_position = pos_a where group_id = s.group_id and user_id = s.target_id;

  update swap_requests set status = 'accepted', responded_at = now() where id = p_swap_id;
end $$;

-- The group admin approves a handover: the replacement takes the leaving
-- member's place and payout position.
create or replace function approve_handover(p_handover_id uuid, p_admin_id uuid)
returns void
language plpgsql as $$
declare
  h    handover_requests%rowtype;
  pos  int;
begin
  select * into h from handover_requests where id = p_handover_id for update;
  if not found then raise exception 'handover request not found'; end if;
  if h.status <> 'pending' then raise exception 'handover request is %', h.status; end if;
  if not exists (select 1 from groups where id = h.group_id and admin_id = p_admin_id) then
    raise exception 'only the group admin can approve a handover';
  end if;

  select payout_position into pos from group_members
   where group_id = h.group_id and user_id = h.leaving_user_id for update;
  if pos is null then raise exception 'the leaving member is not in this group'; end if;
  if not position_is_open(h.group_id, pos) then
    raise exception 'the leaving member has already collected or is collecting; they must finish the cycle';
  end if;

  update group_members set user_id = h.replacement_user_id, joined_at = now()
   where group_id = h.group_id and user_id = h.leaving_user_id;

  update handover_requests set status = 'approved', decided_by = p_admin_id, decided_at = now()
   where id = p_handover_id;
end $$;

-- The round's collector confirms what they received. Returns the shortfall
-- (0 when complete). Expected = sum of fully confirmed contributions.
create or replace function confirm_payout(p_round_id uuid, p_user_id uuid, p_amount int)
returns int
language plpgsql as $$
declare
  r         rounds%rowtype;
  expected  int;
begin
  select * into r from rounds where id = p_round_id for update;
  if not found then raise exception 'round not found'; end if;
  if r.collector_id <> p_user_id then raise exception 'only this round''s collector can confirm the payout'; end if;

  select coalesce(sum(amount), 0) into expected
    from contributions where round_id = p_round_id and status = 'fully_confirmed';

  update rounds set payout_received = p_amount, payout_confirmed_at = now() where id = p_round_id;
  return greatest(expected - p_amount, 0);
end $$;

-- Members who collected their payout and then missed a later contribution
-- that is past its due date. Used for the payout guard and for vouches.
create or replace view unfinished_obligations as
select distinct on (gm.group_id, gm.user_id)
       gm.group_id,
       gm.user_id,
       r.round_number as missed_round,
       r.due_date     as missed_due_date
  from group_members gm
  join rounds collected on collected.group_id = gm.group_id
                       and collected.collector_id = gm.user_id
                       and collected.status in ('active', 'completed')
  join rounds r on r.group_id = gm.group_id
               and r.round_number > collected.round_number
               and r.status in ('active', 'completed')
               and r.collector_id <> gm.user_id
               and r.due_date < current_date
  left join contributions c on c.round_id = r.id and c.user_id = gm.user_id and c.status = 'fully_confirmed'
 where c.id is null
 order by gm.group_id, gm.user_id, r.round_number;
