-- Ready-made private demos: the API keeps a spare copy of the demo world built
-- in advance, so "Try the demo" only has to claim it (one update) instead of
-- building a whole world during the request.
--
-- claimed_at is null for a spare. A spare expires a few hours after it was
-- built (its dates are relative to that day); claiming it starts the visitor's
-- own 24 hours. purge_demo_sandboxes() already removes anything expired.

alter table demo_sandboxes add column if not exists claimed_at timestamptz;

-- Every copy made before this migration was made for a visitor.
update demo_sandboxes set claimed_at = created_at where claimed_at is null;

create index if not exists demo_sandboxes_spare_idx on demo_sandboxes (created_at) where claimed_at is null;
