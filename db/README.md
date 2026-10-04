# Sova database

PostgreSQL 17 schema for Sova, as ordered SQL migrations. Production runs on RumptyCloud managed Postgres.

The database holds the rules that protect the records, so they apply no matter which code writes: constraints (one membership per circle, unique payout turns, one contribution per member per round, valid statuses and phone numbers) and functions for PIN lockout, advancing rounds, swaps, handovers, payout confirmation and the Sova Score.

## Migrations

| File | Adds |
|---|---|
| `20260930000000_waitlist.sql` | Website waitlist |
| `20261001000000_app_schema.sql` | Users, banks, circles (`groups`), members, rounds, contributions, notifications, scores; PIN lockout, `force_advance_round`, `calculate_sova_score` |
| `20261002000000_trust_features.sql` | Group rules and acceptances, vouches, proof of payment, payout receipts (`confirm_payout`), swaps, handovers, disputes, `unfinished_obligations` |
| `20261003000000_auth_and_fixes.sql` | One-time codes, sessions; turns stay empty until the fair draw; admin "collect last" pledge; invite code format; payout = contribution × (members − 1) |
| `20261004000000_circle_lifecycle.sql` | `forming` status; commit-reveal draw (`circle_draws`, `run_draw`); joining, rule acceptance, paying, confirming and closing a turn as functions; shortfall opens a dispute |

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
