import { BadgeCheck, CalendarClock, Users } from "lucide-react";
import { Reveal } from "@/components/ui/reveal";
import { SectionHeading } from "@/components/ui/section-heading";

const steps = [
  {
    icon: Users,
    title: "Start your circle",
    body: "Set the amount, how often you pay and the group's rules, then share a 6-character invite code. When everyone has joined, Sova draws the payout order fairly.",
  },
  {
    icon: CalendarClock,
    title: "Everyone contributes",
    body: "Members pay each other the way they already do, then mark it in Sova. The collector confirms it arrived, so no one argues about who paid.",
  },
  {
    icon: BadgeCheck,
    title: "Build your record",
    body: "Every payment you make on time builds your Sova record: a history of keeping your word that belongs to you.",
  },
] as const;

// Numbered rows on hairlines instead of three equal cards: the steps read in
// order, and the numerals carry the rhythm.
export function HowItWorks() {
  return (
    <section id="how" className="relative mx-auto max-w-6xl scroll-mt-24 px-4 py-24 sm:py-32">
      <SectionHeading
        eyebrow="How it works"
        title={
          <>
            Start. Contribute. <span className="text-electric">Build trust.</span>
          </>
        }
        sub="Sova doesn't change how ajo works. It gives it the records and receipts it never had."
      />

      <Reveal>
        <ol className="mt-16 border-b border-navy-900/10">
          {steps.map((s, i) => (
            <li key={s.title} className="group grid gap-4 border-t border-navy-900/10 py-8 transition-colors hover:bg-mist/60 sm:grid-cols-12 sm:items-start sm:gap-8 sm:px-4 sm:py-10">
              <span
                aria-hidden
                className="font-display text-5xl font-extrabold leading-none tracking-[-0.04em] text-electric/25 tabular-nums transition-colors group-hover:text-electric sm:col-span-2 sm:text-7xl"
              >
                0{i + 1}
              </span>
              <h3 className="font-display text-2xl font-bold tracking-tight text-navy-900 sm:col-span-4 sm:pt-2 sm:text-3xl">
                {s.title}
              </h3>
              <p className="max-w-[52ch] text-slate-600 sm:col-span-5 sm:pt-3">{s.body}</p>
              <span className="hidden size-11 place-items-center rounded-2xl bg-electric/10 text-electric sm:col-span-1 sm:grid sm:justify-self-end">
                <s.icon className="size-5" />
              </span>
            </li>
          ))}
        </ol>
      </Reveal>
    </section>
  );
}
