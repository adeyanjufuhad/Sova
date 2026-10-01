# Sova

Records, reminders and receipts for ajo, esusu and adashe savings circles. Sova never holds members' money.

## Repo layout

| Path | What it is |
| --- | --- |
| `website/` | Marketing site + waitlist (Next.js, Tailwind CSS v4, Motion) |
| `db/migrations/` | Database schema (Neon Postgres) |
| `app/` | Flutter Android app *(coming next)* |

## Zero-cost stack

| Need | Service | Free tier |
| --- | --- | --- |
| Code hosting | GitHub | Free |
| Website hosting | Vercel Hobby | Free, `*.vercel.app` domain |
| Database | Neon (project `sova`, London) | Free (0.5 GB per project, scales to zero when idle) |
| App builds | Flutter + GitHub Actions | Free |

Paid things we are deliberately postponing: a custom domain (~₦15k/yr for `.com.ng`), the Google Play developer account ($25 one-off), and SMS credits.

## Website: run locally

```bash
cd website
npm install
cp .env.example .env.local   # then paste the Neon DATABASE_URL
npm run dev
```

Open http://localhost:3000.

## Waitlist database

The waitlist lives in the Neon project **sova**. To recreate it, run `db/migrations/20260930000000_waitlist.sql` in the Neon SQL editor.
Only the website's server-side API route connects (via `DATABASE_URL`), so the browser never touches the database. Read signups in the Neon console's Tables view or SQL editor.

## Deploy the website (free)

1. Import this repo at https://vercel.com/new
2. Set **Root Directory** to `website`
3. Add the env vars from `website/.env.example`
4. Deploy

When the Android app is live on Google Play, set `NEXT_PUBLIC_PLAY_STORE_URL` and the "Coming soon" buttons become real download buttons.

## UI credits

Several components are adapted from open-source libraries listed on [21st.dev](https://21st.dev): Aceternity UI (Timeline, Container Scroll Animation), Magic UI (Marquee, Animated Beam, Blur Fade), React Bits (Light Rays) and Orbiting Circles 02. The site uses a flat style: solid colours, no gradients or glows.
