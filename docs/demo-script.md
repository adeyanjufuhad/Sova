# Demo script

A walk through Sova on the live services, for judging day and anyone trying it for the first time. It takes about 8 minutes. For the 3-minute product walkthrough on demo day (7 Nov), use [Demo day: the 3-minute walkthrough](#demo-day-the-3-minute-walkthrough) instead. Use the web app (https://sova-app.rumptycloud.app) or the Android app (https://github.com/adeyanjufuhad/Sova/releases/latest: download the APK and install it; Android may ask you to allow installs from your browser). Everything shown here is built; the roadmap is named as roadmap at the end.

## Before the demo

1. **Reset the shared demo data.** Each "Try the demo" tap gets its own private copy of the demo, created fresh and deleted after 24 hours, so visitors never see each other's payments, votes or joins, and the app itself needs no reset. The shared seeded circles are still what the website's verify page lists, and their dates are relative to the day they were seeded, so reseed them on the day. From a computer with the admin connection string in `api/.env` (`MIGRATION_DATABASE_URL`):

   ```bash
   cd api
   npm run seed
   ```

   It recreates only the reserved demo people (`+2348000000xxx`) and their circles; real accounts are untouched. Dates are relative to today, so seed on the day.

   Then run the **Ledger anchors** workflow by hand (GitHub → Actions → Ledger anchors → Run workflow) so the new demo circles get a public anchor before anyone opens the verify page.

2. **Wake the services.** Free RumptyCloud deployments sleep when idle and take about 8 seconds to wake. A minute before, open:
   - https://sova-api.rumptycloud.app/health (should say `"database":"ok"`)
   - https://sova.rumptycloud.app
   - https://sova-app.rumptycloud.app

3. **Judges can also sign up as themselves** with **Continue with Google** or an email code on the sign-in screen (Get started → Sign in), then start a circle and share its code. Phone codes work only for test numbers until an SMS provider is connected.

4. **The demo PIN is `2580`.** The app shows it on every PIN sheet when you're on the demo account. The demo account's name, bank details and PIN can't be changed, so one visitor can't lock out the next.

## The story

Ada belongs to five circles in different states:

| Circle | State | What to show |
|---|---|---|
| Office Esusu | Weekly, ₦20,000, turn 3 of 6 | Ada still owes Halima; Zainab asks Ada to swap turns |
| Unilag Class of '24 Ajo | Monthly, ₦10,000, turn 2 of 5 | Ada is admin and collecting; Emeka's payment waits for her confirmation |
| Ikeja Tech Hub Esusu | Forming, 4 of 8 joined | Join with code `T7KP9Q`; the draw is sealed but not run |
| Church Adashe | Completed | Finished history that feeds Ada's record |
| Yaba Traders Circle | Weekly, ₦10,000, turn 3 of 4 | Musa collected first then stopped paying; a short payout opened a dispute, and the circle is voting on his late payment |

## Demo day: the 3-minute walkthrough

Finalists get a 3-minute pitch, then a 3-minute product walkthrough, then Q&A (Google Meet, 4:30 PM WAT). The pitch is in `docs/pitch.md`; this is the walkthrough. It follows one thread: **pay → confirm → someone cheats → the circle decides → nobody could rig the order → anyone can check the record.** Everything else (website landing page, tours, reminders, swaps, handovers, joining, settings) is left out on purpose.

### Set up (before 4:30)

- [ ] Morning: `npm run seed` in `api/`, then run the **Ledger anchors** workflow by hand (see "Before the demo").
- [ ] Morning: ask Ask Sova one question on a throwaway demo to check it answers. If the day's cap worries you, raise `AI_DAILY_TOTAL` on `sova-api` for the day.
- [ ] 4:00: open `/health`, the website and the app so the first load (about 20 s) is over before you share.
- [ ] 4:10: in a **new** tab (never duplicate a tab: the copied session signs both out), tap **Try the demo**, then **Skip tour**. Open **Office Esusu**, skip its circle tour, and go back to Home. Touch nothing else, so Halima, Emeka and the vote are still waiting.
- [ ] 4:10: in a second tab open https://sova.rumptycloud.app/verify/, pick the shared **Office Esusu** and wait for "Public anchors: every checkpoint matches". Use this tab for the verify beat: a private demo copy is never anchored publicly, so the app's own **Verify this circle** link shows "Public anchors: not published yet" for it.
- [ ] Close other tabs, mute notifications, zoom the browser so text reads on a shared screen.
- [ ] Backup: the screen recording on the laptop and the APK (v1.0.5) on your phone, signed in to its own fresh demo.
- [ ] Demo PIN `2580`.

### The 3 minutes

| Time | Where | Do | Say (roughly) |
|---|---|---|---|
| 0:00–0:15 | Home | Point at the next payout and what Ada owes. | "This is Ada. She's in five savings circles. Home shows what she's owed and what she owes." |
| 0:15–0:45 | Office Esusu → **Pay Halima ₦20,000** | Show Halima's bank details, type a reference, enter the PIN. Skip the receipt photo (mention it). | "Ada pays Halima by her own bank transfer. Sova never touches the money: it records it. She can attach a receipt, and Halima now has to confirm." |
| 0:45–1:10 | Unilag Class of '24 Ajo | Tap **Confirm** on Emeka's payment, PIN. | "Here Ada is the collector. Five members at ₦10,000, so she receives ₦40,000 from the other four. She confirms Emeka's payment and he gets a receipt." |
| 1:10–1:40 | Yaba Traders Circle → the dispute | On the member list, point at Musa's "Collected, then missed a payment"; open the dispute and cast Ada's vote with the PIN. | "This is what kills ajo. Musa collected first, then stopped paying. He says he sent it, Peter says it never came. The admin doesn't decide: the members who aren't involved vote, and it goes on the record." |
| 1:40–1:55 | Same dispute → chat icon (Ask Sova) | Ask for an explanation. **If no answer in 5 seconds, go back and move on.** | "For members who aren't technical, Ask Sova explains the dispute in plain English, from the circle's record, running on GPUs here in Lagos." |
| 1:55–2:30 | Office Esusu → **How it was drawn** | Let the replay run until both checks pass. | "Who collects first is where people suspect rigging. Sova sealed a fingerprint of a secret seed before anyone joined. When the circle filled, the seed was revealed and the order computed from it. Your phone rechecks both. Nobody, not even the admin, picked their turn." |
| 2:30–2:50 | Switch to the verify tab (shared Office Esusu) | Point at the chain check, the draw check and the anchors card. | "Every payment, vote and confirmation is chained by SHA-256. This page recomputes the whole chain in the browser and checks it against copies we publish on GitHub every six hours. Tamper-evident, not tamper-proof, and it says so." |
| 2:50–3:00 | Back in the app → **Record** tab | Show the Sova Score card. | "And all of that becomes Ada's record, which she can share. Live today on the web and Android." |

### If you're running late

Cut in this order: Ask Sova (saves 15 s), then the Sova Score close (end on the verify page instead), then shorten the confirm beat to one sentence. Never cut the dispute or the fair draw: they are what makes Sova different.

### If something breaks mid-walkthrough

Say what happened in one line ("the free model is busy, let me move on") and go to the next beat. If the web app won't respond, switch the share to the phone or the recording. The full list is under "If something goes wrong" at the end of this file.

## Walkthrough

**1. The problem and the promise (website, 45 s).** Open https://sova.rumptycloud.app. Ajo runs on trust and a notebook: people collect and stop paying, the order looks rigged, nobody can prove what was paid. Point at the "Not a bank / lender / wallet" disclosure: members pay each other directly; Sova keeps the record. Click **Try the live demo**.

**2. The guided tour (30 s).** Tap **Try the demo**. Every visit is a new private demo, so a short tour opens: welcome (with the demo PIN), the next payout, Pay / Start / Join, reminders, Ask Sova, then the Circles, Activity and Record tabs. Show two or three steps, then **Skip tour**; it doesn't come back, and Record → Help → **Take the tour again** replays it. The first running circle Ada opens gets its own short tour too (skip it in step 4, or show it once).

**3. Home and reminders (45 s).** Home shows Ada's next payout and payments. The bell has a dot: open it. "Needs you now" lists *Pay Halima ₦20,000* (due soon) and Emeka's payment to confirm; "Recent" shows Zainab's swap request, a vote needed and older turn notices. These are worked out from the record on every visit, so nothing has to be scheduled.

**4. Paying (1 min).** Open **Office Esusu** and tap **Pay Halima ₦20,000**. Halima's bank details are shown to copy; add a bank reference and, optionally, a receipt photo; enter the PIN. The payment shows as sent, waiting for Halima to confirm. The receipt photo sits in a private bucket and opens through a 5-minute link.

**5. Confirming as the collector (1 min).** Open **Unilag Class of '24 Ajo**. It's Ada's turn to collect: 5 members × ₦10,000, so she receives ₦40,000 from the other four (Sova never counts her own share as a payment). Emeka marked his payment as sent: tap **Confirm** and enter the PIN; Emeka gets a receipt. Mention, without doing it, that confirming a short payout still moves the circle on and opens a dispute against whoever didn't pay.

**6. Disputes (1 min).** Open **Yaba Traders Circle** and its dispute. Musa collected turn 1 and then stopped paying; Peter's turn-2 payout came up short. Musa later marked the payment as sent and Peter says it never arrived, so the members who aren't involved vote. Sani has voted; cast Ada's vote with the PIN. More than half decides it, and the outcome goes into the record. The member list also flags Musa: "Collected, then missed a payment".

**7. Ask Sova (45 s).** Still in the dispute, tap the chat icon at the top right. Ask Sova explains what the dispute is about, how it gets decided and what Ada can do, in plain English. Back on **Office Esusu**, tap the same icon for a summary of the circle and Ada's next step. Point at the caption: it's written by AI from the circle's record, so the circle screen stays the record. The API builds the prompt from the database (first names and initials only; never phones, bank details or PINs), and the model runs on RumptyCloud's own GPUs in Lagos. Answers take a few seconds.

**8. The fair draw (1 min).** Back in **Office Esusu**, tap **How it was drawn**. Before anyone joined, Sova published a fingerprint (SHA-256) of a secret seed. When the circle filled, the seed was revealed and the order computed from it. The screen replays the draw and rechecks, on the phone, that the seed matches the fingerprint and that the order comes out the same. No one, including the admin, could pick their turn.

**9. Verify the record (1 min).** On the circle screen, tap **Verify this circle**. The website downloads the circle's ledger and recomputes every SHA-256 link and the draw in the browser. Each change (joins, rules, payments, confirmations, votes, swaps) is an entry chained to the one before; the database refuses edits and deletes, and any change made around it breaks the chain. That is tamper-evident, not tamper-proof, and the page says so.

**10. Swaps and joining (40 s).** In **Office Esusu**, open **Swaps and handovers**: Zainab asks to swap because her shop rent is due before her turn. Accept or decline with the PIN; both turns must not have started. Then, on Home, tap the code button next to **Start** (join a circle) and enter `T7KP9Q`: the preview shows the amount, rules and members of **Ikeja Tech Hub Esusu** before Ada commits, and the draw stays sealed until all 8 have joined.

**11. Sova Score (40 s).** Open the **Record** tab. The score card shows Ada's on-time rate, turns paid and circles finished (weights 60/25/15), from confirmed payments only. **Share** publishes a snapshot behind a random link (first name and initial, score and rates, nothing else); open it to see the public page on the website. It's Ada's record, not a credit rating.

**12. Close (20 s).** Built and live: circles, the fair draw, payments with receipts, confirmations, disputes with votes, swaps and handovers, the tamper-evident ledger with public verification, the Sova Score, in-app reminders and settings, the guided tour, Ask Sova (English), and the Android app. Roadmap: SMS and WhatsApp reminders, push notifications, voice and local languages, offline use, USSD and collector (market) mode.

## If something goes wrong

| What you see | Do this |
|---|---|
| A long first load, or "Sova is starting up" | Wait about 8 seconds and try again; the free service is waking. |
| Someone already paid, voted or joined | Earlier visitors changed the shared demo. Run `npm run seed` again. |
| "Too many attempts" on the PIN | Five wrong PINs lock the account for 15 minutes. Run `npm run seed` to reset it. |
| Ask Sova says it has answered all it can today | The service-wide limit (`AI_DAILY_TOTAL`, 60 a day) is used up. Raise it in the `sova-api` deployment's environment variables for the day; the free inference allowance is 1M tokens a cycle with overage off. |
| Ask Sova couldn't answer | The model service is busy or waking; try again in a minute. |
| A page won't load at all | Check https://sova-api.rumptycloud.app/health; if it isn't `ok`, open the deployment in RumptyCloud and look at its logs. |
