"use client";

import { motion } from "motion/react";
import { ArrowRight, Check, CheckCheck, Clock3, Landmark, Lock, MapPin, ReceiptText, UsersRound } from "lucide-react";
import { AdirePattern } from "@/components/ui/adire";
import { LightRays } from "@/components/ui/light-rays";
import { site } from "@/lib/site";

const members = [
  { name: "Aisha B.", status: "paid" },
  { name: "Tunde O.", status: "paid" },
  { name: "Ngozi E.", status: "due" },
] as const;

function PhoneMock() {
  return (
    <div className="relative mx-auto w-[280px] sm:w-[300px]">
      <div className="relative rounded-[2.6rem] border border-navy-900/20 bg-navy-950 p-2.5">
        <div className="overflow-hidden rounded-[2.1rem] bg-navy-900">
          <div className="flex items-center justify-between px-5 pt-4 text-[11px] text-slate-400">
            <span>9:41</span>
            <span className="h-5 w-20 rounded-full bg-black/60" />
            <span>4G</span>
          </div>

          <div className="px-5 pt-5">
            <p className="text-xs text-slate-400">Balogun Market Ajo</p>
            <div className="mt-1 flex items-end justify-between">
              <p className="font-display text-3xl font-bold tabular-nums text-white">₦110,000</p>
              <span className="rounded-full bg-sky/15 px-2 py-0.5 text-[10px] font-medium text-sky">
                Turn 5 of 12
              </span>
            </div>
            <p className="mt-0.5 text-[11px] text-slate-400">This turn&apos;s payout · ₦10,000 from 11 members</p>

            <div className="mt-4 h-1.5 overflow-hidden rounded-full bg-white/10">
              <motion.div
                className="h-full rounded-full bg-sky"
                initial={{ width: "0%" }}
                animate={{ width: "75%" }}
                transition={{ duration: 1.6, delay: 0.6, ease: "easeOut" }}
              />
            </div>
            <p className="mt-1.5 flex justify-between text-[11px] text-slate-400">
              <span>8 of 11 paid</span>
              <span>Mama Chidinma collects Fri</span>
            </p>
          </div>

          <div className="mx-3 mt-4 rounded-2xl bg-white/[0.04] p-3">
            <p className="px-1 text-[11px] uppercase tracking-wider text-slate-500">This week</p>
            <ul className="mt-2 space-y-1.5">
              {members.map((m) => (
                <li key={m.name} className="flex items-center justify-between rounded-xl px-2 py-1.5">
                  <span className="flex items-center gap-2.5">
                    <span className="grid size-7 place-items-center rounded-full bg-navy-700 text-[10px] font-semibold text-sky">
                      {m.name.slice(0, 1)}
                    </span>
                    <span className="text-sm text-slate-200">{m.name}</span>
                  </span>
                  {m.status === "paid" ? (
                    <span className="flex items-center gap-1 rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-medium text-white">
                      <Check className="size-3" /> Paid
                    </span>
                  ) : (
                    <span className="flex items-center gap-1 rounded-full bg-sky/15 px-2 py-0.5 text-[10px] font-medium text-sky">
                      <Clock3 className="size-3" /> Due today
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>

          {/* room at the bottom of the screen for the floating receipt */}
          <div className="h-28" />
        </div>
      </div>

      {/* floating receipt */}
      <motion.div
        initial={{ opacity: 0, x: 30 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 1.2, duration: 0.6 }}
        className="absolute -right-4 -top-6 hidden animate-float sm:block lg:-right-24"
      >
        <div className="flex w-60 items-start gap-3 rounded-2xl border border-navy-900/10 bg-white p-3">
          <span className="grid size-8 shrink-0 place-items-center rounded-xl bg-electric/10 text-electric">
            <ReceiptText className="size-4" />
          </span>
          <div>
            <p className="text-[11px] text-slate-500">Sova receipt · 9:12am</p>
            <p className="text-sm leading-snug text-navy-900">
              Mama Chidinma confirmed Tunde&apos;s <span className="tabular-nums">₦10,000</span>. Ref SV-4821.
            </p>
          </div>
        </div>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, x: -30 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 1.5, duration: 0.6 }}
        className="absolute -bottom-10 -left-8 hidden animate-float [animation-delay:1.5s] sm:block lg:-left-20"
      >
        <div className="w-56 rounded-2xl border border-navy-900/10 bg-white">
          <div className="flex items-center justify-between border-b border-dashed border-navy-900/15 px-4 py-2.5">
            <p className="text-[11px] font-semibold uppercase tracking-wider text-navy-900">Receipt</p>
            <p className="font-mono text-[10px] text-slate-500">SV-4821</p>
          </div>
          <div className="space-y-1.5 px-4 py-3 text-xs">
            <div className="flex justify-between">
              <span className="text-slate-500">Amount</span>
              <span className="font-semibold tabular-nums text-navy-900">₦10,000.00</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-500">Turn</span>
              <span className="tabular-nums text-navy-900">5 of 12</span>
            </div>
          </div>
          <div className="flex items-center gap-1.5 rounded-b-2xl bg-electric px-4 py-2 text-[11px] font-medium text-white">
            <CheckCheck className="size-3.5" /> Confirmed by payer and collector
          </div>
        </div>
      </motion.div>
    </div>
  );
}

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-36 pb-20 sm:pt-44 lg:pb-28">
      {/* backdrop: blue light rays from the top */}
      <div className="absolute inset-0">
        <LightRays
          raysOrigin="top-center"
          raysColor="#3b6ae8"
          raysSpeed={1}
          lightSpread={0.9}
          rayLength={2.2}
          fadeDistance={1.4}
          followMouse
          mouseInfluence={0.08}
          noiseAmount={0.05}
          distortion={0.04}
          lightMode
        />
      </div>

      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-4 lg:grid-cols-[1.1fr_1fr]">
        <div>
          <motion.p
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            className="inline-flex items-center gap-2 rounded-full border border-navy-900/10 bg-white px-3.5 py-1.5 text-sm font-medium text-navy-800"
          >
            <MapPin className="size-4 text-electric" />
            Built in Nigeria for ajo, esusu and adashe
          </motion.p>

          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1, duration: 0.7 }}
            className="mt-6 font-display text-[3.4rem] font-extrabold leading-[0.95] tracking-[-0.04em] text-navy-900 sm:text-7xl lg:text-8xl"
          >
            Your ajo,
            <br />
            <span className="text-electric">on record.</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2, duration: 0.7 }}
            className="mt-6 max-w-xl text-lg text-pretty text-slate-600"
          >
            Sova keeps your savings circle honest. Every payment is confirmed by both sides, the payout
            order is drawn fairly where everyone can check it, and anyone who collects and stops paying
            shows up on the record. The money moves between you; Sova keeps the record.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3, duration: 0.7 }}
            className="mt-9 flex flex-wrap items-center gap-3"
          >
            <a
              href={site.appUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="group inline-flex items-center gap-2 rounded-2xl bg-electric px-6 py-4 font-semibold text-white transition hover:bg-electric-400 active:scale-[0.98]"
            >
              Try the live demo
              <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
            </a>
            <a
              href="#waitlist"
              className="inline-flex items-center gap-2 rounded-2xl border border-navy-900/15 bg-white px-6 py-4 font-semibold text-navy-900 transition hover:border-electric/40 hover:bg-mist active:scale-[0.98]"
            >
              Join the waitlist
            </a>
          </motion.div>

          <motion.ul
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.5, duration: 0.7 }}
            className="mt-10 grid grid-cols-1 divide-y divide-navy-900/10 border-y border-navy-900/10 sm:flex sm:w-fit sm:divide-x sm:divide-y-0"
          >
            {[
              { icon: Landmark, text: "Your money, your bank" },
              { icon: UsersRound, text: "Both sides confirm" },
              { icon: Lock, text: "Private by design" },
            ].map((t) => (
              <li key={t.text} className="flex items-center gap-2.5 whitespace-nowrap py-3 text-sm font-medium text-navy-800 sm:px-5 sm:first:pl-0 sm:last:pr-0">
                <t.icon className="size-4 shrink-0 text-electric" /> {t.text}
              </li>
            ))}
          </motion.ul>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 40, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ delay: 0.25, duration: 0.9, ease: [0.21, 0.47, 0.32, 0.98] }}
          className="relative"
        >
          {/* adire cloth panel behind the phone */}
          <div className="pointer-events-none absolute left-1/2 top-1/2 h-[88%] w-[88%] max-w-[440px] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-[2.5rem] bg-electric">
            <AdirePattern id="hero-adire" className="text-white/15" />
          </div>
          <PhoneMock />
        </motion.div>
      </div>
    </section>
  );
}
