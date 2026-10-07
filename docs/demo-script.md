# Demo script

A walk through Sova on the live services, for judging day and anyone trying it for the first time. It takes about 7 minutes. Everything shown here is built; the roadmap is named as roadmap at the end.

## Before the demo

1. **Reset the demo data.** Everyone who taps "Try the demo" shares one account (Ada Obi), so earlier visitors may have paid, voted or joined already. From a computer with the admin connection string in `api/.env` (`MIGRATION_DATABASE_URL`):

   ```bash
   cd api
   npm run seed
   ```

   It recreates only the reserved demo people (`+2348000000xxx`) and their circles; real accounts are untouched. Dates are relative to today, so seed on the day.

2. **Wake the services.** Free RumptyCloud deployments sleep when idle and take about 8 seconds to wake. A minute before, open:
   - https://sova-api.rumptycloud.app/health (should say `"database":"ok"`)
   - https://sova.rumptycloud.app
   - https://sova-app.rumptycloud.app

3. **The demo PIN is `2580`.** The app shows it on every PIN sheet when you're on the demo account. The demo account's name, bank details and PIN can't be changed, so one visitor can't lock out the next.

## The story

Ada belongs to five circles in different states:

| Circle | State | What to show |
|---|---|---|
| Office Esusu | Weekly, ₦20,000, turn 3 of 6 | Ada still owes Halima; Zainab asks Ada to swap turns |
| Unilag Class of '24 Ajo | Monthly, ₦10,000, turn 2 of 5 | Ada is admin and collecting; Emeka's payment waits for her confirmation |
| Ikeja Tech Hub Esusu | Forming, 4 of 8 joined | Join with code `T7KP9Q`; the draw is sealed but not run |
| Church Adashe | Completed | Finished history that feeds Ada's record |
| Yaba Traders Circle | Weekly, ₦10,000, turn 3 of 4 | Musa collected first then stopped paying; a short payout opened a dispute, and the circle is voting on his late payment |

## Walkthrough

**1. The problem and the promise (website, 45 s).** Open https://sova.rumptycloud.app. Ajo runs on trust and a notebook: people collect and stop paying, the order looks rigged, nobody can prove what was paid. Point at the "Not a bank / lender / wallet" disclosure: members pay each other directly; Sova keeps the record. Click **Try the live demo**.

**2. Home and reminders (45 s).** Tap **Try the demo**. Home shows Ada's next payout and payments. The bell has a dot: open it. "Needs you now" lists *Pay Halima ₦20,000* (due soon) and Emeka's payment to confirm; "Recent" shows Zainab's swap request, a vote needed and older turn notices. These are worked out from the record on every visit, so nothing has to be scheduled.

**3. Paying (1 min).** Open **Office Esusu** and tap **Pay Halima ₦20,000**. Halima's bank details are shown to copy; add a bank reference and, optionally, a receipt photo; enter the PIN. The payment shows as sent, waiting for Halima to confirm. The receipt photo sits in a private bucket and opens through a 5-minute link.

**4. Confirming as the collector (1 min).** Open **Unilag Class of '24 Ajo**. It's Ada's turn to collect: 5 members × ₦10,000, so she receives ₦40,000 from the other four (Sova never counts her own share as a payment). Emeka marked his payment as sent: tap **Confirm** and enter the PIN; Emeka gets a receipt. Mention, without doing it, that confirming a short payout still moves the circle on and opens a dispute against whoever didn't pay.

**5. Disputes (1 min).** Open **Yaba Traders Circle** and its dispute. Musa collected turn 1 and then stopped paying; Peter's turn-2 payout came up short. Musa later marked the payment as sent and Peter says it never arrived, so the members who aren't involved vote. Sani has voted; cast Ada's vote with the PIN. More than half decides it, and the outcome goes into the record. The member list also flags Musa: "Collected, then missed a payment".

**6. The fair draw (1 min).** Back in **Office Esusu**, tap **How it was drawn**. Before anyone joined, Sova published a fingerprint (SHA-256) of a secret seed. When the circle filled, the seed was revealed and the order computed from it. The screen replays the draw and rechecks, on the phone, that the seed matches the fingerprint and that the order comes out the same. No one, including the admin, could pick their turn.

**7. Verify the record (1 min).** On the circle screen, tap **Verify this circle**. The website downloads the circle's ledger and recomputes every SHA-256 link and the draw in the browser. Each change (joins, rules, payments, confirmations, votes, swaps) is an entry chained to the one before; the database refuses edits and deletes, and any change made around it breaks the chain. That is tamper-evident, not tamper-proof, and the page says so.

**8. Swaps and joining (40 s).** In **Office Esusu**, open **Swaps and handovers**: Zainab asks to swap because her shop rent is due before her turn. Accept or decline with the PIN; both turns must not have started. Then, on Home, tap the code button next to **Start** (join a circle) and enter `T7KP9Q`: the preview shows the amount, rules and members of **Ikeja Tech Hub Esusu** before Ada commits, and the draw stays sealed until all 8 have joined.

**9. Sova Score (40 s).** Open the **Record** tab. The score card shows Ada's on-time rate, turns paid and circles finished (weights 60/25/15), from confirmed payments only. **Share** publishes a snapshot behind a random link (first name and initial, score and rates, nothing else); open it to see the public page on the website. It's Ada's record, not a credit rating.

**10. Close (20 s).** Built and live: circles, the fair draw, payments with receipts, confirmations, disputes with votes, swaps and handovers, the tamper-evident ledger with public verification, the Sova Score, in-app reminders and settings. Roadmap: SMS and WhatsApp reminders, push notifications, voice and local languages, offline use, USSD and collector (market) mode.

## If something goes wrong

| What you see | Do this |
|---|---|
| A long first load, or "Sova is starting up" | Wait about 8 seconds and try again; the free service is waking. |
| Someone already paid, voted or joined | Earlier visitors changed the shared demo. Run `npm run seed` again. |
| "Too many attempts" on the PIN | Five wrong PINs lock the account for 15 minutes. Run `npm run seed` to reset it. |
| A page won't load at all | Check https://sova-api.rumptycloud.app/health; if it isn't `ok`, open the deployment in RumptyCloud and look at its logs. |
