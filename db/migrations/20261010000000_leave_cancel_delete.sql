-- Ways out: leaving a circle that hasn't started, cancelling one, and
-- deleting your account.
--
-- Leaving: while a circle is still forming, any member except the admin can
-- leave. Their place opens up again (the invite code keeps working) and the
-- ledger records it. Once the turns are drawn, the way out is a handover.
--
-- Cancelling: the admin can cancel a circle that is still forming. It moves
-- to 'cancelled' (never deleted: a circle with a ledger can't be), the invite
-- code stops working, and the ledger records it.
--
-- Deleting an account: allowed when every circle you're in has finished or
-- was cancelled (circles still forming are left for you; an admin cancels
-- theirs first). Your name, phone, PIN, bank details, sessions, sign-in codes,
-- notifications, score history and score links are removed. The row itself
-- stays as an empty shell, because payments and turns in finished circles
-- point at it; the ledger keeps the first name and initial it already holds,
-- because entries can't be changed. Receipt photos are deleted by the API.

alter table groups drop constraint if exists groups_status_check;
alter table groups add constraint groups_status_check
  check (status in ('forming', 'active', 'paused', 'completed', 'cancelled'));
alter table groups add column if not exists cancelled_at timestamptz;

-- A deleted account keeps its id but no phone number, so the number can sign up again.
alter table users alter column phone drop not null;
alter table users add column if not exists deleted_at timestamptz;

-- Leaving -------------------------------------------------------------------------

create or replace function leave_circle(p_user_id uuid, p_group_id uuid)
returns void
language plpgsql as $$
declare
  g  groups%rowtype;
begin
  select * into g from groups where id = p_group_id for update;
  if not found or not exists (select 1 from group_members where group_id = p_group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Circle not found.');
  end if;
  if g.admin_id = p_user_id then
    perform sova_fail(409, 'admin_cannot_leave', 'You started this circle, so you can cancel it instead of leaving.');
  end if;
  if g.status <> 'forming' then
    perform sova_fail(409, 'circle_started',
      'The turns have been drawn, so you can''t just leave. Hand your place to someone the admin approves.');
  end if;

  -- Their acceptance and vouches go with them, so they can join again later.
  delete from rule_acceptances a using group_rules r
   where r.id = a.rules_id and r.group_id = p_group_id and a.user_id = p_user_id;
  delete from vouches where group_id = p_group_id and p_user_id in (voucher_id, vouchee_id);
  update handover_requests set status = 'cancelled', decided_at = now()
   where group_id = p_group_id and status in ('pending', 'accepted', 'approved')
     and p_user_id in (leaving_user_id, replacement_user_id);
  delete from group_members where group_id = p_group_id and user_id = p_user_id;

  perform ledger_append(p_group_id, 'member_left',
    jsonb_build_object('at', ledger_ts(now()), 'member', ledger_who(p_user_id)));
  perform notify(g.admin_id, g.id, 'group_update',
    format('%s left %s', first_name(p_user_id), g.name),
    'Their place is open again. Share the invite code to fill it.',
    '/circle/' || g.id);
end $$;

-- Cancelling ----------------------------------------------------------------------

create or replace function cancel_circle(p_user_id uuid, p_group_id uuid)
returns void
language plpgsql as $$
declare
  g  groups%rowtype;
  m  record;
begin
  select * into g from groups where id = p_group_id for update;
  if not found or not exists (select 1 from group_members where group_id = p_group_id and user_id = p_user_id) then
    perform sova_fail(404, 'not_found', 'Circle not found.');
  end if;
  if g.admin_id <> p_user_id then perform sova_fail(403, 'not_admin', 'Only the admin can cancel the circle.'); end if;
  if g.status <> 'forming' then
    perform sova_fail(409, 'circle_started', 'The circle has started, so it runs until every turn is paid out.');
  end if;

  update handover_requests set status = 'cancelled', decided_at = now()
   where group_id = p_group_id and status in ('pending', 'accepted', 'approved');
  update groups set status = 'cancelled', cancelled_at = now() where id = p_group_id;  -- the ledger trigger records it

  for m in select user_id from group_members where group_id = p_group_id and user_id <> p_user_id loop
    perform notify(m.user_id, g.id, 'group_update',
      format('%s was cancelled', g.name),
      format('%s cancelled the circle before it started. Nobody paid anything into it.', first_name(p_user_id)),
      '/circle/' || g.id);
  end loop;
end $$;

-- The ledger records a cancelled circle, as it does a completed one.
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
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    perform ledger_append(new.id, 'circle_cancelled',
      jsonb_build_object('at', ledger_ts(now()), 'by', ledger_who(new.admin_id)));
  end if;
  return null;
end $$;

-- Joining refuses a cancelled circle with its own message (otherwise as before).
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

-- A cancelled circle is neither in progress nor finished for the Sova Score
-- (otherwise as in 20261007000000_sova_score.sql).
create or replace function sova_score_now(p_user_id uuid)
returns table (
  score_value        int,
  on_time_rate       numeric,
  consistency_rate   numeric,
  completion_rate    numeric,
  active_cycles      int,
  completed_cycles   int,
  confirmed_payments int,
  on_time_payments   int,
  turns_counted      int
)
language plpgsql stable as $$
declare
  v_turns  int;
  v_made   int;
begin
  select count(*)::int,
         count(*) filter (where c.payer_confirmed_at::date <= r.due_date)::int
    into confirmed_payments, on_time_payments
    from contributions c join rounds r on r.id = c.round_id
   where c.user_id = p_user_id and c.status = 'fully_confirmed';

  select count(*)::int,
         count(c.id) filter (where c.status in ('payer_confirmed', 'fully_confirmed'))::int
    into v_turns, v_made
    from rounds r
    join group_members gm on gm.group_id = r.group_id and gm.user_id = p_user_id
    left join contributions c on c.round_id = r.id and c.user_id = p_user_id
   where r.collector_id <> p_user_id
     and (r.status = 'completed' or (r.status = 'active' and r.due_date < current_date));

  select count(*) filter (where g.status not in ('completed', 'forming', 'cancelled'))::int,
         count(*) filter (where g.status = 'completed')::int
    into active_cycles, completed_cycles
    from group_members gm join groups g on g.id = gm.group_id
   where gm.user_id = p_user_id;

  turns_counted    := v_turns;
  on_time_rate     := case when confirmed_payments > 0 then on_time_payments::numeric / confirmed_payments else 0 end;
  consistency_rate := case when v_turns > 0 then v_made::numeric / v_turns else 0 end;
  completion_rate  := case when active_cycles + completed_cycles > 0
                           then completed_cycles::numeric / (active_cycles + completed_cycles) else 0 end;
  score_value      := round(100 * (0.60 * on_time_rate + 0.25 * consistency_rate + 0.15 * completion_rate));
  return next;
end $$;

-- Deleting an account ----------------------------------------------------------------

create or replace function delete_account(p_user_id uuid)
returns void
language plpgsql as $$
declare
  u  users%rowtype;
  g  record;
begin
  select * into u from users where id = p_user_id for update;
  if not found or u.deleted_at is not null then perform sova_fail(404, 'not_found', 'Account not found.'); end if;
  if u.is_demo then
    perform sova_fail(403, 'demo_account', 'This is the shared demo account, so it can''t be deleted.');
  end if;

  select gr.name into g from groups gr
   where gr.admin_id = p_user_id and gr.status = 'forming' order by gr.created_at limit 1;
  if found then
    perform sova_fail(409, 'admin_of_forming',
      format('You started %s, which hasn''t begun yet. Cancel it first.', g.name));
  end if;
  select gr.name into g from groups gr join group_members m on m.group_id = gr.id and m.user_id = p_user_id
   where gr.status in ('active', 'paused') order by gr.created_at limit 1;
  if found then
    perform sova_fail(409, 'circle_in_progress',
      format('You''re in %s, which is still running. You can delete your account once every circle you''re in has finished.', g.name));
  end if;

  for g in select gr.id from groups gr join group_members m on m.group_id = gr.id and m.user_id = p_user_id
            where gr.status = 'forming' loop
    perform leave_circle(p_user_id, g.id);
  end loop;

  update handover_requests set status = 'cancelled', decided_at = now()
   where status in ('pending', 'accepted', 'approved') and p_user_id in (leaving_user_id, replacement_user_id);
  update contributions set proof_url = null where user_id = p_user_id and proof_url is not null;
  delete from sessions where user_id = p_user_id;
  delete from otp_challenges where phone = u.phone;
  delete from waitlist where phone = u.phone;
  delete from notifications where user_id = p_user_id;
  delete from scores where user_id = p_user_id;
  delete from score_shares where user_id = p_user_id;

  update users
     set phone = null, full_name = null, avatar_url = null, pin_hash = null,
         pin_failed_attempts = 0, pin_locked_until = null,
         bank_name = null, account_number = null, account_name = null, push_token = null,
         deleted_at = now()
   where id = p_user_id;
end $$;
