-- Sova app schema (Neon Postgres), rebuilt from the old Expo/Supabase app.
--
-- Changes from the Supabase version:
--   * No dependency on Supabase Auth: users.id is our own uuid, so any login
--     method (Neon Auth, Termii OTP + JWT, ...) can be added later.
--   * Constraints the old app relied on the client for: one membership per
--     group, unique payout positions, one contribution per member per round,
--     and checked status values.
--   * expo_push_token -> push_token (the new app is Flutter/FCM).
--   * Row-level security is not enabled yet: only server code connects, with
--     DATABASE_URL. Add RLS when the app talks to the database directly.

create table if not exists users (
  id                   uuid primary key default gen_random_uuid(),
  phone                text not null unique check (phone ~ '^\+234[789][01]\d{8}$'),
  full_name            text check (char_length(full_name) <= 80),
  avatar_url           text,
  pin_hash             text,
  pin_failed_attempts  int not null default 0,
  pin_locked_until     timestamptz,
  bank_name            text,
  account_number       text check (account_number ~ '^\d{10}$'),
  account_name         text,
  push_token           text,
  created_at           timestamptz not null default now()
);

create table if not exists nigerian_banks (
  id    serial primary key,
  name  text not null unique,
  code  text unique  -- NIP/CBN code, fill in when payouts need it
);

create table if not exists groups (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null check (char_length(name) between 2 and 60),
  admin_id             uuid not null references users(id),
  member_count         int not null check (member_count between 2 and 500),
  contribution_amount  int not null check (contribution_amount > 0),  -- naira
  cycle_type           text not null check (cycle_type in ('daily', 'weekly', 'monthly')),
  start_date           date not null,
  status               text not null default 'active' check (status in ('active', 'paused', 'completed')),
  invite_code          text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  created_at           timestamptz not null default now()
);

create table if not exists group_members (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references groups(id) on delete cascade,
  user_id          uuid not null references users(id) on delete cascade,
  payout_position  int not null check (payout_position > 0),
  joined_at        timestamptz not null default now(),
  unique (group_id, user_id),
  -- deferrable so positions can be swapped inside one transaction
  constraint group_members_position_unique unique (group_id, payout_position) deferrable initially deferred
);
create index if not exists group_members_user_idx on group_members (user_id);

create table if not exists rounds (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  round_number  int not null check (round_number > 0),
  collector_id  uuid not null references users(id),
  due_date      date not null,
  status        text not null default 'pending' check (status in ('pending', 'active', 'completed')),
  created_at    timestamptz not null default now(),
  unique (group_id, round_number)
);
create index if not exists rounds_collector_idx on rounds (collector_id);
-- at most one active round per group
create unique index if not exists rounds_one_active_idx on rounds (group_id) where status = 'active';

create table if not exists contributions (
  id                      uuid primary key default gen_random_uuid(),
  round_id                uuid not null references rounds(id) on delete cascade,
  group_id                uuid not null references groups(id) on delete cascade,
  user_id                 uuid not null references users(id) on delete cascade,
  amount                  int not null check (amount > 0),
  payer_confirmed         boolean not null default false,
  payer_confirmed_at      timestamptz,
  collector_confirmed     boolean not null default false,
  collector_confirmed_at  timestamptz,
  status                  text not null default 'pending'
                          check (status in ('pending', 'payer_confirmed', 'fully_confirmed', 'disputed')),
  created_at              timestamptz not null default now(),
  unique (round_id, user_id)
);
create index if not exists contributions_user_idx on contributions (user_id);
create index if not exists contributions_group_idx on contributions (group_id);

create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  type        text not null check (type in ('payment_due', 'payment_confirmed', 'reminder', 'dispute', 'group_update')),
  title       text not null,
  message     text not null,
  read        boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_unread_idx on notifications (user_id) where not read;

create table if not exists scores (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references users(id) on delete cascade,
  score_value       int not null check (score_value between 0 and 100),
  on_time_rate      numeric(5, 4) not null,
  consistency_rate  numeric(5, 4) not null,
  completion_rate   numeric(5, 4) not null,
  active_cycles     int not null,
  completed_cycles  int not null,
  calculated_at     timestamptz not null default now()
);
create index if not exists scores_user_latest_idx on scores (user_id, calculated_at desc);

-- PIN lockout: call before checking a PIN. Five wrong tries locks the PIN
-- for 15 minutes. Returns whether the PIN is currently locked.
create or replace function check_and_increment_pin_attempts(p_user_id uuid)
returns table (locked boolean, attempts int, locked_until timestamptz)
language plpgsql as $$
declare
  u users%rowtype;
begin
  select * into u from users where id = p_user_id for update;
  if not found then
    raise exception 'user % not found', p_user_id;
  end if;

  if u.pin_locked_until is not null and u.pin_locked_until > now() then
    return query select true, u.pin_failed_attempts, u.pin_locked_until;
    return;
  end if;

  update users
     set pin_failed_attempts = case when u.pin_failed_attempts + 1 >= 5 then 0 else u.pin_failed_attempts + 1 end,
         pin_locked_until    = case when u.pin_failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
   where id = p_user_id
  returning false, users.pin_failed_attempts, users.pin_locked_until
    into locked, attempts, locked_until;
  return next;
end $$;

-- Call after a correct PIN.
create or replace function reset_pin_attempts(p_user_id uuid)
returns void
language sql as $$
  update users set pin_failed_attempts = 0, pin_locked_until = null where id = p_user_id;
$$;

-- Close the group's active round and open the next one, collected by the
-- member at the next payout position. Marks the group completed after the
-- last position. Returns the new round number, or null when the group is done.
create or replace function force_advance_round(p_group_id uuid)
returns int
language plpgsql as $$
declare
  g          groups%rowtype;
  cur        rounds%rowtype;
  next_num   int;
  next_user  uuid;
  next_due   date;
begin
  select * into g from groups where id = p_group_id for update;
  if not found then
    raise exception 'group % not found', p_group_id;
  end if;

  select * into cur from rounds where group_id = p_group_id and status = 'active';
  if found then
    update rounds set status = 'completed' where id = cur.id;
    next_num := cur.round_number + 1;
    next_due := cur.due_date + case g.cycle_type
                                 when 'daily' then interval '1 day'
                                 when 'weekly' then interval '1 week'
                                 else interval '1 month' end;
  else
    next_num := 1;
    next_due := g.start_date;
  end if;

  select user_id into next_user from group_members
   where group_id = p_group_id and payout_position = next_num;

  if next_user is null then
    update groups set status = 'completed' where id = p_group_id;
    return null;
  end if;

  insert into rounds (group_id, round_number, collector_id, due_date, status)
  values (p_group_id, next_num, next_user, next_due, 'active')
  on conflict (group_id, round_number)
  do update set status = 'active', collector_id = excluded.collector_id, due_date = excluded.due_date;

  return next_num;
end $$;

-- Sova Score v1 (0-100). A transparent first formula, to be tuned once real
-- repayment data exists:
--   on_time_rate      share of the member's confirmed contributions paid on or before the due date
--   consistency_rate  share of rounds in their groups (active or completed) they contributed to
--   completion_rate   share of their groups that reached completion
--   score = 60% on-time + 25% consistency + 15% completion
create or replace function calculate_sova_score(p_user_id uuid)
returns int
language plpgsql as $$
declare
  v_on_time      numeric := 0;
  v_consistency  numeric := 0;
  v_completion   numeric := 0;
  v_active       int;
  v_completed    int;
  v_score        int;
begin
  select coalesce(avg(case when c.payer_confirmed_at::date <= r.due_date then 1 else 0 end), 0)
    into v_on_time
    from contributions c join rounds r on r.id = c.round_id
   where c.user_id = p_user_id and c.status = 'fully_confirmed';

  select coalesce(avg(case when c.id is not null then 1 else 0 end), 0)
    into v_consistency
    from rounds r
    join group_members gm on gm.group_id = r.group_id and gm.user_id = p_user_id
    left join contributions c on c.round_id = r.id and c.user_id = p_user_id and c.status <> 'disputed'
   where r.status in ('active', 'completed') and r.collector_id <> p_user_id;

  select count(*) filter (where g.status <> 'completed'),
         count(*) filter (where g.status = 'completed')
    into v_active, v_completed
    from group_members gm join groups g on g.id = gm.group_id
   where gm.user_id = p_user_id;

  if v_active + v_completed > 0 then
    v_completion := v_completed::numeric / (v_active + v_completed);
  end if;

  v_score := round(100 * (0.60 * v_on_time + 0.25 * v_consistency + 0.15 * v_completion));

  insert into scores (user_id, score_value, on_time_rate, consistency_rate, completion_rate, active_cycles, completed_cycles)
  values (p_user_id, v_score, v_on_time, v_consistency, v_completion, v_active, v_completed);

  return v_score;
end $$;

-- Banks and fintechs traders commonly use (names only; codes added later).
insert into nigerian_banks (name) values
  ('Access Bank'), ('Citibank Nigeria'), ('Ecobank Nigeria'), ('Fidelity Bank'), ('First Bank of Nigeria'),
  ('First City Monument Bank (FCMB)'), ('Globus Bank'), ('Guaranty Trust Bank (GTBank)'), ('Jaiz Bank'),
  ('Keystone Bank'), ('Kuda Microfinance Bank'), ('Moniepoint Microfinance Bank'), ('OPay'), ('PalmPay'),
  ('Polaris Bank'), ('Providus Bank'), ('Stanbic IBTC Bank'), ('Standard Chartered Bank Nigeria'),
  ('Sterling Bank'), ('SunTrust Bank'), ('Titan Trust Bank'), ('Union Bank of Nigeria'),
  ('United Bank for Africa (UBA)'), ('Unity Bank'), ('Wema Bank'), ('Zenith Bank')
on conflict (name) do nothing;
