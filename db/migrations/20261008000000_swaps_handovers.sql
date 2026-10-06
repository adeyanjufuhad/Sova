-- Phase 4: swapping turns and handing over a place.
--
-- Swaps: a member asks another member to trade payout turns. Both turns must
-- not have started. The other member accepts (or declines); the asker can
-- cancel. An admin who pledged to collect last can't swap away from last.
--
-- Handovers: a member who hasn't collected yet hands their place to someone
-- outside the circle. Three steps: the leaving member names the replacement,
-- the replacement accepts the circle's rules, the admin approves. The change
-- takes effect when the current turn ends (straight away if the circle hasn't
-- started), so nobody's payment for the turn in progress is confused. The
-- admin can't hand over their own place in this version.
--
-- Pending requests that involve a turn that has just started are cancelled.
-- Every swap and handover goes into the circle's ledger.

drop function if exists accept_swap(uuid, uuid);
drop function if exists approve_handover(uuid, uuid);

create unique index if not exists swap_requests_one_pending_idx
  on swap_requests (group_id, requester_id) where status = 'pending';

-- pending: waiting for the replacement; accepted: waiting for the admin;
-- approved: takes effect when the current turn ends; completed: done.
alter table handover_requests drop constraint if exists handover_requests_status_check;
alter table handover_requests add constraint handover_requests_status_check
  check (status in ('pending', 'accepted', 'approved', 'completed', 'declined', 'rejected', 'cancelled'));
alter table handover_requests add column if not exists responded_at timestamptz;
alter table handover_requests add column if not exists completed_at timestamptz;
alter table handover_requests add column if not exists position int;
create unique index if not exists handover_requests_one_open_idx
  on handover_requests (group_id, leaving_user_id) where status in ('pending', 'accepted', 'approved');

-- A turn is open while its round hasn't started (positions are null before the draw).
create or replace function position_is_open(p_group_id uuid, p_position int)
returns boolean
language sql stable as $$
  select p_position is null or not exists (
    select 1 from rounds
     where group_id = p_group_id and round_number = p_position and status in ('active', 'completed')
  );
$$;

-- Swaps -------------------------------------------------------------------------

create or replace function request_swap(p_user_id uuid, p_group_id uuid, p_target_id uuid, p_reason text)
returns uuid
language plpgsql as $$
declare
  g      groups%rowtype;
  pos_a  int;
  pos_b  int;
  v_id   uuid;
begin
  select * into g from groups where id = p_group_id;
  if not found or not exists (select 1 from group_members where group_id = p_group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Circle not found.');
  end if;
  if g.status <> 'active' then perform sova_fail(409, 'not_active', 'Turns can only be swapped once the circle has started.'); end if;
  if p_target_id = p_user_id then perform sova_fail(422, 'same_member', 'Choose another member.'); end if;
  select payout_position into pos_a from group_members where group_id = p_group_id and user_id = p_user_id;
  select payout_position into pos_b from group_members where group_id = p_group_id and user_id = p_target_id;
  if pos_b is null and not exists (select 1 from group_members where group_id = p_group_id and user_id = p_target_id) then
    perform sova_fail(404, 'not_member', 'That person is not in this circle.');
  end if;
  if g.admin_collects_last and g.admin_id in (p_user_id, p_target_id) then
    perform sova_fail(409, 'pledged_last', 'The admin pledged to collect last, so their turn can''t be swapped.');
  end if;
  if not position_is_open(p_group_id, pos_a) then
    perform sova_fail(409, 'turn_started', 'Your turn has already started, so it can''t be swapped.');
  end if;
  if not position_is_open(p_group_id, pos_b) then
    perform sova_fail(409, 'turn_started', 'Their turn has already started, so it can''t be swapped.');
  end if;
  if exists (select 1 from swap_requests where group_id = p_group_id and requester_id = p_user_id and status = 'pending') then
    perform sova_fail(409, 'already_asked', 'You already have a swap request waiting. Cancel it first.');
  end if;
  insert into swap_requests (group_id, requester_id, target_id, reason)
  values (p_group_id, p_user_id, p_target_id, nullif(trim(p_reason), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function respond_swap(p_user_id uuid, p_swap_id uuid, p_accept boolean)
returns text
language plpgsql as $$
declare
  s      swap_requests%rowtype;
  pos_a  int;
  pos_b  int;
begin
  select * into s from swap_requests where id = p_swap_id for update;
  if not found or not exists (select 1 from group_members where group_id = s.group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Swap request not found.');
  end if;
  if s.target_id <> p_user_id then perform sova_fail(403, 'not_target', 'Only the member who was asked can answer.'); end if;
  if s.status <> 'pending' then perform sova_fail(409, 'not_pending', 'This request has already been answered.'); end if;

  if not p_accept then
    update swap_requests set status = 'declined', responded_at = now() where id = s.id;
    return 'declined';
  end if;

  select payout_position into pos_a from group_members where group_id = s.group_id and user_id = s.requester_id for update;
  select payout_position into pos_b from group_members where group_id = s.group_id and user_id = s.target_id for update;
  if pos_a is null or pos_b is null then perform sova_fail(409, 'not_member', 'Both people must still be in the circle.'); end if;
  if not position_is_open(s.group_id, pos_a) or not position_is_open(s.group_id, pos_b) then
    perform sova_fail(409, 'turn_started', 'One of these turns has already started.');
  end if;
  -- The unique position constraint is deferred, so a direct swap is fine.
  update group_members set payout_position = pos_b where group_id = s.group_id and user_id = s.requester_id;
  update group_members set payout_position = pos_a where group_id = s.group_id and user_id = s.target_id;
  update swap_requests set status = 'accepted', responded_at = now() where id = s.id;
  perform ledger_append(s.group_id, 'turns_swapped', jsonb_build_object(
    'at', ledger_ts(now()),
    'a', ledger_who(s.requester_id) || jsonb_build_object('turn', pos_b),
    'b', ledger_who(s.target_id) || jsonb_build_object('turn', pos_a)));
  return 'accepted';
end $$;

create or replace function cancel_swap(p_user_id uuid, p_swap_id uuid)
returns void
language plpgsql as $$
declare
  s  swap_requests%rowtype;
begin
  select * into s from swap_requests where id = p_swap_id for update;
  if not found or s.requester_id <> p_user_id then perform sova_fail(404, 'not_found', 'Swap request not found.'); end if;
  if s.status <> 'pending' then perform sova_fail(409, 'not_pending', 'This request has already been answered.'); end if;
  update swap_requests set status = 'cancelled', responded_at = now() where id = s.id;
end $$;

-- Handovers ---------------------------------------------------------------------

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
  select payout_position into v_pos from group_members where group_id = p_group_id and user_id = p_user_id;
  if not position_is_open(p_group_id, v_pos) then
    perform sova_fail(409, 'turn_started', 'You have already collected or are collecting, so you need to finish the cycle.');
  end if;
  select id into v_repl from users where phone = p_phone and full_name is not null;
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

-- The replacement answers. Accepting means accepting the circle's current rules.
create or replace function respond_handover(p_user_id uuid, p_handover_id uuid, p_accept boolean, p_rules_version int)
returns text
language plpgsql as $$
declare
  h  handover_requests%rowtype;
begin
  select * into h from handover_requests where id = p_handover_id for update;
  if not found or h.replacement_user_id <> p_user_id then perform sova_fail(404, 'not_found', 'Handover not found.'); end if;
  if h.status <> 'pending' then perform sova_fail(409, 'not_pending', 'This handover has already been answered.'); end if;
  if not p_accept then
    update handover_requests set status = 'declined', responded_at = now() where id = h.id;
    return 'declined';
  end if;
  if (select version from group_rules where group_id = h.group_id order by version desc limit 1) is distinct from p_rules_version then
    perform sova_fail(409, 'rules_changed', 'The rules changed while you were reading. Please read them again.');
  end if;
  update handover_requests set status = 'accepted', responded_at = now() where id = h.id;
  return 'accepted';
end $$;

-- Moves the place from the leaving member to the replacement, keeping the turn.
create or replace function complete_handover(p_handover_id uuid)
returns void
language plpgsql as $$
declare
  h      handover_requests%rowtype;
  v_pos  int;
begin
  select * into h from handover_requests where id = p_handover_id for update;
  select payout_position into v_pos from group_members where group_id = h.group_id and user_id = h.leaving_user_id;
  delete from group_members where group_id = h.group_id and user_id = h.leaving_user_id;
  insert into group_members (group_id, user_id, payout_position) values (h.group_id, h.replacement_user_id, v_pos);
  insert into vouches (group_id, voucher_id, vouchee_id) values (h.group_id, h.leaving_user_id, h.replacement_user_id)
  on conflict (group_id, vouchee_id) do nothing;
  insert into rule_acceptances (rules_id, user_id)
  select r.id, h.replacement_user_id from group_rules r where r.group_id = h.group_id order by r.version desc limit 1
  on conflict do nothing;
  update handover_requests set status = 'completed', completed_at = now(), position = v_pos where id = h.id;
  -- Swaps the leaving member asked for, or was asked for, no longer make sense.
  update swap_requests set status = 'cancelled', responded_at = now()
   where group_id = h.group_id and status = 'pending' and h.leaving_user_id in (requester_id, target_id);
  perform ledger_append(h.group_id, 'slot_handed_over', jsonb_build_object(
    'at', ledger_ts(now()), 'turn', v_pos,
    'leaving', ledger_who(h.leaving_user_id), 'replacement', ledger_who(h.replacement_user_id)));
end $$;

-- The admin decides. Approved handovers take effect when the current turn ends,
-- or straight away while the circle is still forming.
create or replace function decide_handover(p_user_id uuid, p_handover_id uuid, p_approve boolean)
returns text
language plpgsql as $$
declare
  h  handover_requests%rowtype;
  g  groups%rowtype;
begin
  select * into h from handover_requests where id = p_handover_id for update;
  if not found then perform sova_fail(404, 'not_found', 'Handover not found.'); end if;
  select * into g from groups where id = h.group_id;
  if g.admin_id <> p_user_id then
    if exists (select 1 from group_members where group_id = h.group_id and user_id = p_user_id) then
      perform sova_fail(403, 'not_admin', 'Only the admin can approve a handover.');
    end if;
    perform sova_fail(404, 'not_found', 'Handover not found.');
  end if;
  if h.status <> 'accepted' then
    perform sova_fail(409, 'not_ready', 'The replacement has to accept before you can decide.');
  end if;
  if not p_approve then
    update handover_requests set status = 'rejected', decided_by = p_user_id, decided_at = now() where id = h.id;
    return 'rejected';
  end if;
  if not position_is_open(h.group_id, (select payout_position from group_members
                                        where group_id = h.group_id and user_id = h.leaving_user_id)) then
    perform sova_fail(409, 'turn_started', 'Their turn has already started, so they need to finish the cycle.');
  end if;
  update handover_requests set status = 'approved', decided_by = p_user_id, decided_at = now() where id = h.id;
  if g.status = 'forming' then
    perform complete_handover(h.id);
    return 'completed';
  end if;
  return 'approved';
end $$;

create or replace function cancel_handover(p_user_id uuid, p_handover_id uuid)
returns void
language plpgsql as $$
declare
  h  handover_requests%rowtype;
begin
  select * into h from handover_requests where id = p_handover_id for update;
  if not found or h.leaving_user_id <> p_user_id then perform sova_fail(404, 'not_found', 'Handover not found.'); end if;
  if h.status not in ('pending', 'accepted', 'approved') then
    perform sova_fail(409, 'not_pending', 'This handover can no longer be cancelled.');
  end if;
  update handover_requests set status = 'cancelled', decided_at = now() where id = h.id;
end $$;

-- When a turn ends, approved handovers take effect before the next collector is
-- chosen (force_advance_round completes the old turn, then reads positions).
-- When a turn starts, pending requests involving its collector are cancelled.
create or replace function turn_changes_on_round()
returns trigger
language plpgsql as $$
declare
  v_id  uuid;
begin
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    for v_id in select id from handover_requests where group_id = new.group_id and status = 'approved' order by decided_at loop
      perform complete_handover(v_id);
    end loop;
  end if;
  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active') then
    update swap_requests set status = 'cancelled', responded_at = now()
     where group_id = new.group_id and status = 'pending' and new.collector_id in (requester_id, target_id);
    update handover_requests set status = 'cancelled', decided_at = now()
     where group_id = new.group_id and status in ('pending', 'accepted', 'approved') and leaving_user_id = new.collector_id;
  end if;
  return null;
end $$;

drop trigger if exists rounds_turn_changes on rounds;
create trigger rounds_turn_changes after insert or update of status on rounds
  for each row execute function turn_changes_on_round();
