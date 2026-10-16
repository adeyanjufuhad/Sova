import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import { LegalPage } from "@/components/legal/legal-page";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy policy · Sova",
  description:
    "What Sova stores, who can see it and how to ask for it to be corrected or deleted. Sova never holds your money, and the website has no ads or trackers.",
};

const UPDATED = "16 October 2026";

const email = (
  <a href={`mailto:${site.contactEmail}`} className="whitespace-nowrap">
    {site.contactEmail}
  </a>
);

// Every row is something Sova actually stores (see db/migrations and api/src/routes).
const collected: { what: string; why: ReactNode }[] = [
  {
    what: "Phone number",
    why: "To sign you in with a text code, and so members of your circles can reach you. Stored as +234XXXXXXXXXX.",
  },
  {
    what: "Name",
    why: "Shown to members of your circles. The public circle record shows only your first name and initial.",
  },
  {
    what: "Bank details",
    why: "Bank name, 10-digit account number and account name, used only to show members where to pay you when it is your turn to collect. Sova never debits, credits or checks your account. Changing them needs your PIN.",
  },
  {
    what: "PIN",
    why: "Stored only as an argon2id hash, so nobody at Sova can read it. It confirms money actions such as marking a payment or confirming a payout.",
  },
  {
    what: "Circle activity",
    why: "Circles you start or join, rules you accept, who vouched for you, payments you mark as sent or confirm, payouts, disputes, votes, comments, swaps and handovers.",
  },
  {
    what: "Receipt photos",
    why: "Only if you attach one to a payment. Kept in a private storage bucket; members of that circle view it through links that expire after 5 minutes.",
  },
  {
    what: "Sova Score",
    why: "Worked out from your circle record. If you choose to share it, a snapshot is published behind a random link (see “Who can see what”).",
  },
  {
    what: "Sign-in records",
    why: "Sign-in codes are stored only as a keyed hash and expire after 5 minutes. Sessions are stored as a hash of the token, with the description your browser or app sends (its user agent), and last up to 30 days unless you sign out.",
  },
  {
    what: "Notifications",
    why: "In-app messages about your circles. Sova does not send marketing texts or emails.",
  },
  {
    what: "Waitlist",
    why: "If you join it on the website: your name, phone number, whether you are a member, admin or collector, and, if you give them, your city and circle size.",
  },
  {
    what: "Server logs",
    why: "When your device talks to the Sova API, the request (address, time, IP address) is logged for security and fixing problems. PINs, codes and tokens are removed from logs.",
  },
];

export default function PrivacyPage() {
  return (
    <LegalPage
      eyebrow="Privacy"
      title="Privacy policy"
      updated={UPDATED}
      intro={
        <>
          <p>
            This page explains what Sova stores, why, who can see it and what you can ask us to do with it. It
            describes Sova as it works today. Sova is open as a demo for now: sign-in works for the shared demo
            account and a short list of test numbers. We will update this page before opening to everyone.
          </p>
        </>
      }
      summary={[
        <>
          <strong className="font-semibold text-navy-900">Sova never holds, moves, lends or invests your money.</strong>{" "}
          Members pay each other directly; Sova keeps the record.
        </>,
        "We store what a savings record needs: your phone number, name, bank details, a hashed PIN, and receipt photos you choose to add.",
        "Members of your circles see your name and phone number, and your bank details when it is your turn to collect. The public circle record shows only an id and your first name and initial.",
        "No ads, no analytics, no trackers. We don't sell your data.",
        "You can ask to see, correct or delete your data under the Nigeria Data Protection Act 2023.",
      ]}
      sections={[
        {
          id: "who-we-are",
          title: "Who we are",
          body: (
            <>
              <p>
                Sova is a record-keeping service for ajo, esusu and adashe savings circles, built in Nigeria.
                “Sova”, “we” and “us” mean the people who run it. For anything on this page, write to {email}.
              </p>
              <p>
                Sova is not a bank, lender or wallet. It never holds, moves, lends or invests money and does not
                process payments. Members pay each other by bank transfer or cash, and Sova records what happened.
              </p>
            </>
          ),
        },
        {
          id: "what-we-collect",
          title: "What we collect",
          body: (
            <dl className="divide-y divide-navy-900/10 rounded-2xl border border-navy-900/10 bg-white">
              {collected.map((row) => (
                <div key={row.what} className="grid gap-1 px-5 py-4 sm:grid-cols-[10rem_1fr] sm:gap-6">
                  <dt className="font-semibold text-navy-900">{row.what}</dt>
                  <dd className="text-slate-600">{row.why}</dd>
                </div>
              ))}
            </dl>
          ),
        },
        {
          id: "how-we-use-it",
          title: "How we use it",
          body: (
            <>
              <ul>
                <li>To run your circles: turns, payments, payouts, rules, disputes, swaps and reminders.</li>
                <li>To show each member what they need, such as where to pay and who has paid.</li>
                <li>
                  To keep accounts safe: limits on sign-in codes and PIN attempts, and spotting a stolen sign-in.
                </li>
                <li>To work out your Sova Score.</li>
                <li>To tell people on the waitlist when Sova opens.</li>
              </ul>
              <p>
                We don&apos;t use your data for advertising, we don&apos;t sell or rent it, and we don&apos;t give it
                to lenders.
              </p>
              <p>
                Under the Nigeria Data Protection Act 2023, we rely on: providing the service you asked for (your
                account and circles); your consent for optional things (receipt photos, sharing your score, the
                waitlist), which you can withdraw; and our legitimate interest in keeping Sova secure (logs and rate
                limits).
              </p>
            </>
          ),
        },
        {
          id: "who-can-see-what",
          title: "Who can see what",
          body: (
            <ul>
              <li>
                <strong>Members of your circles</strong> see your full name and phone number, your payments and
                their status, receipt photos you attach in that circle, and disputes and votes. When you are the
                collector for the current turn, they also see your bank details so they know where to pay.
              </li>
              <li>
                <strong>Anyone with a circle&apos;s link</strong> can download and check that circle&apos;s
                tamper-evident record on the <Link href="/verify/">verify page</Link>. People appear in it only as an
                opaque id and first name plus initial (for example “Ada O.”). Phone numbers and bank details are
                never written to it. A circle&apos;s link works like a private link, so share it with care.
              </li>
              <li>
                <strong>Anyone at all</strong> can read the public ledger anchors: every 6 hours, each circle&apos;s
                latest chain head (a sequence number and a hash) is published to a public GitHub branch, filed under
                a SHA-256 hash of the circle&apos;s id. The file contains no names or numbers and can&apos;t be used
                to find circles.
              </li>
              <li>
                <strong>Anyone with your score link</strong> sees the snapshot you shared: first name and initial,
                score, the three rates, payment and circle counts, and when you joined. There is one live link at a
                time, and you can stop sharing in the app whenever you like; the link then says it is no longer
                active.
              </li>
              <li>
                <strong>Everyone using the demo:</strong> “Try the demo” signs everyone into the same shared account.
                Don&apos;t enter real personal or bank information there.
              </li>
              <li>
                <strong>Service providers.</strong> RumptyCloud hosts the database, API, file storage, web app and
                website. GitHub stores Sova&apos;s code and the public anchors, and builds the app and website. Sign-in
                codes currently work only for a fixed list of test numbers, so no text messages are sent. Before
                opening to everyone we will use a paid SMS provider, which will receive your phone number and code;
                we will name it here first.
              </li>
              <li>We only share data beyond this if Nigerian law requires it.</li>
            </ul>
          ),
        },
        {
          id: "website-and-apps",
          title: "Website, apps and cookies",
          body: (
            <>
              <p>
                This website has no ads, analytics or tracking scripts and sets no cookies. Its fonts are served from
                the site itself. Two things talk to other servers:
              </p>
              <ul>
                <li>The waitlist form sends what you type to the Sova API.</li>
                <li>
                  The verify page downloads the public anchors file from GitHub (raw.githubusercontent.com), so GitHub
                  sees your IP address when you use it.
                </li>
              </ul>
              <p>
                The web app keeps you signed in using the browser tab&apos;s session storage, which is cleared when
                you close the tab; the Android app uses the phone&apos;s secure storage. Neither has ads or analytics.
                Like other Flutter web apps by default, the web app loads its rendering engine from Google&apos;s
                servers (gstatic.com), so Google sees your IP address and browser details when it loads.
              </p>
            </>
          ),
        },
        {
          id: "how-long",
          title: "How long we keep it",
          body: (
            <ul>
              <li>Account details: while you have an account, or until you delete it or ask us to.</li>
              <li>Sign-in codes: 5 minutes. Sessions: up to 30 days, or until you sign out.</li>
              <li>
                Circle records: the ledger is append-only by design, so members can rely on it. Its entries can&apos;t
                be edited or deleted, by us or anyone else, and they name people only by id and first name plus
                initial.
              </li>
              <li>Receipt photos: kept with the circle&apos;s record, and deleted when you delete your account.</li>
              <li>
                Shared scores: when you stop sharing, the snapshot is marked stopped and no longer shown. You can ask
                us to delete it.
              </li>
              <li>Waitlist: until we contact you about launch, or until you ask to be removed.</li>
              <li>Server logs: kept by our hosting provider and used only for security and fixing problems.</li>
              <li>Demo data is fictional and is reset from time to time.</li>
            </ul>
          ),
        },
        {
          id: "your-rights",
          title: "Your rights",
          body: (
            <>
              <p>Under the Nigeria Data Protection Act 2023 you can ask us to:</p>
              <ul>
                <li>tell you what data we hold about you and give you a copy;</li>
                <li>correct data that is wrong;</li>
                <li>delete your data, or stop or limit how we use it;</li>
                <li>give you your data in a format you can take elsewhere;</li>
                <li>stop using data you gave with consent (for example, a shared score or the waitlist).</li>
              </ul>
              <p>
                You can change your name and bank details yourself in the app, and delete your account from the
                Record tab (Delete account, with your PIN) once every circle you&apos;re in has finished. Deleting it
                removes your name, phone number, PIN, bank details, sessions, notifications, score history and
                receipt photos; payments in finished circles stay on those circles&apos; records without your name or
                number, and ledger entries stay as described above. The phone number can&apos;t be changed in the
                app. For anything else, write to {email} from or about the number on your account, and we will check
                it is yours before acting.
              </p>
              <p>
                If you are unhappy with how we handle your data, you can complain to the Nigeria Data Protection
                Commission.
              </p>
            </>
          ),
        },
        {
          id: "security",
          title: "Security",
          body: (
            <>
              <ul>
                <li>PINs are hashed with argon2id. Five wrong PINs lock the account for 15 minutes.</li>
                <li>Sign-in codes and PIN checks are rate-limited; codes are stored only as a keyed hash.</li>
                <li>
                  Sign-in tokens are stored only as hashes and change on every refresh; reusing an old one signs that
                  device out.
                </li>
                <li>Receipt photos sit in a private bucket and open only through links that expire after 5 minutes.</li>
                <li>The apps and website talk to the API over HTTPS.</li>
              </ul>
              <p>
                No system is perfectly secure. If a breach affects your data, we will tell you and the Nigeria Data
                Protection Commission as the Act requires. Sova will never call or text to ask for your PIN or sign-in
                code.
              </p>
            </>
          ),
        },
        {
          id: "children",
          title: "Children",
          body: <p>Sova is for people aged 18 and over. We don&apos;t knowingly hold data about children.</p>,
        },
        {
          id: "changes",
          title: "Changes to this policy",
          body: (
            <p>
              When Sova changes what it collects or who sees it, we will update this page and the date at the top. For
              significant changes, we will also tell you in the app before they take effect.
            </p>
          ),
        },
        {
          id: "contact",
          title: "Contact",
          body: <p>Questions or requests about your data: {email}.</p>,
        },
      ]}
      other={{ href: "/terms/", label: "Terms of use" }}
    />
  );
}
