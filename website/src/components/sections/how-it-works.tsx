import { ArrowRight, BadgeCheck, CalendarClock, Users } from "lucide-react";
import { Reveal } from "@/components/ui/reveal";
import { SectionHeading } from "@/components/ui/section-heading";
import { cn } from "@/lib/utils";

const steps = [
  {
    icon: Users,
    title: "Start your circle",
    body: "Add members by phone number, set the amount and how often you contribute: daily, weekly or monthly. Sova sets the payout order.",
    tone: "outline",
  },
  {
    icon: CalendarClock,
    title: "Everyone contributes",
    body: "Members pay each other the way they already do. Sova sends reminders before the day and an SMS receipt after, so no one argues about who paid.",
    tone: "dark",
  },
  {
    icon: BadgeCheck,
    title: "Build your record",
    body: "Each cycle you complete on time adds to your Sova record, which you own and can share, to earn an earlier turn next time.",
    tone: "blue",
  },
] as const;

export function HowItWorks() {
  return (
    <section id="how" className="relative mx-auto max-w-6xl scroll-mt-24 px-4 py-24 sm:py-32">
      <SectionHeading
        eyebrow="How it works"
        title={
          <>
            Start. Contribute. <span className="text-gradient">Build trust.</span>
          </>
        }
        sub="Sova doesn't change how ajo works. It gives it the records, reminders and receipts it never had."
      />

      <div className="mt-16 grid items-stretch gap-4 md:grid-cols-[1fr_auto_1fr_auto_1fr]">
        {steps.map((s, i) => (
          <div key={s.title} className="contents">
            <Reveal delay={i * 0.12} className="h-full">
              <div
                className={cn(
                  "flex h-full flex-col rounded-3xl p-7",
                  s.tone === "outline" && "border border-navy-900/10 bg-white",
                  s.tone === "dark" && "border border-electric/10 bg-mist",
                  s.tone === "blue" && "bg-gradient-to-br from-electric to-navy-700 text-white",
                )}
              >
                <div className="flex items-center justify-between">
                  <span
                    className={cn(
                      "grid size-11 place-items-center rounded-2xl",
                      s.tone === "blue" ? "bg-white/15 text-white" : "bg-electric/10 text-electric",
                    )}
                  >
                    <s.icon className="size-5" />
                  </span>
                  <span className={cn("font-mono text-xs", s.tone === "blue" ? "text-white/50" : "text-navy-900/30")}>0{i + 1}</span>
                </div>
                <h3 className={cn("mt-8 font-display text-xl font-semibold", s.tone === "blue" ? "text-white" : "text-navy-900")}>{s.title}</h3>
                <p className={cn("mt-3 text-sm leading-relaxed", s.tone === "blue" ? "text-white/80" : "text-slate-600")}>
                  {s.body}
                </p>
              </div>
            </Reveal>
            {i < steps.length - 1 && (
              <div className="hidden items-center justify-center md:flex">
                <ArrowRight className="size-6 text-electric/40" />
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
