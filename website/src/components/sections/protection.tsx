"use client";

import { Gavel, Lock, ReceiptText, UserRoundX } from "lucide-react";
import { Timeline, type TimelineEntry } from "@/components/ui/timeline";
import { Reveal } from "@/components/ui/reveal";

const steps = [
  {
    when: "When you pay",
    icon: ReceiptText,
    title: "You mark it as sent",
    body: "After transferring from your own bank, you record the payment and its bank reference in Sova.",
    message: "Ngozi marked ₦10,000 as sent to Mama Chidinma. Ref FT2610ABC.",
  },
  {
    when: "When it arrives",
    icon: Lock,
    title: "The collector confirms with their PIN",
    body: "Only the person collecting this turn can confirm, and only after checking their account. Both of you get the receipt.",
    message: "Confirmed by Mama Chidinma. Receipt SV-4821.",
  },
  {
    when: "Payout day",
    icon: Gavel,
    title: "A short payout opens a dispute",
    body: "The collector confirms what actually reached them. If it's short, Sova opens a dispute on its own and the next turn still starts on time.",
    message: "Turn 5 payout was ₦20,000 short: expected ₦110,000, received ₦90,000.",
  },
  {
    when: "Collected, then stopped?",
    icon: UserRoundX,
    title: "The group can see it",
    body: "Anyone who collects their payout and then misses a later payment is flagged on the group record for every member to see.",
    message: "Musa collected turn 1, then missed turn 2.",
  },
];

const data: TimelineEntry[] = steps.map((s) => ({
  title: s.when,
  content: (
    <div className="rounded-3xl border border-navy-900/10 bg-white p-6">
      <div className="flex items-center gap-3">
        <span className="grid size-11 place-items-center rounded-2xl bg-electric text-white">
          <s.icon className="size-5" />
        </span>
        <h4 className="font-display text-xl font-semibold text-navy-900">{s.title}</h4>
      </div>
      <p className="mt-3 text-slate-600">{s.body}</p>
      <div className="mt-5 rounded-2xl rounded-bl-md bg-mist px-4 py-3 text-sm text-navy-800">{s.message}</div>
    </div>
  ),
}));

export function Protection() {
  return (
    <section className="px-4 py-24 sm:py-32">
      <Timeline
        data={data}
        heading={
          <Reveal className="max-w-2xl">
            <p className="inline-flex items-center gap-2 font-mono text-xs uppercase tracking-[0.2em] text-electric"><span className="size-1.5 bg-electric" /> How Sova protects your ajo</p>
            <h2 className="mt-4 font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-balance text-navy-900 sm:text-6xl">
              Missed payments can&apos;t hide.
            </h2>
            <p className="mt-4 text-lg text-slate-600">
              Most circles don&apos;t collapse from one bad person. They collapse from small gaps nobody tracked.
              In Sova, every naira has two witnesses and every shortfall leaves a mark. Reminders before the due day
              are coming soon.
            </p>
          </Reveal>
        }
      />
    </section>
  );
}
