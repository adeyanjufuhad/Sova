# The fair payout draw

In an ajo, the order of payouts is everything: collecting early is an interest-free loan, collecting last is a favour to the group. Sova decides the order with a **commit-reveal draw** that no one, including the admin, can steer after seeing who joined, and that any member can check.

## How it works

1. **Commit (when the circle is created).** Sova picks a random 32-byte seed and publishes only its fingerprint:
   `commitment = SHA-256(seed bytes)`.
   The commitment is shown to everyone who previews the circle and is written to the ledger (`draw_committed`) before anyone joins, the admin included. The seed stays secret.
2. **Fill.** Members join with the invite code and accept the rules. Turns show as "not drawn yet".
3. **Reveal (when the circle is full and everyone accepted the rules).** The database orders members by
   `key = SHA-256(seed_hex + ":" + user_id)` (UTF-8, compared as lowercase hex, byte order),
   gives turn 1 to the smallest key, reveals the seed and opens turn 1. The ledger records `draw_revealed` with the seed and the order.
4. **Collect-last pledge.** If the admin pledged to collect last when creating the circle, they take the last turn and everyone else is ordered by key. The pledge is part of `circle_created`, so it can't be added later.

Code: `run_draw` and `draw_key` in `db/migrations/20261004000000_circle_lifecycle.sql`; the same rule in TypeScript in `api/src/lib/draw.ts`.

## Checking a draw

Anyone with the circle's ledger can check:

1. `SHA-256(seed bytes)` equals the `commitment` recorded earlier in the chain.
2. Recomputing every member's key from the revealed seed and their id gives exactly the recorded order (with the admin last if they pledged).
3. The `draw_committed` entry comes before every `member_joined` entry, so the seed was fixed before anyone joined.

The website's **Verify this circle** page does all three in the browser.

## What it protects against, and what it doesn't

- **The admin can't pick their friends' turns.** The order comes from a seed fixed before anyone joined, and the admin never sees it.
- **Nobody can redraw.** The commitment is in the ledger; a different seed wouldn't match it.
- **It trusts Sova not to leak the seed early.** Sova generates and holds the seed until the reveal. Mixing in randomness from members (for example from their join entries) would remove that trust; it's a possible improvement.
- **Demo data:** the seeded demo circles that already started use a seed searched to reproduce their scripted payout order, so the demo story stays the same and their draws still verify. Real circles always get a fresh random seed.
