import { Bell, MessageCircle, UserRound, UsersRound } from "lucide-react";
import { Reveal } from "@/components/ui/reveal";

const ladder = [
  { icon: Bell, when: "Day before", title: "Friendly SMS reminder", body: "A quiet nudge so no one forgets." },
  { icon: MessageCircle, when: "On the day", title: "Second reminder", body: "Sent only to members who haven't paid yet." },
  { icon: UserRound, when: "A day late", title: "Collector is told", body: "The organiser can follow up in person." },
  { icon: UsersRound, when: "Still unpaid", title: "Group can see it", body: "Social pressure, used last, not first." },
];

export function Protection() {
  return (
    <section className="relative overflow-hidden bg-white px-4 py-24 text-navy-900 sm:py-32">
      {/* Blurred blue orb seen through vertical glass slats */}
      <div className="pointer-events-none absolute -right-40 top-1/2 hidden size-[720px] -translate-y-1/2 lg:block">
        <div className="absolute inset-0 rounded-full bg-electric/80 blur-[70px]" />
        <div className="absolute inset-0 flex">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="h-full flex-1 border-l border-white/30 bg-gradient-to-r from-white/25 via-white/5 to-transparent backdrop-blur-[2px]"
            />
          ))}
        </div>
      </div>

      <div className="relative mx-auto max-w-6xl">
        <div className="max-w-xl">
          <Reveal>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-electric">How Sova protects your ajo</p>
            <h2 className="mt-4 font-display text-3xl font-semibold tracking-tight text-balance sm:text-5xl">
              Missed payments get handled before they become fights.
            </h2>
            <p className="mt-4 text-lg text-navy-700/80">
              Most circles don&apos;t collapse from one bad person. They collapse from small delays that nobody
              tracked. Sova follows up step by step, gently at first.
            </p>
          </Reveal>

          <ol className="relative mt-12 space-y-4 before:absolute before:bottom-6 before:left-[27px] before:top-6 before:w-px before:bg-navy-900/15">
            {ladder.map((s, i) => (
              <Reveal key={s.title} delay={i * 0.08}>
                <li className="relative flex gap-5 rounded-3xl border border-navy-900/10 bg-white/80 p-4 pr-6 backdrop-blur">
                  <span className="relative grid size-14 shrink-0 place-items-center rounded-2xl bg-navy-900 text-white">
                    <s.icon className="size-5" />
                  </span>
                  <div>
                    <p className="font-mono text-[11px] uppercase tracking-wider text-electric">{s.when}</p>
                    <p className="mt-0.5 font-display text-lg font-semibold">{s.title}</p>
                    <p className="text-sm text-navy-700/70">{s.body}</p>
                  </div>
                </li>
              </Reveal>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}
