# Sova database

PostgreSQL 17 schema for Sova, as ordered SQL migrations. Production runs on RumptyCloud managed Postgres.

The database holds the rules that protect the records, so they apply no matter which code writes: constraints (one membership per circle, unique payout turns, one contribution per member per round, valid statuses and phone numbers) and functions for joining, the fair draw, paying and confirming, closing a turn, disputes, swaps, handovers, PIN lockout, the Sova Score and notifications. Triggers write the tamper-evident ledger.

## Migrations

| File | Adds |
|---|---|
| `20260930000000_waitlist.sql` | Website waitlist |
| `20261001000000_app_schema.sql` | Users, banks, circles (`groups`), members, rounds, contributions, notifications, scores; PIN lockout, `force_advance_round`, `calculate_sova_score` |
| `20261002000000_trust_features.sql` | Group rules and acceptances, vouches, proof of payment, payout receipts (`confirm_payout`), swaps, handovers, disputes, `unfinished_obligations` |
| `20261003000000_auth_and_fixes.sql` | One-time codes, sessions; turns stay empty until the fair draw; admin "collect last" pledge; invite code format; payout = contribution × (members − 1) |
| `20261004000000_circle_lifecycle.sql` | `forming` status; commit-reveal draw (`circle_draws`, `run_draw`); joining, rule acceptance, paying, confirming and closing a turn as functions; shortfall opens a dispute |
| `20261005000000_ledger.sql` | Per-circle SHA-256 hash chain (`ledger_entries`) written by triggers; UPDATE, DELETE and TRUNCATE refused for every role (see `docs/ledger.md`) |
| `20261006000000_dispute_votes.sql` | Payment and shortfall disputes, open votes, settling, comments; shortfalls settle themselves when the missing payments are confirmed |
| `20261007000000_sova_score.sql` | Live score (`sova_score_now`), shared snapshots (`score_shares`, `share_sova_score`) |
| `20261008000000_swaps_handovers.sql` | Swap requests and answers, handovers with replacement and admin approval, applied as a turn ends |
| `20261009000000_notifications.sql` | `notify()` and triggers that write in-app notifications with an app link; `change_pin` |

Rules:
- Files are named `YYYYMMDDHHMMSS_description.sql` and applied in order, once each.
- **Never edit a migration after it has been applied.** The runner stores a checksum and refuses changed files; add a new migration instead.
- Migrations need only built-in Postgres 17 features (no extensions).

## Apply

Migrations are applied by the API's runner (`api/src/migrate/runner.ts`), which records each version in `schema_migrations` under an advisory lock:

```bash
cd api
npm run migrate          # uses MIGRATION_DATABASE_URL, else DATABASE_URL
```

Run it with an admin user. Afterwards the runner grants the restricted `sova_app` role (if it exists) access to every table, minus UPDATE/DELETE on append-only tables.

## Demo data

`npm run seed` (in `api/`) recreates 18 demo people (phones `+2348000000xxx`) and 5 circles in different states. It never touches other users.
