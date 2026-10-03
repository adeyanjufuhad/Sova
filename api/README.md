# Sova API

The backend for the Sova app and website: phone sign-in, circles, payments, the tamper-evident ledger and the fair payout draw. Node.js 22, Fastify and TypeScript on PostgreSQL 17.

Rules that guard the records (constraints, PIN lockout, round advancing, swaps, handovers, payout checks) live in the database (`../db/migrations`). The API wraps those functions instead of duplicating them.

> Status: Phase 1 (auth, migrations, seed). Circle endpoints arrive in Phase 2. See `../docs/STATUS.md`.

## Run locally

```bash
cd api
npm install
cp .env.example .env     # set DATABASE_URL and JWT_SECRET
npm run migrate          # apply db/migrations
npm run seed             # optional: demo data
npm run dev              # http://localhost:8080/health
```

The npm scripts read `api/.env` automatically.

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Start with auto-reload |
| `npm run build` | Compile to `dist/` and copy `db/migrations` into `dist/migrations` |
| `npm start` | Run the compiled server |
| `npm test` | Tests against a throwaway PostgreSQL 17 (embedded-postgres, no Docker) |
| `npm run typecheck` | Type-check source, tests and scripts |
| `npm run migrate` / `migrate:prod` | Apply pending migrations (as an admin user) |
| `npm run seed` / `seed:prod` | Recreate demo data (reserved phones `+2348000000xxx` only) |
| `npm run db:create-app-role` | Create or rotate the restricted `sova_app` login and print its connection string once |

## Environment variables

Validated at startup (`src/config.ts`); an invalid value stops the server with a clear message. Full descriptions in `.env.example`.

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | `development` | `development`, `test` or `production` |
| `HOST`, `PORT` | `0.0.0.0`, `8080` | Where to listen |
| `LOG_LEVEL` | `info` | Pino log level |
| `DATABASE_URL` | none | Postgres URL the API uses (restricted `sova_app` user in production) |
| `DATABASE_SSL` | `auto` | `auto`, `disable`, `no-verify`, `verify` |
| `DATABASE_CA_CERT` | none | PEM certificate for `verify` |
| `MIGRATION_DATABASE_URL` | `DATABASE_URL` | Admin URL for migrate/seed/role scripts |
| `RUN_MIGRATIONS_ON_START` | `false` | Migrate at startup (needs DDL rights) |
| `CORS_ORIGINS` | none | Browser origins allowed to call the API |
| `JWT_SECRET` | random in dev | Signs tokens and hashes OTPs; **required in production** |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` | Access token lifetime |
| `REFRESH_TOKEN_TTL_DAYS` | `30` | Refresh token lifetime |
| `OTP_PROVIDER` | `test-numbers` | `test-numbers` or `sms` (stub) |
| `OTP_TEST_NUMBERS` | none | `+2348000000001:123456,...` |
| `OTP_TTL_SECONDS` | `300` | Code lifetime |
| `DEMO_LOGIN_ENABLED` | `false` | Enables `POST /auth/demo` |
| `DEMO_PHONE` | `+2348000000000` | Seeded demo account |

## Endpoints

Errors always look like `{ "error": { "code": "...", "message": "...", "details": {...} } }`.

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | none | `200` when up; `503` if the database is configured but unreachable |
| POST | `/auth/otp/request` | none | `{ phone }` → sends a code (test numbers: fixed code). 5/min per IP, 3 per 10 min per phone |
| POST | `/auth/otp/verify` | none | `{ phone, code }` → `{ accessToken, refreshToken, expiresIn, user }`. Creates the user on first sign-in |
| POST | `/auth/demo` | none | Signs into the seeded demo account (when enabled) |
| POST | `/auth/refresh` | none | `{ refreshToken }` → new token pair (rotation; reuse revokes the family) |
| POST | `/auth/logout` | none | `{ refreshToken }` → ends the session family |
| GET | `/me` | bearer | Current user |
| PATCH | `/me` | bearer | `{ fullName }` (first and last name) |
| POST | `/me/pin` | bearer | `{ pin }` sets the first PIN (4 digits, not trivial) |
| POST | `/me/pin/verify` | bearer | `{ pin }` → `204`, `401` with attempts left, or `423` when locked |

## How auth works

1. **One-time code.** `OtpProvider` decides who can receive a code and sends it. `test-numbers` serves only whitelisted phones with fixed codes (free); `sms` is a stub for a paid gateway. Codes are stored as HMAC-SHA256, expire after 5 minutes and burn after 5 wrong tries.
2. **Sessions.** A 15-minute JWT (HS256) plus a 30-day opaque refresh token stored as SHA-256. Every refresh rotates the token; presenting an already-rotated token revokes the whole family.
3. **PIN.** argon2id hash. Each check goes through the database function `check_and_increment_pin_attempts`: 5 wrong tries lock the PIN for 15 minutes.

## Deploy on RumptyCloud

Live at `https://sova-api.rumptycloud.app` (`/health`).

1. Create the restricted login once, as the admin user: `npm run db:create-app-role -- --out .env.deploy` (writes the password to a git-ignored file instead of the screen). Use the same user and password with the database's **internal** host for `DATABASE_URL`.
2. Run `npm run migrate` (and optionally `npm run seed`) from your machine with the admin URL. The image does not contain the migrations.
3. New deployment from GitHub: repository `Sova`, branch `main`, root directory `api`, type Web Service/Backend.

| Setting | Value |
|---|---|
| Build command | `npm ci && npm run build` |
| Start command | `export PATH="/mise/shims:$(echo /mise/installs/node/*/bin):$PATH"; exec node dist/server.js` |
| Health check path | `/health` |
| Port | `8080` |
| Variables | `NODE_ENV=production`, `LOG_LEVEL=info`, `DEMO_LOGIN_ENABLED=true`, `OTP_PROVIDER=test-numbers`, `OTP_TEST_NUMBERS`, `DATABASE_URL`, `JWT_SECRET`, later `CORS_ORIGINS` |

The start command sets `PATH` itself because RumptyCloud runs it in a shell that does not see the Node install inside the image; plain `npm start` or `node dist/server.js` fail with "not found".

Free deployments sleep when idle (first request waits about 8 seconds). Paid sizes can turn scale-to-zero off.

## Security notes

- Logs redact authorization headers, cookies, PINs, codes, tokens and secrets.
- All input is validated with zod; request bodies are limited to 64 KB.
- In production the API connects as `sova_app` (no superuser, no DDL). Migrations and seeding use the admin URL.
- RumptyCloud's public Postgres endpoint uses a self-signed certificate; `sslmode=require` therefore means "encrypted, not verified". Prefer the internal endpoint inside RumptyCloud.
