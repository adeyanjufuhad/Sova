-- Signing in with an email code or with Google, next to the phone code.
--
-- An account is found by its verified phone, its verified email or its Google
-- account id (`google_sub`). Emails are stored lower-case. Google only hands
-- over verified emails, so a Google sign-in links to an account that already
-- uses the same email. Circle members see the email where a phone would be.

alter table users add column if not exists email text;
alter table users add column if not exists google_sub text;

alter table users drop constraint if exists users_email_format;
alter table users add constraint users_email_format
  check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 254));

create unique index if not exists users_email_key on users (email) where email is not null;
create unique index if not exists users_google_sub_key on users (google_sub) where google_sub is not null;

-- One-time codes go to a phone or to an email, never both.
alter table otp_challenges alter column phone drop not null;
alter table otp_challenges add column if not exists email text;
alter table otp_challenges drop constraint if exists otp_challenges_one_target;
alter table otp_challenges add constraint otp_challenges_one_target check ((phone is null) <> (email is null));
create index if not exists otp_challenges_email_idx on otp_challenges (email, created_at desc) where email is not null;

-- Handing over a place: the replacement is named by phone or by email.
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
  if g.sandbox_id is not null then
    perform sova_fail(409, 'demo_handover', 'In the demo, places can''t be handed to a real phone number.');
  end if;
  select payout_position into v_pos from group_members where group_id = p_group_id and user_id = p_user_id;
  if not position_is_open(p_group_id, v_pos) then
    perform sova_fail(409, 'turn_started', 'You have already collected or are collecting, so you need to finish the cycle.');
  end if;
  select id into v_repl from users
   where (phone = p_phone or email = lower(p_phone)) and full_name is not null and sandbox_id is null;
  if v_repl is null then
    perform sova_fail(404, 'no_account', 'Nobody with that number or email uses Sova yet. Ask them to sign up first.');
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

-- Deleting an account also forgets its email and Google account id.
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
  delete from otp_challenges where phone = u.phone or email = u.email;
  delete from waitlist where phone = u.phone;
  delete from notifications where user_id = p_user_id;
  delete from scores where user_id = p_user_id;
  delete from score_shares where user_id = p_user_id;

  update users
     set phone = null, email = null, google_sub = null, full_name = null, avatar_url = null, pin_hash = null,
         pin_failed_attempts = 0, pin_locked_until = null,
         bank_name = null, account_number = null, account_name = null, push_token = null,
         deleted_at = now()
   where id = p_user_id;
end $$;
