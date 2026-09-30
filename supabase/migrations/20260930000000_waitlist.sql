-- Waitlist for the Sova website. The site inserts with the public anon key,
-- so RLS allows anonymous INSERT only: nobody can read the list from the browser.
create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 80),
  phone       text not null unique check (phone ~ '^\+234[789][01]\d{8}$'),
  role        text not null check (role in ('member', 'admin', 'collector')),
  city        text check (char_length(city) <= 80),
  group_size  int  check (group_size between 1 and 5000),
  created_at  timestamptz not null default now()
);

alter table public.waitlist enable row level security;

drop policy if exists "anyone can join the waitlist" on public.waitlist;
create policy "anyone can join the waitlist"
  on public.waitlist for insert
  to anon
  with check (true);
