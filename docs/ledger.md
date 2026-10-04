# The tamper-evident ledger

Every circle in Sova has its own append-only ledger: a hash chain of everything that matters to its money. Anyone with a circle's link can download the chain and check it, without signing in and without trusting Sova's servers to do the checking.

The ledger is **tamper-evident, not tamper-proof**. It can't stop someone with full control of the database from rewriting a whole chain, but any change to a recorded entry breaks every hash after it, so edits are visible to anyone who saved an earlier chain head. Publishing chain heads somewhere Sova doesn't control is on the roadmap.

## What is recorded

Database triggers (`db/migrations/20261005000000_ledger.sql`) append an entry whenever one of these happens, so no code path can skip the ledger:

| Kind | When |
|---|---|
| `circle_created` | A circle is created (name, contribution, size, cycle, start date, admin, collect-last pledge) |
| `draw_committed` | The draw commitment is fixed (before anyone else joins) |
| `rules_published` | A rules version is published |
| `member_joined`, `member_vouched`, `rules_accepted` | Someone joins, is vouched for, accepts the rules |
| `draw_revealed` | The circle is full: the seed is revealed with the resulting payout order |
| `turn_opened` | A turn starts (turn number, collector, due date) |
| `payment_marked` | A member says they sent their contribution |
| `payment_confirmed` | The collector confirms it arrived |
| `payout_confirmed` | The collector confirms what reached them (expected, received, shortfall) |
| `dispute_opened` | A dispute opens (including automatically, for a short payout) |
| `circle_completed` | The last turn closes |

People appear as `{ "id": "<user id>", "name": "Ada O." }`: an opaque id (needed to check the draw) and first name plus initial. Phone numbers and bank details are never written to the ledger.

## The hash rule

Each entry has a sequence number `seq` (1, 2, 3, … per circle), a `kind`, and a `body`: the event as JSON text, stored exactly as it was hashed.

```
hash(seq) = SHA-256( prevHash + "|" + seq + "|" + kind + "|" + body )   (UTF-8)
prevHash(1) = "000…000" (64 zeros)
prevHash(n) = hash(n − 1)
```

The body is stored as text, not re-serialised, so a verifier hashes exactly the bytes Sova hashed.

## Append-only, enforced by the database

- `BEFORE UPDATE OR DELETE` and `BEFORE TRUNCATE` triggers refuse every change, for every database role including the owner.
- The API's restricted role (`sova_app`) additionally has no `UPDATE`, `DELETE` or `TRUNCATE` privilege on `ledger_entries` (the migration runner reads `append_only_tables`).
- `ledger_entries.group_id` references `groups` without cascade, so a circle with a ledger can't be deleted.
- The only exception: the demo seed may purge the ledgers of circles run by the reserved demo numbers (`+2348000000xxx`), and only after setting `sova.purge_demo = 'on'` in its transaction.
- Appends take a per-circle advisory lock, so sequence numbers never clash.

## Checking a circle

```
GET /public/circles/:id/ledger
```

returns the circle's name and status, the chain head, and every entry (`seq`, `kind`, `body`, `prevHash`, `hash`). The website's **Verify this circle** page (`/verify/?c=<circle id>`) downloads it and recomputes every hash in the browser with the Web Crypto API, then re-checks the fair draw from the chain alone (see [fair-draw.md](fair-draw.md)).

To check by hand:

```js
const { entries } = await (await fetch(`${API}/public/circles/${id}/ledger`)).json();
let prev = "0".repeat(64);
for (const e of entries) {
  const bytes = new TextEncoder().encode(`${prev}|${e.seq}|${e.kind}|${e.body}`);
  const hex = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (e.prevHash !== prev || hex !== e.hash) throw new Error(`entry ${e.seq} does not match`);
  prev = e.hash;
}
```

Tests: `api/test/ledger.test.ts` (chains verify, the draw re-checks from the chain, no phone numbers, changes refused even for the owner, a single altered entry is detected).
