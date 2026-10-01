-- Waitlist for the Sova website (Neon Postgres). Only the website's server-side
-- API route connects, using DATABASE_URL; the browser never touches the database.
create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 80),
  phone       text not null unique check (phone ~ '^\+234[789][01]\d{8}$'),
  role        text not null check (role in ('member', 'admin', 'collector')),
  city        text check (char_length(city) <= 80),
  group_size  int  check (group_size between 1 and 5000),
  created_at  timestamptz not null default now()
);
