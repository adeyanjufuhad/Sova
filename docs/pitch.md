# Pitch prep

For live demo day (7 November 2026) and any judge Q&A before it. The step-by-step demo is in `docs/demo-script.md`; this file is the story around it, the hard questions, and the money.

Honesty rule for everything below: say only what is built. Every number marked **(assumption)** is a planning estimate, not a result, and must be said that way on stage.

## The 3-minute pitch

**1. The problem (30 s)**
- Ajo, esusu and adashe run on trust and a notebook. Millions of Nigerians save this way; EFInA's surveys count tens of millions of adults using informal financial services.
- What goes wrong is always the same: someone collects early and stops paying, the order of turns looks rigged, nobody can prove who paid, and years of reliable saving leave no record a lender will read.

**2. What Sova is (20 s)**
- "Sova makes ajo impossible to cheat quietly, and turns your saving history into a record you own."
- Sova never holds, moves or lends money. Members still pay each other by transfer or cash. Sova keeps the record.

**3. Live demo (90 s)** — follow `docs/demo-script.md`, shortest path:
1. Try the demo → Office Esusu → pay Halima with a receipt photo and the PIN.
2. Unilag ajo → confirm Emeka's payment as collector.
3. Yaba Traders → the dispute: Musa collected then stopped paying; vote, then "Ask Sova" explains it.
4. "How it was drawn" → the fair draw replays and both checks pass on the phone.
5. Website `/verify` → the browser recomputes every hash of the ledger and checks the public anchors.

**4. Why it's different (20 s)**
- Fair draw by commit-reveal: the order is sealed before anyone joins and anyone can recheck it.
- Tamper-evident ledger (hash chain written by the database, append-only, anchored publicly every 6 hours on GitHub).
- Disputes decided by the circle's vote, not by the admin.
- Sova Score: your record, shareable by link, only after 3 confirmed payments.

**5. Where it goes (20 s)**
- Now: self-run circles (friends, colleagues, students, churches).
- Roadmap: SMS and WhatsApp reminders, collector/market mode, USSD, local languages, and (with consent and a licensed partner) the Sova Score as evidence for lenders.
- Close: "Live today on the web and Android. Try it in one tap."

## Before you go on stage

- [ ] Morning of: `npm run seed` in `api/`, then run the Ledger anchors workflow by hand.
- [ ] Open `/health`, the website and the app one minute before (all three on Tiny until 7 Nov).
- [ ] Phone charged, APK v1.0.3 installed, signed in to a fresh "Try the demo".
- [ ] Backup: a screen recording of the full demo on the laptop (plan says "backup video", not made yet).
- [ ] Offline fallback: an app build without `SOVA_API_URL` runs the in-memory demo with the same story.
- [ ] Demo PIN `2580`. Invite code for the forming circle: `T7KP9Q`.
- [ ] After 7 Nov: move the three deployments back to Free (see the 23 Oct decision in `STATUS.md`).

## Hard questions and honest answers

| Question | Answer |
|---|---|
| Do you hold people's money? | No. Members pay each other directly. Sova records it. That keeps us out of deposit-taking rules and means a Sova failure can't lose anyone's savings. |
| So what stops someone running off after collecting? | Nothing physical, and we don't pretend otherwise. What changes is that it can't be hidden: the record shows who collected and stopped, the circle sees it, vouches are visible, and their Sova Score shows it. Social pressure plus a permanent record. |
| Can the admin rig the order? | No. The seed is committed (SHA-256) when the circle is created, before anyone joins; the order is computed from it; the app and the website both recheck it. The admin can only pledge to go last. |
| Can Sova edit the ledger? | The database refuses updates and deletes on ledger rows for every role, and chain heads are published every 6 hours outside our database. We say "tamper-evident", not "tamper-proof": a change would be detectable, not impossible. |
| Is the Sova Score a credit score? | No. It's the person's own record of paying on time, shown only after 3 confirmed payments, shared only when they choose. Using it for lending would need a licensed credit bureau partner. |
| Why not just a WhatsApp group? | A WhatsApp group can't prove the draw was fair, can't stop an admin editing the list, and can't settle "I sent it" vs "it never came". |
| How do people sign in today? | Google or an email code, plus the demo. Phone codes need a paid SMS provider, which is the first spend after judging. |
| What does the AI do? | "Ask Sova" explains a circle or a dispute in plain English from the circle's data. It never sees phones, bank details or PINs, never gives financial advice, and the circle screen stays the record. |
| How will you make money? | See below: paid plans for circle admins and collectors first; partnerships later, only with consent. |
| What's your traction? | Say the truth: built in October, live, Android release v1.0.3, demo-tested on a real phone. No public users yet: opening after judging. |

## What it costs to get real users (SMS first)

Prices checked October 2026 from public sources; confirm with the provider before paying.

| Item | Cost | Notes |
|---|---|---|
| Sign-in SMS (OTP) through a local gateway (Termii, BulkSMS Nigeria, Africa's Talking, Sendchamp) | about ₦5–8 per SMS on a transactional/DND route | Twilio is about $0.39 per SMS to Nigeria (checked 7 Oct): far too dear. Ask for the DND/transactional route or codes won't reach DND numbers. |
| Sender ID registration with the gateway | ask the provider | Needed for a branded "Sova" sender; approval can take days, so start right after judging. |
| WhatsApp authentication messages | roughly $0.007–0.012 per message (sources disagree) | An alternative for codes and reminders; Meta's rates change, check the current Nigeria rate. |
| Hosting (API, app, website on Tiny, always on) | about ₦8,100 a month for all three (billing, 23 Oct) | Plus the database and bucket already in use. |
| Google Play developer account | $25 once | Already in the agreed budget. |
| Push notifications (Firebase Cloud Messaging) | free | Build these before paying for SMS reminders. |
| Email codes (Brevo free tier) and Google sign-in | free | Already built; turn email on with the Brevo key. |

**SMS maths (assumption):** each new person needs about 2 code messages in their first year. Reminders cost more: a monthly circle needs about 2–3 messages per member per month. Keep the `₦` sign out of SMS (it forces Unicode and halves the length per message); write "N20,000".

**A lean 3-month pilot for about 1,000 people (assumption):**

| Line | Estimate |
|---|---|
| SMS: codes plus paid reminders for a few pilot circles | ₦50,000–100,000 |
| Hosting, always on | ₦25,000–45,000 |
| Google Play | about ₦40,000 |
| Printing, data/airtime thank-yous for pilot admins | ₦150,000–300,000 |
| Privacy/terms legal review before opening up | ₦100,000–300,000 |
| **Total** | **about ₦400,000–800,000** |

The cheapest path: launch with Google/email sign-in plus in-app and push reminders (free), and use SMS only for people without email and for paid reminder plans.

## How Sova makes money (without touching members' money)

In order of when they can start:

1. **Sova Plus for circle admins** (first, after push and SMS reminders exist): SMS/WhatsApp reminders to every member, receipts by SMS, larger circles, CSV/PDF export of the record. Planning price ₦1,000–2,000 per circle per month **(assumption)**. Traditional alajo collectors already keep about one contribution per cycle, so people are used to paying for a trustworthy organiser.
2. **Collector and cooperative mode** (roadmap): the professional alajo collector or a staff cooperative manages many members. Planning price ₦3,000–5,000 per collector per month **(assumption)**.
3. **Workplace ajo** (B2B): companies and unions sponsor circles for staff as a benefit; priced per employee.
4. **Consented record checks** (later, with a licensed credit bureau partner and NDPA compliance): a member shares their Sova record with a lender, landlord or BNPL provider, who pays per check. Never sold without the member's choice.
5. **Partner referrals** (later): banks or savings apps pay when a member chooses to open an account with them. Labelled as a referral.

**Owner decision needed:** collecting subscription fees means Sova takes payments for its own service. `CLAUDE.md` currently says "never add payment processing". That rule protects members' money; charging for Sova's own service (for example through Google Play billing or Paystack) is a different thing, but it is the owner's call and should be written into the rules before building it.

## If it grows (all assumptions, for planning only)

Assumptions: 10 people per circle; 8% of circles pay ₦1,500/month for Sova Plus; 2 collectors per 1,000 users paying ₦3,000/month; record checks and referrals bring ₦50 per user per year; Sova pays SMS only for paying circles (about ₦210 per circle per month) and about ₦12 per user per year for sign-in codes. Naira figures; at an assumed ₦1,500 to $1.

| Users | Paying circles | Revenue a year | Running costs (SMS + hosting) | Team (assumption) | Result a year |
|---|---|---|---|---|---|
| 10,000 | 80 | ₦2.7M (~$1.8k) | ₦0.7M | founders only | **+₦1.9M** |
| 100,000 | 800 | ₦26.6M (~$18k) | ₦6.2M | 5 people, ₦40M | **−₦19.6M** (needs a grant or pre-seed) |
| 1,000,000 | 8,000 | ₦266M (~$177k) | ₦57M | 20 people, ₦250M | **−₦41M** (near break-even) |
| 5,000,000 | 40,000 | ₦1.33B (~$887k) | ₦261M | 50 people, ₦750M | **+₦319M** (~$213k) |

**Upside case (assumption):** if consented record checks and partner deals reach ₦300 per user per year at scale, 5 million users adds about ₦1.25B a year, taking revenue to about ₦2.6B (~$1.7M).

**What the table says:** subscriptions alone make Sova a small, healthy business. The big outcome depends on the record becoming useful to lenders, which needs a licensed partner, consent, and years of on-time history. That's the honest story for investors: a free tool that earns trust first, a paid tool for organisers second, and a data-for-credit layer last.

**One illustrative line for the pitch (assumption, say it as such):** 1 million members saving an average ₦20,000 a month would put about ₦240 billion a year of saving on a verifiable record, without Sova ever holding a naira of it.

## Sources (checked 30 October 2026)

- Nigeria SMS prices: [BulkSMS Nigeria pricing guide](https://www.bulksmsnigeria.com/resources/sms-pricing-calculator), [Sendar 2026 guide](https://sendar.io/blog/how-to-send-bulk-sms-nigeria/), [sent.dm Nigeria pricing](https://www.sent.dm/resources/sms-pricing/nigeria-sms-pricing), [MarTech Africa 2026 comparison](https://martechafrica.com/blog/best-sms-api-providers-in-nigeria-for-2026-pricing-features-and-support-compared/)
- WhatsApp: [Meta pricing page](https://developers.facebook.com/docs/whatsapp/pricing), [Zernio 2026 table](https://zernio.com/blog/whatsapp-business-api-pricing)
- USSD (roadmap): [NCC determination](https://ncc.gov.ng/media/1456/view), [Nairametrics, June 2025](https://nairametrics.com/2025/06/03/nigerian-banks-begin-deduction-of-ussd-transaction-charges-from-customer-airtime/): ₦6.98 per banking session, charged to airtime.
- Informal savings: [EFInA A2F 2020 report](https://efina.org.ng/wp-content/uploads/2021/10/A2F-2020-Final-Report.pdf), [EFInA blog, October 2026](https://efina.org.ng/2026/10/06/beyond-the-account-number-why-reliability-is-the-real-frontier-for-nigerias-financial-health/)
