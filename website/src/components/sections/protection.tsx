"use client";

import { Bell, MessageCircle, UserRound, UsersRound } from "lucide-react";
import { Timeline, type TimelineEntry } from "@/components/ui/timeline";
import { Reveal } from "@/components/ui/reveal";

const steps = [
  {
    when: "Day before",
    icon: Bell,
    title: "Friendly SMS reminder",
    body: "A quiet nudge to every member who pays tomorrow, so nobody forgets.",
    message: "Ngozi, your ₦10,000 for Balogun Market Ajo is due tomorrow.",
  },
  {
    when: "On the day",
    icon: MessageCircle,
    title: "Second reminder",
    body: "Sent only to members who haven't paid yet. Everyone else is left alone.",
    message: "Today is contribution day. Mama Chidinma collects on Friday.",
  },
  {
    when: "A day late",
    icon: UserRound,
    title: "Collector is told",
    body: "The organiser sees who is late and can follow up in person, the way ajo has always worked.",
    message: "Ngozi E. is 1 day late on Balogun Market Ajo.",
  },
  {
    when: "Still unpaid",
    icon: UsersRound,
    title: "Group can see it",
    body: "The missed payment shows on the group record. Social pressure comes last, not first.",
    message: "Group record updated: 11 of 12 paid this week.",
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
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-electric">How Sova protects your ajo</p>
            <h2 className="mt-4 font-display text-3xl font-semibold tracking-tight text-balance text-navy-900 sm:text-5xl">
              Missed payments get handled before they become fights.
            </h2>
            <p className="mt-4 text-lg text-slate-600">
              Most circles don&apos;t collapse from one bad person. They collapse from small delays that nobody
              tracked. Sova follows up step by step, gently at first.
            </p>
          </Reveal>
        }
      />
    </section>
  );
}
