import { exportJWK, generateKeyPair, SignJWT, createLocalJWKSet } from "jose";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildApp, type AppOverrides } from "../src/app.js";
import { BrevoEmailProvider } from "../src/auth/email.js";
import { GoogleIdTokenVerifier, type GoogleIdentity } from "../src/auth/google.js";
import { loadConfig, parseSender } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

const EMAIL = "ada@example.com";
const CODE = "246810";

let db: Awaited<ReturnType<typeof freshDatabase>>;

const config = (extra: Record<string, string> = {}) =>
  loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
    ...extra,
  });

let ip = 0;
const nextIp = () => `10.1.${Math.floor(++ip / 250)}.${ip % 250}`;

const withEmail = { EMAIL_PROVIDER: "test-emails", OTP_TEST_EMAILS: `${EMAIL}:${CODE},bola@example.com:135790` };

async function newApp(extra: Record<string, string> = {}, overrides: AppOverrides = {}) {
  return buildApp(config(extra), db.pool, overrides);
}

async function emailSignIn(app: FastifyInstance, email = EMAIL, code = CODE) {
  const req = await app.inject({ method: "POST", url: "/auth/email/request", payload: { email }, remoteAddress: nextIp() });
  expect(req.statusCode).toBe(202);
  const res = await app.inject({ method: "POST", url: "/auth/email/verify", payload: { email, code }, remoteAddress: nextIp() });
  expect(res.statusCode).toBe(200);
  return res.json() as { accessToken: string; user: { id: string; email: string | null; phone: string } };
}

/** Stands in for Google: any token "ok:<sub>:<email>" signs in as that account. */
const fakeGoogle = {
  async verify(token: string): Promise<GoogleIdentity> {
    const [, sub, email] = token.split(":");
    return { sub: sub!, email: email!, name: "Ada Obi" };
  },
};

const googleSignIn = (app: FastifyInstance, sub: string, email: string) =>
  app.inject({
    method: "POST",
    url: "/auth/google",
    payload: { idToken: `ok:${sub}:${email}`.padEnd(24, "-") },
    remoteAddress: nextIp(),
  });

beforeAll(async () => {
  db = await freshDatabase();
});
afterAll(async () => db.drop());
beforeEach(async () => {
  await db.pool.query("delete from otp_challenges");
});

describe("sign-in methods", () => {
  it("say email and Google are off until configured", async () => {
    const app = await newApp();
    const res = await app.inject({ method: "GET", url: "/auth/methods" });
    expect(res.json()).toMatchObject({ phone: true, email: false, google: null });

    const email = await app.inject({ method: "POST", url: "/auth/email/request", payload: { email: EMAIL } });
    expect(email.statusCode).toBe(503);
    expect(email.json().error.code).toBe("email_not_configured");

    const google = await app.inject({ method: "POST", url: "/auth/google", payload: { idToken: "x".repeat(30) } });
    expect(google.statusCode).toBe(503);
    expect(google.json().error.code).toBe("google_not_configured");
  });

  it("list Google with the web client id once it is set", async () => {
    const app = await newApp({ ...withEmail, GOOGLE_CLIENT_IDS: "web-id.apps.googleusercontent.com,android-id" });
    const res = await app.inject({ method: "GET", url: "/auth/methods" });
    expect(res.json()).toMatchObject({ email: true, google: { clientId: "web-id.apps.googleusercontent.com" } });
  });
});

describe("email codes", () => {
  it("sign in, make one account per email, and ignore case", async () => {
    const app = await newApp(withEmail);
    const first = await emailSignIn(app);
    expect(first.user.email).toBe(EMAIL);
    expect(first.user.phone).toBe("");
    const again = await emailSignIn(app, "  Ada@Example.COM ");
    expect(again.user.id).toBe(first.user.id);
  });

  it("refuse wrong codes and addresses outside the beta", async () => {
    const app = await newApp(withEmail);
    await app.inject({ method: "POST", url: "/auth/email/request", payload: { email: EMAIL }, remoteAddress: nextIp() });
    const wrong = await app.inject({
      method: "POST",
      url: "/auth/email/verify",
      payload: { email: EMAIL, code: "000000" },
      remoteAddress: nextIp(),
    });
    expect(wrong.statusCode).toBe(400);
    expect(wrong.json().error.code).toBe("wrong_code");

    const outside = await app.inject({
      method: "POST",
      url: "/auth/email/request",
      payload: { email: "someone@else.com" },
      remoteAddress: nextIp(),
    });
    expect(outside.statusCode).toBe(403);

    const invalid = await app.inject({ method: "POST", url: "/auth/email/request", payload: { email: "not-an-email" } });
    expect(invalid.statusCode).toBe(400);
  });

  it("are limited per address", async () => {
    const app = await newApp(withEmail);
    for (let i = 0; i < 3; i++) {
      const ok = await app.inject({ method: "POST", url: "/auth/email/request", payload: { email: EMAIL }, remoteAddress: nextIp() });
      expect(ok.statusCode).toBe(202);
    }
    const limited = await app.inject({ method: "POST", url: "/auth/email/request", payload: { email: EMAIL }, remoteAddress: nextIp() });
    expect(limited.statusCode).toBe(429);
  });
});

describe("Brevo email sender", () => {
  it("posts the code to the address and reports failures without leaking them", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const ok = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response("{}", { status: 201 });
    }) as unknown as typeof fetch;
    const sender = new BrevoEmailProvider("key-123", { email: "sova@example.com", name: "Sova" }, 5, ok);
    const code = sender.codeFor();
    expect(code).toMatch(/^\d{6}$/);
    await sender.send(EMAIL, code);
    expect(calls[0]!.url).toBe("https://api.brevo.com/v3/smtp/email");
    expect((calls[0]!.init.headers as Record<string, string>)["api-key"]).toBe("key-123");
    const body = JSON.parse(calls[0]!.init.body as string);
    expect(body.to).toEqual([{ email: EMAIL }]);
    expect(body.sender).toEqual({ email: "sova@example.com", name: "Sova" });
    expect(body.textContent).toContain(code);

    const failing = (async () => new Response("nope", { status: 401 })) as unknown as typeof fetch;
    const broken = new BrevoEmailProvider("bad", { email: "sova@example.com", name: "Sova" }, 5, failing);
    await expect(broken.send(EMAIL, "123456")).rejects.toMatchObject({ code: "email_unavailable" });
  });

  it("reads the sender from EMAIL_FROM", () => {
    expect(parseSender("Sova <Sova.App@Gmail.com>")).toEqual({ email: "sova.app@gmail.com", name: "Sova" });
    expect(parseSender("sova@example.com")).toEqual({ email: "sova@example.com", name: "Sova" });
    expect(parseSender("not an address")).toBeNull();
    expect(() => config({ EMAIL_PROVIDER: "brevo" })).toThrow(/BREVO_API_KEY/);
  });
});

describe("Google sign-in", () => {
  it("makes an account, finds it again, and links it to the same email's account", async () => {
    const app = await newApp(withEmail, { google: fakeGoogle });
    const byEmail = await emailSignIn(app, "bola@example.com", "135790");

    const linked = await googleSignIn(app, "google-bola", "bola@example.com");
    expect(linked.statusCode).toBe(200);
    expect(linked.json().user.id).toBe(byEmail.user.id);
    expect(linked.json().suggestedName).toBe("Ada Obi");

    const fresh = await googleSignIn(app, "google-chika", "chika@example.com");
    const again = await googleSignIn(app, "google-chika", "chika@example.com");
    expect(again.json().user.id).toBe(fresh.json().user.id);
    expect(fresh.json().user.email).toBe("chika@example.com");
  });

  it("checks Google's signature, audience and verified email", async () => {
    const { publicKey, privateKey } = await generateKeyPair("RS256");
    const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" };
    const verifier = new GoogleIdTokenVerifier(["sova-web"], createLocalJWKSet({ keys: [jwk] }));
    const token = (claims: Record<string, unknown>, aud = "sova-web", iss = "https://accounts.google.com") =>
      new SignJWT(claims)
        .setProtectedHeader({ alg: "RS256", kid: "k1" })
        .setIssuer(iss)
        .setAudience(aud)
        .setSubject("12345")
        .setIssuedAt()
        .setExpirationTime("5m")
        .sign(privateKey);

    await expect(verifier.verify(await token({ email: "Ada@Example.com", email_verified: true, name: "Ada Obi" }))).resolves.toEqual({
      sub: "12345",
      email: "ada@example.com",
      name: "Ada Obi",
    });
    await expect(verifier.verify(await token({ email: EMAIL, email_verified: true }, "someone-else"))).rejects.toMatchObject({
      code: "google_invalid",
    });
    await expect(verifier.verify(await token({ email: EMAIL, email_verified: false }))).rejects.toMatchObject({
      code: "google_invalid",
    });
    await expect(
      verifier.verify(await token({ email: EMAIL, email_verified: true }, "sova-web", "https://evil.example")),
    ).rejects.toMatchObject({ code: "google_invalid" });
  });
});

describe("deleting an account made with email or Google", () => {
  it("forgets the email and the Google account id", async () => {
    const app = await newApp(withEmail, { google: fakeGoogle });
    const res = await googleSignIn(app, "google-dele", "dele@example.com");
    const id = res.json().user.id as string;
    await db.pool.query("select delete_account($1)", [id]);
    const { rows } = await db.pool.query("select email, google_sub, deleted_at from users where id = $1", [id]);
    expect(rows[0]).toMatchObject({ email: null, google_sub: null });
    expect(rows[0].deleted_at).not.toBeNull();
  });
});
