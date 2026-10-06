"use client";

import { useId, useState } from "react";
import { AdirePattern } from "@/components/ui/adire";
import { Reveal } from "@/components/ui/reveal";
import { SectionHeading } from "@/components/ui/section-heading";
import { cn } from "@/lib/utils";

const naira = new Intl.NumberFormat("en-NG", { style: "currency", currency: "NGN", maximumFractionDigits: 0 });

const cycles = [
  { value: "daily", label: "Daily", unit: ["day", "days"] },
  { value: "weekly", label: "Weekly", unit: ["week", "weeks"] },
  { value: "monthly", label: "Monthly", unit: ["month", "months"] },
] as const;

const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));

/**
 * The circle maths, worked out live: the collector receives one contribution
 * from every other member, and over a full cycle each member pays in exactly
 * what they collect. Nothing here is a projection or a promise; it's arithmetic.
 */
export function PayoutCalculator() {
  const id = useId();
  const [amount, setAmount] = useState(20000);
  const [members, setMembers] = useState(10);
  const [cycle, setCycle] = useState<(typeof cycles)[number]["value"]>("weekly");

  const payout = amount * (members - 1);
  const unit = cycles.find((c) => c.value === cycle)!.unit;

  return (
    <section id="payout" className="scroll-mt-24 bg-mist px-4 py-24 sm:py-32">
      <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-12">
        <div className="lg:col-span-5">
          <SectionHeading
            className="lg:block"
            eyebrow="Your payout"
            title="See what your turn pays."
          />
          <p className="mt-6 max-w-[46ch] text-lg text-pretty text-slate-600">
            When it&apos;s your turn, every other member pays you once. Over the whole cycle you pay in exactly what you
            collect: no interest, and Sova takes nothing from it.
          </p>
        </div>

        <Reveal delay={0.1} className="lg:col-span-7">
          <div className="overflow-hidden rounded-3xl border border-navy-900/15 bg-white">
            <div className="grid gap-5 p-6 sm:grid-cols-2 sm:p-8">
              <label className="block sm:col-span-2" htmlFor={`${id}-amount`}>
                <span className="mb-1.5 block text-sm font-medium text-navy-800">Each member pays</span>
                <span className="flex items-center rounded-xl border border-navy-900/15 px-4 focus-within:border-electric focus-within:ring-2 focus-within:ring-electric/20">
                  <span aria-hidden className="font-display text-2xl font-bold text-slate-400">
                    ₦
                  </span>
                  <input
                    id={`${id}-amount`}
                    name="amount"
                    type="number"
                    inputMode="numeric"
                    autoComplete="off"
                    min={100}
                    max={10_000_000}
                    step={500}
                    value={amount}
                    onChange={(e) => setAmount(clamp(Number(e.target.value) || 0, 0, 10_000_000))}
                    className="w-full bg-transparent px-2 py-3 font-display text-2xl font-bold text-navy-900 tabular-nums outline-none"
                  />
                </span>
              </label>

              <label className="block" htmlFor={`${id}-members`}>
                <span className="mb-1.5 flex items-baseline justify-between text-sm font-medium text-navy-800">
                  Members <span className="font-display text-lg font-bold text-navy-900 tabular-nums">{members}</span>
                </span>
                <input
                  id={`${id}-members`}
                  name="members"
                  type="range"
                  min={2}
                  max={30}
                  value={members}
                  onChange={(e) => setMembers(Number(e.target.value))}
                  className="h-11 w-full cursor-pointer accent-electric"
                />
              </label>

              <fieldset>
                <legend className="mb-1.5 text-sm font-medium text-navy-800">How often</legend>
                <div className="grid grid-cols-3 gap-1 rounded-xl border border-navy-900/15 p-1">
                  {cycles.map((c) => (
                    <button
                      key={c.value}
                      type="button"
                      aria-pressed={cycle === c.value}
                      onClick={() => setCycle(c.value)}
                      className={cn(
                        "rounded-lg py-2.5 text-sm font-medium transition-colors active:scale-[0.98]",
                        cycle === c.value ? "bg-navy-900 text-white" : "text-slate-600 hover:bg-mist hover:text-navy-900",
                      )}
                    >
                      {c.label}
                    </button>
                  ))}
                </div>
              </fieldset>
            </div>

            <div aria-live="polite" className="relative overflow-hidden bg-electric p-6 text-white sm:p-8">
              <AdirePattern id="payout-adire" className="text-white/10" />
              <div className="relative grid gap-6 sm:grid-cols-[1.4fr_1fr] sm:items-end">
                <div>
                  <p className="text-sm text-white/75">On your turn you collect</p>
                  <p className="mt-1 font-display text-5xl font-extrabold tracking-[-0.03em] tabular-nums sm:text-6xl">
                    {naira.format(payout)}
                  </p>
                  <p className="mt-2 text-sm text-white/75">
                    {naira.format(amount)} from each of the other {members - 1} member{members === 2 ? "" : "s"}
                  </p>
                </div>
                <dl className="grid grid-cols-2 gap-4 border-t border-white/20 pt-4 text-sm sm:grid-cols-1 sm:border-t-0 sm:border-l sm:pt-0 sm:pl-6">
                  <div>
                    <dt className="text-white/65">The cycle lasts</dt>
                    <dd className="font-semibold tabular-nums">
                      {members} {unit[1]}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-white/65">You pay in</dt>
                    <dd className="font-semibold tabular-nums">{naira.format(payout)} in total</dd>
                  </div>
                </dl>
              </div>
              <p className="relative mt-6 text-xs text-white/65">
                Your turn comes from the fair draw once the circle is full. Money moves between members; Sova only keeps
                the record.
              </p>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
