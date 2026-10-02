# Sova API

The backend for the Sova app and website: authentication, circles, payments, the tamper-evident ledger and the fair payout draw. It runs on Node.js 22 with Fastify and TypeScript, on top of PostgreSQL.

Business rules that guard the records (constraints, PIN lockout, round advancing, swaps, handovers, payout checks) live in the database (`../db/migrations`). The API wraps those functions rather than duplicating them.

> Status: Phase 0 skeleton. Only `GET /health` exists. See `../docs/STATUS.md` for the roadmap.

## Run locally

```bash
cd api
npm install
cp .env.example .env    # optional: set DATABASE_URL to use a database
npm run dev             # http://localhost:8080/health
```

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Start with auto-reload (`tsx watch`) |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run the compiled server (`node dist/server.js`) |
| `npm run typecheck` | Type-check source and tests |
| `npm test` | Run the test suite (Vitest) |

## Environment variables

All configuration is read from the environment and validated at startup (`src/config.ts`); an invalid value stops the server with a clear message. See `.env.example`.

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | `development` | `development`, `test` or `production` |
| `HOST` | `0.0.0.0` | Interface to listen on |
| `PORT` | `8080` | Port to listen on |
| `LOG_LEVEL` | `info` | Pino log level |
| `DATABASE_URL` | none | Postgres connection string (internal string on RumptyCloud) |
| `CORS_ORIGINS` | none | Comma-separated browser origins allowed to call the API |

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | none | `200 {status:"ok"}` when up; `503` if the database is configured but unreachable |

## Security notes

- Logs redact authorization headers, cookies, PINs, OTP codes, tokens and secrets.
- Request bodies are limited to 64 KB.
