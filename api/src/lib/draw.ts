import { createHash, randomBytes, randomInt } from "node:crypto";

/**
 * The fair payout draw, mirrored from the database (run_draw, draw_key) so it
 * can be checked outside it:
 *   commitment = SHA-256(seed bytes), published when the circle is created
 *   key(member) = SHA-256(seed_hex + ":" + user_id), turns in ascending key order
 *   an admin who pledged to collect last goes last
 */

export const newSeed = () => randomBytes(32).toString("hex");

export const commitmentOf = (seedHex: string) => createHash("sha256").update(Buffer.from(seedHex, "hex")).digest("hex");

export const drawKey = (seedHex: string, userId: string) => createHash("sha256").update(`${seedHex}:${userId}`, "utf8").digest("hex");

/** Member ids in payout order (turn 1 first). */
export function drawOrder(seedHex: string, userIds: string[], adminId: string, adminCollectsLast: boolean): string[] {
  const last = (id: string) => (adminCollectsLast && id === adminId ? 1 : 0);
  return userIds
    .map((id) => ({ id, key: drawKey(seedHex, id) }))
    .sort((a, b) => last(a.id) - last(b.id) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map((m) => m.id);
}

/** Invite codes avoid look-alike characters (no 0/O, 1/I/L); matches groups_invite_code_format. */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export const newInviteCode = () => Array.from({ length: 6 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
