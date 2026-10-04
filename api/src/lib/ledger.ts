import { createHash } from "node:crypto";

/**
 * The ledger's hash rule, mirrored from the database (ledger_hash), so the
 * chain can be checked outside it:
 *   hash = SHA-256(prev_hash + "|" + seq + "|" + kind + "|" + body), first prev_hash = 64 zeros
 */
export const GENESIS = "0".repeat(64);

export const ledgerHash = (prev: string, seq: number, kind: string, body: string) =>
  createHash("sha256").update(`${prev}|${seq}|${kind}|${body}`, "utf8").digest("hex");

export interface ChainEntry {
  seq: number;
  kind: string;
  body: string;
  prevHash: string;
  hash: string;
}

/** Returns the first broken entry's seq, or null when the whole chain checks out. */
export function firstBrokenEntry(entries: ChainEntry[]): number | null {
  let prev = GENESIS;
  for (const [i, e] of entries.entries()) {
    if (e.seq !== i + 1 || e.prevHash !== prev || ledgerHash(prev, e.seq, e.kind, e.body) !== e.hash) return e.seq;
    prev = e.hash;
  }
  return null;
}
