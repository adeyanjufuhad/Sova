-- Guided tours: the app walks a new member through the main screens once, and
-- through a circle the first time they open one. Which tours someone has
-- finished (or skipped) is kept on their account so it doesn't come back on
-- another device or after a reload. Private demo copies start with none done,
-- so every demo visitor gets the tour.

alter table users add column if not exists tours_done text[] not null default '{}';

alter table users drop constraint if exists users_tours_done_known;
alter table users add constraint users_tours_done_known check (tours_done <@ array['home', 'circle']::text[]);
