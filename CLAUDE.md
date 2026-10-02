# Sova: project conventions

Read `docs/STATUS.md` first. It records what is built, what is not, and every product decision.
Keep earlier decisions unless the owner changes them, and update `docs/STATUS.md` at the end of each phase.

## Product rules
- Sova never holds, moves, lends or invests money. Never add wallets, balances held by Sova, or payment processing.
- First users are self-run circles. Collector/market mode, USSD, WhatsApp, loans and multi-currency are roadmap only.
- Honesty: never invent stats, testimonials, partners or features. Unbuilt features are labelled "coming soon" or "roadmap".
- The ledger is "tamper-evident", never "tamper-proof".
- Payout = contribution × (members − 1): the collector receives from the other members.
- Payout order comes from the commit-reveal draw (docs/fair-draw.md once written); the admin may pledge to collect last.

## Design rules (website and app)
- Flat, white-first, blue accents. No gradients, neon, glows, glass, or large drop shadows; use hairline borders.
- Tokens: navy `#0B1A33`, royal blue `#1D4ED8`, mist `#F3F6FD`, sky `#7DC3E3`. Errors use blue/navy, not red.
- Adire line patterns for African identity. Plus Jakarta Sans; tabular figures for naira.
- Naira formatting: `₦120,000`. Nigerian phones normalised to `+234XXXXXXXXXX`.
- 21st.dev components (via the `21st` MCP) are React: use them directly on the website, as references only for Flutter. Strip gradients and shadows, recolour to the tokens.

## Repository layout
| Folder | What | Commands |
|---|---|---|
| `api/` | Fastify + TypeScript API | `npm run dev`, `npm test`, `npm run typecheck`, `npm run build` |
| `app/` | Flutter app (Android + web), package `ng.sova.app` | `flutter test`, `flutter analyze`, `flutter build web` |
| `website/` | Next.js marketing site + verify page | `npm run dev`, `npm run lint`, `npm run build` |
| `db/migrations/` | Ordered SQL migrations | applied by the API's migration runner |
| `docs/` | Status report and design docs | — |

## Engineering rules
- All configuration from environment variables, documented in each folder's `.env.example`. Never commit secrets.
- Validate every input with zod (API) and authorise every request against group membership and role.
- Hash PINs with argon2id. Rate-limit OTP and PIN endpoints. Never log PINs, OTPs, tokens or secrets.
- Business rules that guard money records live in the database (constraints, functions, triggers); the API wraps them rather than duplicating them.
- The app talks only to the `SovaRepository` interface; screens never call HTTP directly.
- Keep the demo repository for Flutter tests.
- Every phase ends with: tests passing (API, Flutter, website build), `docs/STATUS.md` updated, focused commits pushed.

## Commits
- Small, focused commits with clear imperative messages (one feature or fix each).
- Do not add `Co-Authored-By` trailers (owner's preference).
