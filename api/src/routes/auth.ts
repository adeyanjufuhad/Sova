import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import type { OtpService } from "../auth/otp.js";
import { requireUser, userIdOf } from "../auth/plugin.js";
import { assertStrongPin, hashPin, verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import { AppError, conflict, forbidden } from "../lib/errors.js";
import { displayPhone, normalisePhone } from "../lib/phone.js";
import { claimDemoSandbox, createDemoSandbox, topUpDemoSpares } from "../seed/demo.js";

const phoneField = z
  .string()
  .max(30)
  .transform((v, ctx) => {
    const phone = normalisePhone(v);
    if (!phone) {
      ctx.addIssue({ code: "custom", message: "Enter a Nigerian mobile number, like 0803 123 4567." });
      return z.NEVER;
    }
    return phone;
  });

const otpRequestBody = z.object({ phone: phoneField });
const otpVerifyBody = z.object({ phone: phoneField, code: z.string().regex(/^\d{6}$/, "Enter the 6-digit code.") });
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
const profileBody = z.object({
  fullName: z
    .string()
    .trim()
    .min(2, "Enter your name.")
    .max(80, "That name is too long.")
    .refine((v) => /\S+\s+\S+/.test(v), "Enter your first and last name."),
});
const pinBody = z.object({ pin: z.string() });
const bankBody = z.object({
  bankName: z.string().trim().min(2).max(80),
  accountNumber: z.string().trim().regex(/^\d{10}$/, "Account numbers are 10 digits."),
  accountName: z.string().trim().min(2, "Enter the name on the account.").max(80),
  /** Changing where payouts go is what a fraudster would try first, so it needs the PIN. */
  pin: z.string().regex(/^\d{4}$/, "Your PIN is 4 digits."),
});
const changePinBody = z.object({
  currentPin: z.string().regex(/^\d{4}$/, "Your PIN is 4 digits."),
  newPin: z.string(),
});

interface UserRow {
  id: string;
  /** Null for a private demo's people (and deleted accounts). */
  phone: string | null;
  full_name: string | null;
  pin_hash: string | null;
  is_demo: boolean;
  bank_name: string | null;
  account_number: string | null;
  account_name: string | null;
  tours_done: string[];
}

const USER_COLUMNS = "id, phone, full_name, pin_hash, is_demo, bank_name, account_number, account_name, tours_done";

/** Guided tours in the app; see db/migrations/20261013000000_tours.sql. */
const TOURS = ["home", "circle"] as const;
const tourParam = z.object({ tour: z.enum(TOURS) });

/**
 * `demoPhone` is shown as the number of a private demo's member, who has none.
 * `assistant` says whether "Ask Sova" is switched on for this API.
 */
export const toUser = (u: UserRow, demoPhone: string, assistant = false) => ({
  id: u.id,
  phone: u.phone ?? (u.is_demo ? demoPhone : ""),
  fullName: u.full_name,
  hasPin: u.pin_hash !== null,
  isDemo: u.is_demo,
  bank: u.account_number ? { bankName: u.bank_name, accountNumber: u.account_number, accountName: u.account_name } : null,
  toursDone: u.tours_done,
  assistant,
});

/** Per-IP limits for sensitive endpoints, on top of the per-phone limits in the database. */
const strict = { rateLimit: { max: 5, timeWindow: "1 minute" } };
const moderate = { rateLimit: { max: 20, timeWindow: "1 minute" } };

export async function authRoutes(
  app: FastifyInstance,
  opts: {
    pool: pg.Pool;
    otp: OtpService;
    tokens: TokenService;
    demoEnabled: boolean;
    demoPhone: string;
    demoSpares: number;
    assistantOn?: boolean;
  },
) {
  const { pool, otp, tokens } = opts;
  const auth = requireUser(tokens);
  const view = (u: UserRow) => toUser(u, opts.demoPhone, opts.assistantOn ?? false);

  const findUser = async (id: string) => {
    const { rows } = await pool.query<UserRow>(`select ${USER_COLUMNS} from users where id = $1 and deleted_at is null`, [
      id,
    ]);
    if (!rows[0]) throw new AppError(401, "unauthorized", "Please sign in again.");
    return rows[0];
  };

  app.post("/auth/otp/request", { config: strict }, async (req, reply) => {
    const { phone } = otpRequestBody.parse(req.body);
    const result = await otp.request(phone);
    return reply.code(202).send({ sentTo: displayPhone(phone), ...result });
  });

  app.post("/auth/otp/verify", { config: strict }, async (req) => {
    const { phone, code } = otpVerifyBody.parse(req.body);
    await otp.verify(phone, code);
    const { rows } = await pool.query<UserRow>(
      `insert into users (phone) values ($1)
       on conflict (phone) do update set phone = excluded.phone
       returning ${USER_COLUMNS}`,
      [phone],
    );
    const user = rows[0]!;
    return { ...(await tokens.issue(user.id, req.headers["user-agent"])), user: view(user) };
  });

  /** Builds the next spare demo copy in the background, one top-up at a time. */
  let refilling: Promise<void> | null = null;
  const refillSpares = () => {
    if (!opts.demoSpares || refilling) return;
    refilling = topUpDemoSpares(pool, opts.demoSpares)
      .then(
        () => undefined,
        (err) => app.log.error({ err }, "demo: spare copy not built"),
      )
      .finally(() => {
        refilling = null;
      });
  };

  /**
   * "Try the demo": a private copy of the demo world for this visitor (see
   * createDemoSandbox), so nothing they do reaches the next visitor. A spare
   * built in advance is claimed when one is ready (instant); otherwise one is
   * built now. It lasts SANDBOX_TTL_HOURS; tapping "Try the demo" again starts
   * a fresh one.
   */
  app.post("/auth/demo", { config: strict }, async (req) => {
    if (!opts.demoEnabled) throw new AppError(404, "demo_disabled", "The demo is not available here.");
    const adaId = (await claimDemoSandbox(pool)) ?? (await createDemoSandbox(pool));
    if (!adaId) throw new AppError(503, "demo_busy", "The demo is busy right now. Please try again in a few minutes.");
    refillSpares();
    return { ...(await tokens.issue(adaId, req.headers["user-agent"])), user: view(await findUser(adaId)) };
  });

  app.post("/auth/refresh", { config: moderate }, async (req) => {
    const { refreshToken } = refreshBody.parse(req.body);
    const { userId, tokens: pair } = await tokens.rotate(refreshToken, req.headers["user-agent"]);
    return { ...pair, user: view(await findUser(userId)) };
  });

  app.post("/auth/logout", async (req, reply) => {
    const { refreshToken } = refreshBody.parse(req.body);
    await tokens.revoke(refreshToken);
    return reply.code(204).send();
  });

  app.get("/me", { preHandler: auth }, async (req) => view(await findUser(userIdOf(req))));

  /** A guided tour was finished or skipped; it isn't offered again (the app can still replay it). */
  app.post("/me/tours/:tour", { preHandler: auth, config: moderate }, async (req, reply) => {
    const { tour } = tourParam.parse(req.params);
    await pool.query(
      "update users set tours_done = array_append(tours_done, $2) where id = $1 and not ($2 = any(tours_done))",
      [userIdOf(req), tour],
    );
    return reply.code(204).send();
  });

  /**
   * Everyone who taps "Try the demo" shares one account, so its name, bank
   * details and PIN stay as seeded: one visitor can't lock out the next.
   */
  const assertNotDemo = async (userId: string) => {
    const { rows } = await pool.query<{ is_demo: boolean }>("select is_demo from users where id = $1", [userId]);
    if (rows[0]?.is_demo) {
      throw forbidden("This is the shared demo account, so its name, bank details and PIN can't be changed.");
    }
  };

  app.patch("/me", { preHandler: auth }, async (req) => {
    const { fullName } = profileBody.parse(req.body);
    await assertNotDemo(userIdOf(req));
    const { rows } = await pool.query<UserRow>(
      `update users set full_name = $2 where id = $1 returning ${USER_COLUMNS}`,
      [userIdOf(req), fullName],
    );
    return view(rows[0]!);
  });

  /** Where this person receives their payout. */
  app.put("/me/bank", { preHandler: auth, config: moderate }, async (req) => {
    const body = bankBody.parse(req.body);
    await assertNotDemo(userIdOf(req));
    await verifyPin(pool, userIdOf(req), body.pin);
    const bank = await pool.query<{ name: string }>("select name from nigerian_banks where lower(name) = lower($1)", [body.bankName]);
    if (!bank.rows[0]) throw new AppError(400, "unknown_bank", "Choose a bank from the list.");
    const { rows } = await pool.query<UserRow>(
      `update users set bank_name = $2, account_number = $3, account_name = $4 where id = $1 returning ${USER_COLUMNS}`,
      [userIdOf(req), bank.rows[0].name, body.accountNumber, body.accountName],
    );
    return view(rows[0]!);
  });

  app.get("/banks", async () => {
    const { rows } = await pool.query<{ id: number; name: string }>("select id, name from nigerian_banks order by name");
    return { banks: rows };
  });

  /** First-time PIN. Changing an existing PIN goes through /me/pin/change. */
  app.post("/me/pin", { preHandler: auth, config: strict }, async (req) => {
    const { pin } = pinBody.parse(req.body);
    assertStrongPin(pin);
    const { rows } = await pool.query<UserRow>(
      `update users set pin_hash = $2 where id = $1 and pin_hash is null
       returning ${USER_COLUMNS}`,
      [userIdOf(req), await hashPin(pin)],
    );
    if (!rows[0]) throw conflict("pin_already_set", "You already have a PIN.");
    return view(rows[0]);
  });

  /** Changes the PIN: the current one must be right (wrong tries count towards the lockout). */
  app.post("/me/pin/change", { preHandler: auth, config: strict }, async (req, reply) => {
    const me = userIdOf(req);
    const { currentPin, newPin } = changePinBody.parse(req.body);
    assertStrongPin(newPin);
    await assertNotDemo(me);
    await verifyPin(pool, me, currentPin);
    if (newPin === currentPin) throw new AppError(400, "same_pin", "Choose a PIN that's different from your current one.");
    await pool.query("select change_pin($1, $2)", [me, await hashPin(newPin)]);
    return reply.code(204).send();
  });

  app.post("/me/pin/verify", { preHandler: auth, config: strict }, async (req, reply) => {
    const { pin } = pinBody.parse(req.body);
    if (!/^\d{4}$/.test(pin)) throw new AppError(400, "invalid_pin", "Your PIN is 4 digits.");
    await verifyPin(pool, userIdOf(req), pin);
    return reply.code(204).send();
  });
}
