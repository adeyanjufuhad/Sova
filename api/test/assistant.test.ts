import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { AssistantUnavailable, parseReply, shortName, type Assistant, type ChatMessage } from "../src/lib/assistant.js";
import { freshDatabase } from "./setup/db.js";

/** Stands in for RumptyCloud's model service and keeps every prompt it was sent. */
class FakeAssistant implements Assistant {
  readonly model = "fake-model";
  readonly prompts: ChatMessage[][] = [];
  fail = false;
  async reply(messages: ChatMessage[]) {
    if (this.fail) throw new AssistantUnavailable("model service answered 503");
    this.prompts.push(messages);
    return "Here is how your circle works.";
  }
  get lastData() {
    return this.prompts.at(-1)!.find((m) => m.role === "user")!.content;
  }
}

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000031", name: "Ada Obi" },
  bayo: { phone: "+2348000000032", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000033", name: "Chuka Eze" },
  dayo: { phone: "+2348000000034", name: "Dayo Ola" },
} as const;
type Person = keyof typeof PEOPLE;

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
let appOff: FastifyInstance;
const assistant = new FakeAssistant();
const tokens = {} as Record<Person, string>;

let ip = 0;
const nextIp = () => `10.7.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(who: Person | null, method: "GET" | "POST" | "PATCH" | "PUT", url: string, payload?: object, on = app) {
  const res = await on.inject({
    method,
    url,
    payload,
    remoteAddress: nextIp(),
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.statusCode === 204 ? null : res.json() };
}

async function signIn(who: Person) {
  const p = PEOPLE[who];
  await call(null, "POST", "/auth/otp/request", { phone: p.phone });
  const signed = await call(null, "POST", "/auth/otp/verify", { phone: p.phone, code: "123456" });
  tokens[who] = signed.body.accessToken;
  await call(who, "PATCH", "/me", { fullName: p.name });
  await call(who, "POST", "/me/pin", { pin: PIN });
}

const rawConfig = () => ({
  NODE_ENV: "test",
  LOG_LEVEL: "silent",
  JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
  OTP_TEST_NUMBERS: Object.values(PEOPLE).map((p) => `${p.phone}:123456`).join(","),
});
const config = () => loadConfig(rawConfig());

beforeAll(async () => {
  db = await freshDatabase();
  app = await buildApp(config(), db.pool, { storage: null, assistant });
  appOff = await buildApp(config(), db.pool, { storage: null, assistant: null });
  for (const who of Object.keys(PEOPLE) as Person[]) await signIn(who);
});
afterAll(async () => db.drop());

describe("guided tours", () => {
  it("starts with none done, remembers finished ones once, and refuses unknown tours", async () => {
    expect((await call("dayo", "GET", "/me")).body.toursDone).toEqual([]);
    expect((await call("dayo", "POST", "/me/tours/home")).status).toBe(204);
    expect((await call("dayo", "POST", "/me/tours/home")).status).toBe(204);
    expect((await call("dayo", "POST", "/me/tours/circle")).status).toBe(204);
    expect((await call("dayo", "GET", "/me")).body.toursDone).toEqual(["home", "circle"]);
    expect((await call("dayo", "POST", "/me/tours/everything")).status).toBe(400);
    expect((await call(null, "POST", "/me/tours/home")).status).toBe(401);
  });
});

describe("Ask Sova", () => {
  let circleId: string;

  beforeAll(async () => {
    const banks = await call(null, "GET", "/banks");
    await call("ada", "PUT", "/me/bank", {
      bankName: banks.body.banks[0].name,
      accountNumber: "0123456789",
      accountName: "Ada Obi",
      pin: PIN,
    });
    const created = await call("ada", "POST", "/circles", {
      name: "Assistant Ajo",
      contributionAmount: 5000,
      memberCount: 3,
      cycleType: "weekly",
      startDate: new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10),
      pin: PIN,
    });
    circleId = created.body.id;
    for (const who of ["bayo", "chuka"] as const) {
      await call(who, "POST", "/circles/join", { code: created.body.inviteCode, rulesVersion: 1, pin: PIN });
    }
  });

  it("says on /me whether it is switched on", async () => {
    expect((await call("ada", "GET", "/me")).body.assistant).toBe(true);
    expect((await call("ada", "GET", "/me", undefined, appOff)).body.assistant).toBe(false);
  });

  it("explains a circle from its record, without phones or bank details", async () => {
    const res = await call("bayo", "POST", "/assistant/explain", { topic: "circle", circleId, language: "pcm" });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ text: "Here is how your circle works.", model: "fake-model", language: "pcm" });

    const data = assistant.lastData;
    expect(data).toContain("Circle: Assistant Ajo. Status: active.");
    expect(data).toContain("collects ₦10,000");
    expect(data).toContain("The collector keeps all of it");
    expect(data).toContain("Ada O.");
    expect(data).toContain("This turn: turn 1 of 3.");
    expect(data).toContain("Open disputes: none.");
    expect(data).toContain("YOU = the member asking.");
    expect(data).not.toContain("Bayo A."); // the asker is "YOU", never their name
    // The next step is worked out by the API, not left to the model.
    expect(data).toMatch(/What you should do now: (you have not paid this turn\. Send ₦5,000 to \w+ \w\.|you are collecting this turn)/);
    expect(data).not.toMatch(/\+234|0123456789|Obi|Adeyemi/);
    expect(assistant.prompts.at(-1)![0]!.content).toContain("Nigerian Pidgin");
  });

  it("answers a question about how Sova works", async () => {
    const res = await call("chuka", "POST", "/assistant/explain", { topic: "question", question: "Who holds the money?" });
    expect(res.status).toBe(200);
    expect(assistant.lastData).toContain("My question: Who holds the money?");
    expect(assistant.lastData).toContain("Sova does not give loans.");
    expect(assistant.prompts.at(-1)![0]!.content).toContain("Sova never holds, moves, lends or invests money");
  });

  it("keeps circles private and checks the request", async () => {
    expect((await call("dayo", "POST", "/assistant/explain", { topic: "circle", circleId })).status).toBe(404);
    expect((await call("ada", "POST", "/assistant/explain", { topic: "circle" })).status).toBe(400);
    expect((await call("ada", "POST", "/assistant/explain", { topic: "question", question: "x".repeat(301) })).status).toBe(400);
    expect((await call(null, "POST", "/assistant/explain", { topic: "question", question: "Hello?" })).status).toBe(401);
  });

  it("explains when it is off or the model service is down", async () => {
    const off = await call("ada", "POST", "/assistant/explain", { topic: "circle", circleId }, appOff);
    expect(off.status).toBe(503);
    expect(off.body.error.code).toBe("assistant_off");

    assistant.fail = true;
    const down = await call("ada", "POST", "/assistant/explain", { topic: "circle", circleId });
    assistant.fail = false;
    expect(down.status).toBe(502);
    expect(down.body.error.code).toBe("assistant_unavailable");
  });
});

describe("Ask Sova daily limits", () => {
  let limited: FastifyInstance;
  const ask = (who: Person) =>
    call(who, "POST", "/assistant/explain", { topic: "question", question: "Who holds the money?" }, limited);
  const usedToday = async () =>
    (await db.pool.query<{ n: number }>("select coalesce(sum(answers), 0)::int as n from assistant_days")).rows[0]!.n;

  beforeAll(async () => {
    limited = await buildApp(loadConfig({ ...rawConfig(), AI_DAILY_LIMIT: "2", AI_DAILY_TOTAL: "3" }), db.pool, {
      storage: null,
      assistant,
    });
    await db.pool.query("delete from assistant_usage; delete from assistant_days");
  });

  it("caps each member and then the whole service, counted in the database", async () => {
    expect((await ask("ada")).status).toBe(200);
    expect((await ask("ada")).status).toBe(200);
    const third = await ask("ada");
    expect(third.status).toBe(429);
    expect(third.body.error.code).toBe("assistant_limit");

    expect((await ask("bayo")).status).toBe(200);
    const busy = await ask("chuka");
    expect(busy.status).toBe(429);
    expect(busy.body.error.code).toBe("assistant_busy");
    expect(await usedToday()).toBe(3);
  });

  it("gives the answer back when the model service fails", async () => {
    await db.pool.query("delete from assistant_usage; delete from assistant_days");
    assistant.fail = true;
    expect((await ask("dayo")).status).toBe(502);
    assistant.fail = false;
    expect(await usedToday()).toBe(0);
  });
});

describe("assistant helpers", () => {
  it("reads both plain and streamed chat replies", () => {
    expect(parseReply(JSON.stringify({ choices: [{ message: { content: " Hello. " } }] }))).toBe("Hello.");
    const sse = [
      'data: {"choices":[{"delta":{"content":"Hel"}}]}',
      'data: {"choices":[{"delta":{"content":"lo."}}]}',
      "data: [DONE]",
    ].join("\n");
    expect(parseReply(sse)).toBe("Hello.");
  });

  it("shortens names the way the public ledger does", () => {
    expect(shortName("Ada Obi")).toBe("Ada O.");
    expect(shortName("Chukwuemeka")).toBe("Chukwuemeka");
    expect(shortName(null)).toBe("A member");
  });
});
