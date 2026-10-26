import type { Metadata } from "next";
import Link from "next/link";
import { LegalPage } from "@/components/legal/legal-page";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of use · Sova",
  description:
    "The rules for using Sova, a record-keeping service for savings circles. Sova is not a bank, lender or wallet and never holds members' money.",
};

const UPDATED = "26 October 2026";

const email = (
  <a href={`mailto:${site.contactEmail}`} className="whitespace-nowrap">
    {site.contactEmail}
  </a>
);

export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="Terms"
      title="Terms of use"
      updated={UPDATED}
      intro={
        <p>
          These terms are the agreement between you and Sova when you use the Sova app or website. Please read them
          with the <Link href="/privacy/" className="text-electric underline">privacy policy</Link>, which explains what
          we store and who can see it.
        </p>
      }
      summary={[
        "Sova keeps the record of your savings circle. It is not a bank, lender or wallet, and it never holds, moves, lends or invests money.",
        "Members pay each other directly. Sova can't make anyone pay and can't recover money that wasn't paid.",
        "Keep your PIN secret. Sova will never call or text to ask for it.",
        "Record only what really happened. The record can't be edited later, by you or by us.",
        "Sova is free to use today and is still early: features marked “coming soon” or “roadmap” are not promises.",
      ]}
      sections={[
        {
          id: "about",
          title: "About these terms",
          body: (
            <>
              <p>
                By creating an account, signing in or using the demo, you agree to these terms. “Sova”, “we” and “us”
                mean the people who run Sova, a service built in Nigeria. “You” means the person using it.
              </p>
              <p>
                Sova is open as a demo for now. Sign-in works through “Try the demo”, Google, an email code and a
                short list of test phone numbers; we will review these terms before opening to everyone.
              </p>
            </>
          ),
        },
        {
          id: "what-sova-is",
          title: "What Sova is, and is not",
          body: (
            <>
              <p>
                Sova helps ajo, esusu and adashe circles keep a shared record: who is in the circle, the rules everyone
                accepted, the payout order, who has paid, what each collector received, and any disputes.
              </p>
              <ul>
                <li>
                  Sova is <strong>not</strong> a bank, lender, wallet, payment service or investment product. It never
                  holds, moves, lends or invests money and does not process payments.
                </li>
                <li>Members pay each other directly, by bank transfer or cash, outside Sova.</li>
                <li>
                  Sova does not guarantee that any member will pay, and it does not chase, collect or refund money.
                </li>
                <li>Sova does not check that bank details belong to the person who entered them.</li>
              </ul>
            </>
          ),
        },
        {
          id: "who-can-use",
          title: "Who can use Sova",
          body: (
            <ul>
              <li>You must be 18 or older.</li>
              <li>You need a Nigerian mobile number, an email address or a Google account that you control. One account per person.</li>
              <li>The name and bank details you give must be your own and correct.</li>
            </ul>
          ),
        },
        {
          id: "account-and-pin",
          title: "Your account and PIN",
          body: (
            <ul>
              <li>
                Your PIN confirms money actions, such as marking a payment as sent or confirming a payout. Keep it
                secret. Anything done with your PIN counts as done by you.
              </li>
              <li>Sova will never call or text to ask for your PIN or sign-in code.</li>
              <li>Five wrong PINs lock your account for 15 minutes.</li>
              <li>If you think someone else knows your PIN, change it in the app and tell us at {email}.</li>
            </ul>
          ),
        },
        {
          id: "circles",
          title: "Circles, rules and payments",
          body: (
            <ul>
              <li>
                A circle&apos;s rules are agreed between its members. Sova records who accepted which version; it does
                not enforce the rules outside the app.
              </li>
              <li>
                Each turn&apos;s collector receives the contribution from every other member: contribution ×
                (members − 1).
              </li>
              <li>
                The payout order is set by Sova&apos;s fair draw once the circle is full. The admin may pledge to
                collect last, and the draw respects that pledge. Anyone can check the draw on the{" "}
                <Link href="/verify/">verify page</Link>.
              </li>
              <li>
                Only mark a payment as sent when you have sent it, and only confirm a payment or payout when it has
                reached you.
              </li>
              <li>
                If a payout is short, the circle still moves to the next turn and a dispute opens automatically against
                the members who did not pay.
              </li>
              <li>Swaps and handovers follow the rules shown in the app and need the other people involved to agree.</li>
            </ul>
          ),
        },
        {
          id: "disputes",
          title: "Disputes",
          body: (
            <>
              <p>
                When a payment is disputed, other members of the circle can vote on whether it arrived, and the outcome
                updates the record. A dispute outcome is the circle&apos;s view, recorded by Sova. It is not a court
                decision, and it does not move any money.
              </p>
              <p>
                Sova does not take sides in disagreements between members. You remain free to settle a disagreement
                any other way, including through mediation, the police or the courts.
              </p>
            </>
          ),
        },
        {
          id: "the-record",
          title: "The record",
          body: (
            <>
              <p>
                Every circle has an append-only ledger. Once an entry is written, nobody can edit or delete it, including
                us, and anyone with the circle&apos;s link can check it. Chain heads are also published to a public
                GitHub branch every 6 hours.
              </p>
              <p>
                The ledger is tamper-evident, not tamper-proof: a change to a past entry shows up when it is checked,
                but the ledger can&apos;t stop someone with full control of the database from trying.
              </p>
            </>
          ),
        },
        {
          id: "score",
          title: "Sova Score",
          body: (
            <ul>
              <li>
                Your Sova Score describes your record of paying your circles. It is your record, not a credit rating,
                and Sova does not give it to lenders.
              </li>
              <li>
                If you share it, anyone with the link can see the snapshot until you stop sharing. Decisions others
                make based on your score are theirs, not Sova&apos;s.
              </li>
            </ul>
          ),
        },
        {
          id: "acceptable-use",
          title: "Acceptable use",
          body: (
            <>
              <p>Don&apos;t use Sova to:</p>
              <ul>
                <li>record payments that did not happen, or confirm money you did not receive;</li>
                <li>pretend to be someone else, or use a phone number, email or Google account that isn&apos;t yours;</li>
                <li>deceive, threaten or harass other members;</li>
                <li>
                  break, overload or get around Sova&apos;s security, or collect other people&apos;s data from it.
                </li>
              </ul>
            </>
          ),
        },
        {
          id: "demo",
          title: "The demo account",
          body: (
            <p>
              “Try the demo” gives each visit its own private copy of a fictional account and circles, deleted
              after 24 hours. The demo account&apos;s name, bank details and PIN can&apos;t be changed. Don&apos;t
              enter real personal or bank information in it.
            </p>
          ),
        },
        {
          id: "availability",
          title: "Availability and changes",
          body: (
            <>
              <p>
                Sova is free to use today. It is new, and parts of it may be slow to wake up, unavailable at times, or
                change. Features marked “coming soon” or “roadmap” are plans, not promises.
              </p>
              <p>
                We may change or stop parts of Sova. Where a change affects your circles, we will tell you in the app
                where we can.
              </p>
            </>
          ),
        },
        {
          id: "ending",
          title: "Ending your use",
          body: (
            <p>
              You can stop using Sova at any time and delete your account in the app once none of your circles is
              running (see the{" "}
              <Link href="/privacy/#your-rights">privacy policy</Link>). We may suspend or close an account that
              breaks these terms. Either way, entries already in a circle&apos;s ledger stay, because other members rely
              on them.
            </p>
          ),
        },
        {
          id: "responsibility",
          title: "Our responsibility",
          body: (
            <>
              <p>
                We work to keep Sova accurate and available, but it is provided as it is. Because Sova never handles
                money, we are not responsible for payments between members, for money a member does not pay, or for
                losses from relying on what members record.
              </p>
              <p>Nothing in these terms limits any right you have that Nigerian law says can&apos;t be limited.</p>
            </>
          ),
        },
        {
          id: "law",
          title: "Law",
          body: <p>These terms are governed by the laws of the Federal Republic of Nigeria.</p>,
        },
        {
          id: "changes",
          title: "Changes and contact",
          body: (
            <p>
              We will post any change to these terms on this page with a new date, and tell you in the app before a
              significant change takes effect. Questions: {email}.
            </p>
          ),
        },
      ]}
      other={{ href: "/privacy/", label: "Privacy policy" }}
    />
  );
}
