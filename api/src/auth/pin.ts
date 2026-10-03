import { hash, verify } from "@node-rs/argon2";
import type pg from "pg";

import { AppError } from "../lib/errors.js";

/** Four digits, not trivially guessable. Mirrors the app's rule. */
export function assertStrongPin(pin: string): void {
  if (!/^\d{4}$/.test(pin)) throw new AppError(400, "invalid_pin", "Your PIN must be exactly 4 digits.");
  const weak = /^(\d)\1{3}$/.test(pin) || pin === "1234";
  if (weak) throw new AppError(400, "weak_pin", "That PIN is too easy to guess. Choose another.");
}

/** argon2id with the library's defaults (memory-hard; tuned for interactive logins). */
export const hashPin = (pin: string) => hash(pin);

/**
 * Checks a PIN using the database lockout (5 wrong tries locks it for 15
 * minutes; see check_and_increment_pin_attempts). Throws 423 when locked,
 * 401 with attempts left when wrong.
 */
export async function verifyPin(pool: pg.Pool, userId: string, pin: string): Promise<void> {
  const { rows } = await pool.query<{ pin_hash: string | null }>("select pin_hash from users where id = $1", [userId]);
  const pinHash = rows[0]?.pin_hash;
  if (!pinHash) throw new AppError(409, "pin_not_set", "Create your PIN first.");

  const lock = await pool.query<{ locked: boolean; attempts: number; locked_until: Date | null }>(
    "select * from check_and_increment_pin_attempts($1)",
    [userId],
  );
  const state = lock.rows[0]!;
  if (state.locked) {
    throw new AppError(423, "pin_locked", "Too many wrong tries. Your PIN is locked for a few minutes.", {
      lockedUntil: state.locked_until?.toISOString() ?? null,
    });
  }

  if (await verify(pinHash, pin)) {
    await pool.query("select reset_pin_attempts($1)", [userId]);
    return;
  }

  if (state.locked_until) {
    throw new AppError(423, "pin_locked", "Too many wrong tries. Your PIN is locked for 15 minutes.", {
      lockedUntil: state.locked_until.toISOString(),
    });
  }
  const left = 5 - state.attempts;
  throw new AppError(401, "wrong_pin", `Wrong PIN. ${left} ${left === 1 ? "try" : "tries"} left.`, { attemptsLeft: left });
}
