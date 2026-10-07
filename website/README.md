# Sova website

The public site, live at https://sova.rumptycloud.app: what Sova is, how a circle runs, the roadmap, an FAQ in English and Pidgin, and the waitlist. Next.js with Tailwind CSS v4, exported as static files.

It also has two pages that work with live data:

| Page | What it does |
|---|---|
| `/verify/?c=<circle id>` | Downloads a circle's ledger from the API and recomputes every SHA-256 link and the fair draw in the browser. Without `c` it lists the demo circles. |
| `/score/?t=<token>` | Shows a Sova Score someone chose to share. Not indexed by search engines. |

## Run

```bash
npm install
cp .env.example .env.local
npm run dev
```

The site is at http://localhost:3000. Set `NEXT_PUBLIC_API_URL=http://localhost:8080` in `.env.local` to use a local API.

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SITE_URL` | Public address, for social previews |
| `NEXT_PUBLIC_APP_URL` | The web app ("Try the live demo") |
| `NEXT_PUBLIC_API_URL` | The Sova API (waitlist, verify, shared scores); it must list this site in `CORS_ORIGINS` |
| `NEXT_PUBLIC_PLAY_STORE_URL` | Empty until the Android app is on Google Play; the download buttons say "coming soon" until then |

All of them end up in the static files, so never put secrets here.

## Checks

```bash
npm run lint
npm run build
```

`npm run build` writes the static site to `out/` (`output: "export"`, with `trailingSlash` so `/verify/` is a folder any static host can serve).

## Structure

```
src/
  app/                    page.tsx (home), verify/, score/, layout, globals.css (tokens)
  components/sections/    one file per home page section
  components/verify/      the in-browser ledger and draw check
  components/score/       the shared score card
  components/ui/          building blocks, several adapted from 21st.dev and restyled flat
  lib/                    site addresses, API calls with wake-up retries
```

Design rules are in [../DESIGN.md](../DESIGN.md). The copy describes only what is built; everything else is labelled "coming soon" or listed under the roadmap.

## Hosting

`.github/workflows/site-web.yml` lints and builds the site on every push to `main` that touches `website/`, then publishes `out/` to the `site-web` branch, which RumptyCloud serves as a static site.
