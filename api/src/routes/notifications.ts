import type { FastifyInstance } from "fastify";
import type pg from "pg";

import { requireUser, userIdOf } from "../auth/plugin.js";
import type { TokenService } from "../auth/tokens.js";

/**
 * In-app notifications. Stored ones are written by database triggers (see
 * db/migrations/20261009000000_notifications.sql). Reminders are worked out
 * here on every read, from what the member owes and must confirm right now,
 * so they never go stale and no scheduler is needed.
 */

const naira = (n: number) => `₦${n.toLocaleString("en-NG")}`;
/** Today in Nigeria, as YYYY-MM-DD. */
const todayInLagos = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Lagos" }).format(new Date());
const dayLabel = (iso: string) =>
  new Intl.DateTimeFormat("en-NG", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(`${iso}T00:00:00Z`));

/** Days from today to the due date (negative when overdue). */
const daysUntil = (iso: string) => Math.round((Date.parse(`${iso}T00:00:00Z`) - Date.parse(`${todayInLagos()}T00:00:00Z`)) / 86_400_000);

export async function notificationRoutes(app: FastifyInstance, opts: { pool: pg.Pool; tokens: TokenService }) {
  const { pool } = opts;
  app.addHook("preHandler", requireUser(opts.tokens));

  async function reminders(me: string) {
    const [owed, toConfirm] = await Promise.all([
      pool.query<{ circle_id: string; circle_name: string; turn: number; due: string; collector: string | null; amount: number }>(
        `select g.id as circle_id, g.name as circle_name, r.round_number as turn, r.due_date::text as due,
                cu.full_name as collector, g.contribution_amount as amount
           from rounds r
           join groups g on g.id = r.group_id
           join group_members m on m.group_id = g.id and m.user_id = $1
           join users cu on cu.id = r.collector_id
           left join contributions c on c.round_id = r.id and c.user_id = $1
          where r.status = 'active' and r.collector_id <> $1 and (c.id is null or c.status = 'pending')
            and r.due_date <= $2::date + 2
          order by r.due_date`,
        [me, todayInLagos()],
      ),
      pool.query<{ circle_id: string; circle_name: string; n: number }>(
        `select g.id as circle_id, g.name as circle_name, count(*)::int as n
           from rounds r
           join groups g on g.id = r.group_id
           join contributions c on c.round_id = r.id and c.status = 'payer_confirmed'
          where r.status = 'active' and r.collector_id = $1
          group by g.id, g.name`,
        [me],
      ),
    ]);
    return [
      ...owed.rows.map((o) => {
        const days = daysUntil(o.due);
        const who = (o.collector ?? "the collector").split(" ")[0];
        return {
          kind: days < 0 ? "overdue" : "due",
          title: `Pay ${who} ${naira(o.amount)}`,
          message:
            days < 0
              ? `${o.circle_name}, turn ${o.turn}. ${-days} day${days === -1 ? "" : "s"} late: it was due ${dayLabel(o.due)}.`
              : `${o.circle_name}, turn ${o.turn}. Due ${days === 0 ? "today" : days === 1 ? "tomorrow" : dayLabel(o.due)}.`,
          circleId: o.circle_id,
          link: `/circle/${o.circle_id}/pay`,
          dueDate: o.due,
        };
      }),
      ...toConfirm.rows.map((t) => ({
        kind: "confirm",
        title: `${t.n} payment${t.n === 1 ? "" : "s"} to confirm`,
        message: `${t.circle_name}. Check your bank, then confirm what arrived.`,
        circleId: t.circle_id,
        link: `/circle/${t.circle_id}`,
        dueDate: null,
      })),
    ];
  }

  app.get("/me/notifications", async (req) => {
    const me = userIdOf(req);
    const [items, due] = await Promise.all([
      pool.query<{
        id: string;
        type: string;
        title: string;
        message: string;
        link: string | null;
        group_id: string | null;
        read: boolean;
        created_at: Date;
      }>(
        `select id, type, title, message, link, group_id, read, created_at
           from notifications where user_id = $1 order by created_at desc limit 50`,
        [me],
      ),
      reminders(me),
    ]);
    return {
      reminders: due,
      items: items.rows.map((n) => ({
        id: n.id,
        type: n.type,
        title: n.title,
        message: n.message,
        link: n.link,
        circleId: n.group_id,
        read: n.read,
        createdAt: n.created_at,
      })),
      /** What the bell shows: unread notifications plus reminders. */
      badge: items.rows.filter((n) => !n.read).length + due.length,
    };
  });

  /** Marks everything as read (the list was opened). */
  app.post("/me/notifications/read", async (req, reply) => {
    await pool.query("update notifications set read = true where user_id = $1 and not read", [userIdOf(req)]);
    return reply.code(204).send();
  });
}
