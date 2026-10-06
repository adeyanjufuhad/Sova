-- Phase 5: in-app notifications.
--
-- Triggers write a notification for each event that matters to a member:
-- a payment to confirm, a payment confirmed, a turn opening, a dispute that
-- needs a vote and its outcome, swap requests and answers, handover offers
-- and updates. Reminders about payments due soon are not stored: the API
-- works them out when the list is read, so no scheduler is needed.
--
-- Notifications carry an app link (e.g. /circle/<id>) so tapping one opens
-- the right screen. The demo seed sets sova.seeding = 'on' to write its own
-- history instead of a flood of "just now" notifications.

alter table notifications add column if not exists group_id uuid references groups(id) on delete cascade;
alter table notifications add column if not exists link text check (char_length(link) <= 200);
alter table notifications drop constraint if exists notifications_type_check;
alter table notifications add constraint notifications_type_check check (type in (
  'payment_due', 'payment_confirmed', 'reminder', 'dispute', 'group_update',
  'swap_request', 'handover_request', 'vouch', 'rules_updated', 'payout_shortfall',
  'payment_marked', 'turn_opened', 'dispute_vote', 'dispute_resolved', 'swap_answered', 'handover_update'
));
create index if not exists notifications_user_recent_idx on notifications (user_id, created_at desc);

create or replace function notify(p_user_id uuid, p_group_id uuid, p_type text, p_title text, p_message text, p_link text)
returns void
language plpgsql as $$
begin
  if coalesce(current_setting('sova.seeding', true), '') = 'on' or p_user_id is null then return; end if;
  insert into notifications (user_id, group_id, type, title, message, link)
  values (p_user_id, p_group_id, p_type, p_title, p_message, p_link);
end $$;

create or replace function first_name(p_user_id uuid)
returns text
language sql stable as $$
  select coalesce(nullif(split_part(full_name, ' ', 1), ''), 'A member') from users where id = p_user_id;
$$;

create or replace function naira(p_amount int)
returns text
language sql immutable as $$ select '₦' || to_char(p_amount, 'FM999,999,999,990') $$;

-- Payments ------------------------------------------------------------------------

create or replace function notify_on_contribution()
returns trigger
language plpgsql as $$
declare
  r  rounds%rowtype;
  g  groups%rowtype;
begin
  select * into r from rounds where id = new.round_id;
  select * into g from groups where id = new.group_id;
  if new.status = 'payer_confirmed' and (tg_op = 'INSERT' or old.status = 'pending') then
    perform notify(r.collector_id, g.id, 'payment_marked',
      format('%s marked %s as sent', first_name(new.user_id), naira(new.amount)),
      format('%s, turn %s. Check your bank, then confirm it arrived.', g.name, r.round_number),
      '/circle/' || g.id);
  elsif new.status = 'fully_confirmed' and tg_op = 'UPDATE' and old.status = 'payer_confirmed' then
    perform notify(new.user_id, g.id, 'payment_confirmed',
      format('%s confirmed your %s', first_name(r.collector_id), naira(new.amount)),
      format('%s, turn %s. Your receipt is ready.', g.name, r.round_number),
      '/circle/' || g.id || '/receipt/' || r.id);
  end if;
  return null;
end $$;

drop trigger if exists contributions_notify on contributions;
create trigger contributions_notify after insert or update of status on contributions
  for each row execute function notify_on_contribution();

-- Turns -----------------------------------------------------------------------------

create or replace function notify_on_round()
returns trigger
language plpgsql as $$
declare
  g  groups%rowtype;
  m  record;
begin
  if not (new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active')) then return null; end if;
  select * into g from groups where id = new.group_id;
  for m in select user_id from group_members where group_id = g.id loop
    if m.user_id = new.collector_id then
      perform notify(m.user_id, g.id, 'turn_opened',
        format('It''s your turn to collect %s', naira(g.contribution_amount * (g.member_count - 1))),
        format('%s, turn %s. Members pay you by %s.', g.name, new.round_number, to_char(new.due_date, 'Dy FMDD Mon')),
        '/circle/' || g.id);
    else
      perform notify(m.user_id, g.id, 'turn_opened',
        format('Turn %s: pay %s %s', new.round_number, first_name(new.collector_id), naira(g.contribution_amount)),
        format('%s. Due %s.', g.name, to_char(new.due_date, 'Dy FMDD Mon')),
        '/circle/' || g.id);
    end if;
  end loop;
  return null;
end $$;

drop trigger if exists rounds_notify on rounds;
create trigger rounds_notify after insert or update of status on rounds
  for each row execute function notify_on_round();

-- Disputes ----------------------------------------------------------------------------

create or replace function notify_on_dispute()
returns trigger
language plpgsql as $$
declare
  g        groups%rowtype;
  v_link   text;
  v_payer  uuid;
  m        record;
begin
  select * into g from groups where id = new.group_id;
  v_link := '/circle/' || g.id || '/disputes/' || new.id;

  if tg_op = 'INSERT' and new.kind = 'payment' then
    select user_id into v_payer from contributions where id = new.contribution_id;
    perform notify(new.against_user_id, g.id, 'dispute',
      format('%s disputed a payment', first_name(new.raised_by)),
      format('%s: "%s"', g.name, new.reason), v_link);
    for m in select user_id from group_members
              where group_id = g.id and user_id <> dispute_collector(new.id) and user_id <> v_payer loop
      perform notify(m.user_id, g.id, 'dispute_vote', 'Your vote is needed',
        format('%s: did %s''s payment reach %s?', g.name, first_name(v_payer), first_name(dispute_collector(new.id))),
        v_link);
    end loop;
  elsif tg_op = 'INSERT' and new.kind = 'shortfall' then
    for m in select dispute_payers(new.id) as user_id loop
      perform notify(m.user_id, g.id, 'payout_shortfall', 'A payout came up short',
        format('%s: your payment for this turn is missing. Pay it late and ask the collector to confirm.', g.name), v_link);
    end loop;
  elsif tg_op = 'UPDATE' and old.status = 'open' and new.status <> 'open' then
    for m in select distinct u from unnest(array[new.raised_by, new.against_user_id, dispute_collector(new.id)]) u where u is not null loop
      perform notify(m.u, g.id, 'dispute_resolved', 'A dispute was closed', format('%s: %s', g.name, new.resolution_note), v_link);
    end loop;
  end if;
  return null;
end $$;

drop trigger if exists disputes_notify on disputes;
create trigger disputes_notify after insert or update of status on disputes
  for each row execute function notify_on_dispute();

-- Swaps and handovers ----------------------------------------------------------------

create or replace function notify_on_swap()
returns trigger
language plpgsql as $$
declare
  v_link  text := '/circle/' || new.group_id || '/turns';
  v_name  text := (select name from groups where id = new.group_id);
begin
  if tg_op = 'INSERT' then
    perform notify(new.target_id, new.group_id, 'swap_request',
      format('%s asks to swap turns with you', first_name(new.requester_id)), v_name, v_link);
  elsif old.status = 'pending' and new.status in ('accepted', 'declined') then
    perform notify(new.requester_id, new.group_id, 'swap_answered',
      format('%s %s your swap', first_name(new.target_id), new.status), v_name, v_link);
  end if;
  return null;
end $$;

drop trigger if exists swap_requests_notify on swap_requests;
create trigger swap_requests_notify after insert or update of status on swap_requests
  for each row execute function notify_on_swap();

create or replace function notify_on_handover()
returns trigger
language plpgsql as $$
declare
  g  groups%rowtype;
begin
  select * into g from groups where id = new.group_id;
  if tg_op = 'INSERT' then
    perform notify(new.replacement_user_id, g.id, 'handover_request',
      format('%s offered you a place', first_name(new.leaving_user_id)),
      format('In %s. See the rules and decide.', g.name), '/handover/' || new.id);
  elsif old.status = 'pending' and new.status = 'accepted' then
    perform notify(g.admin_id, g.id, 'handover_request', 'A handover needs your approval',
      format('%s: %s would take %s''s place.', g.name, first_name(new.replacement_user_id), first_name(new.leaving_user_id)),
      '/circle/' || g.id || '/turns');
    perform notify(new.leaving_user_id, g.id, 'handover_update',
      format('%s accepted your place', first_name(new.replacement_user_id)), format('%s. Waiting for the admin.', g.name),
      '/circle/' || g.id || '/turns');
  elsif new.status in ('declined', 'rejected') and old.status <> new.status then
    perform notify(new.leaving_user_id, g.id, 'handover_update',
      case new.status when 'declined' then format('%s declined your place', first_name(new.replacement_user_id))
                      else 'The admin did not approve your handover' end,
      g.name, '/circle/' || g.id || '/turns');
  elsif new.status = 'completed' and old.status <> 'completed' then
    perform notify(new.replacement_user_id, g.id, 'handover_update', format('Welcome to %s', g.name),
      format('You now hold turn %s.', new.position), '/circle/' || g.id);
  end if;
  return null;
end $$;

drop trigger if exists handover_requests_notify on handover_requests;
create trigger handover_requests_notify after insert or update of status on handover_requests
  for each row execute function notify_on_handover();

-- Changing a PIN needs the current one (checked by the API); this keeps the
-- lockout counters honest after a successful change.
create or replace function change_pin(p_user_id uuid, p_new_hash text)
returns void
language sql as $$
  update users set pin_hash = p_new_hash where id = p_user_id;
  select reset_pin_attempts(p_user_id);
$$;
