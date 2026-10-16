# Performance on RumptyCloud

Measured on **16 October 2026** against the live API at `https://sova-api.rumptycloud.app` (version 0.9.1), deployed on RumptyCloud's **Free size: 0.5 vCPU, 512 MB, sleeps when idle**. The database is RumptyCloud managed PostgreSQL 17.11 holding the seeded demo data (18 people, 5 circles, 167 ledger entries).

These are small, careful measurements from one machine, not a capacity test. Every figure below is what the tools printed; nothing is extrapolated.

## Summary

| What | Result |
|---|---|
| Cold start (asleep → first JSON answer) | **one sample:** wake page in 0.7 s; API process up 3–5 s after the first request; JSON answer within **11 s** at most |
| Warm `GET /health`, one request at a time (100 requests) | p50 **79 ms**, p95 172 ms |
| Warm public ledger, one at a time (45 requests, 18.7 kB each) | p50 **150 ms**, p95 820 ms |
| Most requests per second seen (10 connections, 10 s) | `/health` **96/s**, `/public/demo-circles` **63/s**, no errors |
| Public ledger in a 50-request burst (5 connections) | **16/s**, p50 210 ms, no errors |
| Database time for every hot query | **under 1 ms** each (EXPLAIN ANALYZE) |
| Errors or rate-limit refusals during all runs | **none** |

What this means: once awake, the Free size answers well within what a demo needs, and the database is not the bottleneck: almost all of the time is the network and Node on half a CPU. The real cost of the Free size is the **sleep**: the first visitor after an idle spell sees RumptyCloud's "Waking your app" page for several seconds (the app and the website's waitlist wait it out and retry). The tail is also uneven: p95 and p99 jump to 0.4–1.6 s on single requests, which looks like a shared half-CPU being descheduled rather than slow code (the same requests are fast most of the time).

## Method

- **Client:** a Windows laptop on the owner's internet connection, Node 22.14. A fresh TCP connection to the API's edge took 26–36 ms and a full TLS handshake 130–210 ms, so a request over a kept-alive connection can't be faster than about 30 ms however quick the server is.
- **Tools:** [autocannon](https://github.com/mcollina/autocannon) 8.0.0 via `npx` for concurrent runs; a 20-line Node script (sequential `fetch` over one kept-alive connection, sorted percentiles) for one-at-a-time latency; `curl -w` for connection timings; a polling script for cold start (one request every 500 ms until `/health` answers JSON 200).
- **Endpoints:** only public, read-only ones: `GET /health` (runs `select 1`), `GET /public/demo-circles`, `GET /public/circles/:id/ledger` (Office Esusu, the longest chain: 47 entries, 18.7 kB) and `GET /public/chain-heads`. Signed-in screens were checked at the database level only (see below).
- **Staying gentle:** concurrency stepped 1 → 5 → 10 for 10 seconds each with 5-second pauses, and no further. The ledger (60 requests a minute per IP) and chain heads (10 a minute per IP) were kept under their limits: 45 and 8 sequential requests, then one 50-request ledger burst in a fresh minute. Not one request was refused.
- **Single runs.** Each figure is one run from one place at one time of day. Treat differences under about 2× as noise (for example `/health` at 5 connections came out slower than at 10).

## Cold start

The API sleeps when idle. A request to a sleeping app gets an immediate `503` HTML page from RumptyCloud (`<html data-rumpty-wake="1">`, "Waking your app…") while the container starts; the API's own JSON only comes once Node is up and connected to Postgres.

One clean sample (16 Oct, after the API had been idle for an unknown time):

| Time (UTC) | What happened |
|---|---|
| 10:13:49.6 | First request. RumptyCloud answered at once (0.67 s) with the `503` wake page. |
| 10:13:52.6–10:13:54.6 | The API process started (worked back from `uptimeSeconds: 7` in the next answer). |
| 10:14:00.6 | Next request: `200` JSON, `"database":"ok"`, 0.56 s. |

So the container started 3–5 seconds after the waking request, and the API was answering **no later than 11 seconds** after it. The true figure is somewhere between about 4 and 11 seconds: there was a 10-second gap between the first two requests, so this sample can't be narrowed further. It agrees with RumptyCloud's stated ~8 s.

A second attempt after 25 idle minutes (10:45:49) found the API already awake with `uptimeSeconds: 318`: something else had woken or restarted it at 10:40:31, so that attempt measured nothing. A cold start can only be timed from the first request after a sleep, and any visitor or job (the 6-hourly anchors workflow, a judge, a team member) can be that first request.

The Flutter app recognises the wake page (`data-rumpty-wake`) and retries every 2 seconds; the website's waitlist also retries. Paid sizes can turn scale-to-zero off, which removes this wait entirely; the Free size cannot.

## Warm latency

One request at a time over a kept-alive connection:

| Endpoint | Requests | Body | min | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|---|
| `GET /health` | 100 | 68 B | 55 ms | **79 ms** | 172 ms | 349 ms | 364 ms |
| `GET /public/demo-circles` | 100 | 474 B | 57 ms | **79 ms** | 420 ms | 503 ms | 549 ms |
| `GET /public/circles/:id/ledger` | 45 | 18.7 kB | 90 ms | **150 ms** | 820 ms | 948 ms | 948 ms |
| `GET /public/chain-heads` | 8 | 894 B | 74 ms | **110 ms** | 884 ms | — | 884 ms |

With a new connection each time (as a browser's first request would), `curl` saw 230–300 ms to the first byte of `/health`, most of it the TLS handshake.

## Throughput

autocannon, 10 seconds per step:

| Endpoint | Connections | Requests/s | p50 | p90 | p99 | max | Errors |
|---|---|---|---|---|---|---|---|
| `GET /health` | 1 | 7.8 | 98 ms | 163 ms | 1,472 ms | 1,472 ms | 0 |
| | 5 | 30.9 | 135 ms | 207 ms | 696 ms | 874 ms | 0 |
| | 10 | **96.1** | 90 ms | 140 ms | 777 ms | 874 ms | 0 |
| `GET /public/demo-circles` | 1 | 10.2 | 84 ms | 152 ms | 264 ms | 284 ms | 0 |
| | 5 | 41.7 | 102 ms | 165 ms | 529 ms | 790 ms | 0 |
| | 10 | **63.2** | 132 ms | 194 ms | 1,631 ms | 1,677 ms | 0 |
| `GET /public/circles/:id/ledger` (50-request burst) | 5 | **16.0** | 210 ms | 302 ms | 661 ms | 661 ms | 0 |

Rate limits, not the server, set the ceiling a single visitor can reach on the ledger (60 a minute, so 1 a second sustained) and on chain heads (10 a minute). The ledger burst shows the server itself handled 16 a second on its heaviest public route without errors. Every response also carries a second `x-ratelimit-limit: 500, 500;w=1` header, present even on the wake page, so it comes from RumptyCloud's edge rather than Sova.

Not measured: higher concurrency (deliberately, on a shared Free deployment), signed-in endpoints over HTTP, and clients far from the platform.

## Database

`EXPLAIN (ANALYZE, BUFFERS)` was run on the RumptyCloud database as the restricted `sova_app` role, inside a read-only transaction that was rolled back. The queries are copied from the routes: the public ledger (entries by circle, circle header), chain heads, demo circles, the circle screen (membership check, members with rules/vouches/obligations, draw order from the ledger, turns, payments by circle and by turn), the circles list, and notifications (list, "pay now" reminders, "to confirm" reminders).

| Query | Execution time | Index used when the table is large (seq scans off) |
|---|---|---|
| Ledger entries by circle | 0.28 ms | `ledger_entries_group_id_seq_key` (group_id, seq) |
| Chain heads | 0.43 ms | `ledger_entries_group_id_seq_key` |
| Demo circles | 0.17 ms | `users_pkey`; `groups` has no index on `admin_id` |
| Circle screen: members | 0.95 ms | `group_members_position_unique`, `vouches_group_id_vouchee_id_key`, `rule_acceptances_pkey`, `rounds_group_id_round_number_key`, `contributions_user_idx` |
| Circle screen: draw order | 0.25 ms | `circle_draws_pkey`, `ledger_entries_group_id_seq_key` |
| Circle screen: turns / payments | 0.06–0.14 ms | `rounds_group_id_round_number_key`, `contributions_group_idx`, `contributions_round_id_user_id_key` |
| Circles list | 0.42 ms | `group_members_user_idx`, `rounds_one_active_idx`, `contributions_round_id_user_id_key` |
| Notifications list | 0.12 ms | `notifications_user_recent_idx` (user_id, created_at desc) |
| Reminders (pay now / to confirm) | 0.31 / 0.17 ms | `group_members_user_idx`, `rounds_one_active_idx`, `rounds_collector_idx`, `contributions_round_id_user_id_key` |

With today's small tables the planner chooses sequential scans everywhere, which is the right choice for tables of a few dozen rows. To see what it would do as the data grows, the same queries were planned again with `enable_seqscan = off`: every hot query has an index path already, so **no new migration was added**. The one exception is `GET /public/demo-circles`, which scans `groups` (no index on `admin_id`); it only lists the seeded demo circles and costs 0.17 ms today, so it is a watch item, not a fix. (In that forced run the query took 1.5–2 s, but that was PostgreSQL's JIT compiler starting because disabling seq scans inflates the estimated cost; with `jit = off` the same plan ran in 0.2 ms. Normal plans never reach the JIT threshold.)

Database settings seen: `shared_buffers` 64 MB, `work_mem` 4 MB, `max_connections` 100.

## Demo sign-in

Measured later on 16 October, after "Try the demo" started giving each visitor a private copy of the demo world (`POST /auth/demo`, one request each, from the same client):

| When | Time |
|---|---|
| Building the copy during the request (first version) | 5,568 ms, 6,469 ms |
| A spare copy ready (first request, new connection) | 1,171 ms |
| Straight after, while the next spare was still being built | 2,588 ms |
| A spare ready again (after 25 s waits) | 548 ms, 367 ms |

Four requests with spares, so treat these as an indication, not a benchmark. The API keeps one spare built in advance by default (`DEMO_SPARES`).

## Limits of the Free size

- **It always sleeps when idle.** The first visitor after a quiet spell waits for the container to start (see Cold start). This is the biggest effect on what a judge would notice, and only a paid size with scale-to-zero off removes it.
- **Half a CPU.** Single requests occasionally take 0.5–1.6 s even though the same request usually takes under 100 ms. More connections did not make it fail, but the tail is uneven.
- **One instance, 512 MB.** No autoscaling was configured or tested.

## Reproducing

From any machine with Node 22 (keep within the rate limits above):

```bash
npx autocannon@8 -c 5 -d 10 https://sova-api.rumptycloud.app/health
```

```bash
curl -s -o /dev/null -w "connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer}\n" https://sova-api.rumptycloud.app/health
```

For a cold start, leave the API idle until it sleeps, then request `/health` every 500 ms and time how long until it answers JSON with `"status":"ok"` (the `uptimeSeconds` field confirms the process has just started).
