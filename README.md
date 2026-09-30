# Sova

Records, reminders and receipts for ajo, esusu and adashe savings circles. Sova never holds members' money.

## Repo layout

| Path | What it is |
| --- | --- |
| `website/` | Marketing site + waitlist (Next.js, Tailwind CSS v4, Motion) |
| `supabase/migrations/` | Database schema (Supabase Postgres) |
| `app/` | Flutter Android app *(coming next)* |

## Zero-cost stack

| Need | Service | Free tier |
| --- | --- | --- |
| Code hosting | GitHub | Free |
| Website hosting | Vercel Hobby | Free, `*.vercel.app` domain |
| Database + auth | Supabase | Free (2 active projects, pauses after 7 days idle) |
| App builds | Flutter + GitHub Actions | Free |

Paid things we are deliberately postponing: a custom domain (~₦15k/yr for `.com.ng`), the Google Play developer account ($25 one-off), and SMS credits.

## Website: run locally

```bash
cd website
npm install
cp .env.example .env.local   # then fill in the Supabase values
npm run dev
```

Open http://localhost:3000.

## Waitlist database

Run `supabase/migrations/20260930000000_waitlist.sql` in the Supabase SQL editor (or `supabase db push`).
The table only allows anonymous **inserts**; nobody can read the list from the browser. Read signups from the Supabase dashboard.

## Deploy the website (free)

1. Import this repo at https://vercel.com/new
2. Set **Root Directory** to `website`
3. Add the env vars from `website/.env.example`
4. Deploy

When the Android app is live on Google Play, set `NEXT_PUBLIC_PLAY_STORE_URL` and the "Coming soon" buttons become real download buttons.

## UI credits

Several components are adapted from open-source libraries listed on [21st.dev](https://21st.dev): Aceternity UI (Timeline, Container Scroll Animation), Magic UI (Marquee, Animated Beam, Blur Fade), React Bits (Light Rays) and Orbiting Circles 02. The site uses a flat style: solid colours, no gradients or glows.
