-- Daily limits for "Ask Sova". Answers are counted per member and for the
-- whole service, per day in Lagos, so the free inference allowance can't be
-- used up by one person or by a stream of new demo visitors. Counts live here
-- (not in the API's memory) because the API sleeps and restarts on the Free size.
--
-- The whole-service count has its own table: purging demo copies deletes their
-- users (and their per-member rows) but must not give the day's answers back.

create table if not exists assistant_days (
  day     date primary key,
  answers integer not null default 0 check (answers >= 0)
);

create table if not exists assistant_usage (
  day     date not null,
  user_id uuid not null references users (id) on delete cascade,
  answers integer not null default 0 check (answers >= 0),
  primary key (day, user_id)
);

-- Takes one answer from today's allowance: 'ok', or which limit refused it.
-- The day's row is locked, so concurrent requests can't both take the last answer.
create or replace function take_assistant_answer(p_user_id uuid, p_per_member integer, p_total integer)
returns text
language plpgsql
as $$
declare
  v_day   date := (now() at time zone 'Africa/Lagos')::date;
  v_total integer;
  v_mine  integer;
begin
  insert into assistant_days (day) values (v_day) on conflict (day) do nothing;
  select answers into v_total from assistant_days where day = v_day for update;
  if v_total >= p_total then
    return 'total_limit';
  end if;

  select answers into v_mine from assistant_usage where day = v_day and user_id = p_user_id;
  if coalesce(v_mine, 0) >= p_per_member then
    return 'member_limit';
  end if;

  update assistant_days set answers = answers + 1 where day = v_day;
  insert into assistant_usage (day, user_id, answers) values (v_day, p_user_id, 1)
    on conflict (day, user_id) do update set answers = assistant_usage.answers + 1;
  return 'ok';
end;
$$;

-- Gives an answer back when the model service failed, so errors don't use up the allowance.
create or replace function give_back_assistant_answer(p_user_id uuid)
returns void
language plpgsql
as $$
declare
  v_day date := (now() at time zone 'Africa/Lagos')::date;
begin
  update assistant_days set answers = answers - 1 where day = v_day and answers > 0;
  update assistant_usage set answers = answers - 1 where day = v_day and user_id = p_user_id and answers > 0;
end;
$$;
