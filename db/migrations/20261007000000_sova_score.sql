-- Phase 4: the Sova Score card.
--
-- The score keeps the v1 formula (60% on time, 25% consistency, 15% completion),
-- now computed by one pure function so the API can show it live without
-- writing a row on every read. Two fixes to what counts:
--   * consistency only looks at turns that are over (completed, or past their
--     due date): a turn that isn't due yet no longer counts as a missed payment;
--   * a payment only counts as made when it was sent or confirmed, so a
--     payment sent back to unpaid by a dispute no longer counts.
-- A score is shown only after a minimum of confirmed payments, so a new
-- member isn't labelled with a meaningless low number.
--
-- Sharing: a member can publish a snapshot of their score behind a random
-- link. The snapshot holds only first name + initial, the score and counts;
-- never phone numbers, circle names or amounts. One live link at a time;
-- sharing again replaces it, and the member can stop sharing.

create or replace function sova_score_min_payments()
returns int
language sql immutable as $$ select 3 $$;

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

  select count(*) filter (where g.status not in ('completed', 'forming'))::int,
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

-- Same signature as before (close_round, resolve_dispute and the seed call it):
-- records a history row and returns the score.
create or replace function calculate_sova_score(p_user_id uuid)
returns int
language plpgsql as $$
declare
  s  record;
begin
  select * into s from sova_score_now(p_user_id);
  insert into scores (user_id, score_value, on_time_rate, consistency_rate, completion_rate, active_cycles, completed_cycles)
  values (p_user_id, s.score_value, s.on_time_rate, s.consistency_rate, s.completion_rate, s.active_cycles, s.completed_cycles);
  return s.score_value;
end $$;

create table if not exists score_shares (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references users(id) on delete cascade,
  token               text not null unique check (token ~ '^[A-Za-z0-9_-]{22,64}$'),
  display_name        text not null,
  score_value         int not null check (score_value between 0 and 100),
  on_time_rate        numeric(5, 4) not null,
  consistency_rate    numeric(5, 4) not null,
  completion_rate     numeric(5, 4) not null,
  confirmed_payments  int not null,
  completed_cycles    int not null,
  active_cycles       int not null,
  member_since        date not null,
  created_at          timestamptz not null default now(),
  revoked_at          timestamptz
);
create unique index if not exists score_shares_one_live_idx on score_shares (user_id) where revoked_at is null;

-- Publishes a snapshot of the member's current score behind p_token, replacing
-- any live link. Refuses until the member has enough confirmed payments.
create or replace function share_sova_score(p_user_id uuid, p_token text)
returns uuid
language plpgsql as $$
declare
  s       record;
  v_name  text;
  v_since date;
  v_id    uuid;
begin
  select * into s from sova_score_now(p_user_id);
  if s.confirmed_payments < sova_score_min_payments() then
    perform sova_fail(409, 'not_enough_history',
      format('Your Sova Score starts after %s confirmed payments. You have %s so far.',
             sova_score_min_payments(), s.confirmed_payments));
  end if;
  select coalesce(split_part(full_name, ' ', 1) || coalesce(' ' || left(nullif(split_part(full_name, ' ', 2), ''), 1) || '.', ''), 'Member'),
         created_at::date
    into v_name, v_since
    from users where id = p_user_id;

  update score_shares set revoked_at = now() where user_id = p_user_id and revoked_at is null;
  insert into score_shares (user_id, token, display_name, score_value, on_time_rate, consistency_rate, completion_rate,
                            confirmed_payments, completed_cycles, active_cycles, member_since)
  values (p_user_id, p_token, v_name, s.score_value, s.on_time_rate, s.consistency_rate, s.completion_rate,
          s.confirmed_payments, s.completed_cycles, s.active_cycles, v_since)
  returning id into v_id;
  perform calculate_sova_score(p_user_id);
  return v_id;
end $$;
