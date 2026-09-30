"use client";

import { motion } from "motion/react";
import { ArrowRight, BellRing, Check, Clock3, ShieldCheck } from "lucide-react";
import { LightRays } from "@/components/ui/light-rays";
import { DownloadButton } from "@/components/ui/download-button";

const members = [
  { name: "Aisha B.", status: "paid" },
  { name: "Tunde O.", status: "paid" },
  { name: "Ngozi E.", status: "due" },
  { name: "Musa K.", status: "paid" },
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
              <p className="font-display text-3xl font-semibold text-white">₦120,000</p>
              <span className="rounded-full bg-sky/15 px-2 py-0.5 text-[10px] font-medium text-sky">
                Turn 5 of 12
              </span>
            </div>
            <p className="mt-0.5 text-[11px] text-slate-400">This week&apos;s pot · ₦10,000 × 12</p>

            <div className="mt-4 h-1.5 overflow-hidden rounded-full bg-white/10">
              <motion.div
                className="h-full rounded-full bg-sky"
                initial={{ width: "0%" }}
                animate={{ width: "75%" }}
                transition={{ duration: 1.6, delay: 0.6, ease: "easeOut" }}
              />
            </div>
            <p className="mt-1.5 text-[11px] text-slate-400">9 of 12 paid</p>
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

          <div className="m-3 rounded-2xl bg-electric p-3.5">
            <p className="text-[11px] text-white/70">Next payout · Friday</p>
            <p className="mt-0.5 font-medium text-white">Mama Chidinma collects ₦120,000</p>
          </div>
        </div>
      </div>

      {/* floating receipt */}
      <motion.div
        initial={{ opacity: 0, x: 30 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 1.2, duration: 0.6 }}
        className="absolute -right-4 -top-6 hidden animate-float sm:block lg:-right-24"
      >
        <div className="flex w-56 items-start gap-3 rounded-2xl border border-navy-900/10 bg-white p-3">
          <span className="grid size-8 shrink-0 place-items-center rounded-xl bg-electric/10 text-electric">
            <BellRing className="size-4" />
          </span>
          <div>
            <p className="text-[11px] text-slate-500">SMS receipt · just now</p>
            <p className="text-sm leading-snug text-navy-900">Tunde paid ₦10,000. Recorded by Sova.</p>
          </div>
        </div>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, x: -30 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 1.5, duration: 0.6 }}
        className="absolute -bottom-16 left-1/2 hidden -translate-x-1/2 animate-float whitespace-nowrap [animation-delay:1.5s] sm:block"
      >
        <div className="flex items-center gap-2.5 rounded-2xl border border-navy-900/10 bg-white px-3.5 py-2.5">
          <ShieldCheck className="size-5 text-electric" />
          <p className="text-sm text-navy-900">Sova never holds your money</p>
        </div>
      </motion.div>
    </div>
  );
}

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-32 pb-20 sm:pt-40 lg:pb-32">
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
          <motion.a
            href="#how"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            className="inline-flex items-center gap-2 rounded-full border border-navy-900/10 bg-white py-1.5 pl-1.5 pr-4 text-sm text-navy-800"
          >
            <span className="rounded-full bg-electric px-2.5 py-0.5 text-xs font-medium text-white">New</span>
            Ajo · Esusu · Adashe, now with receipts
            <ArrowRight className="size-3.5" />
          </motion.a>

          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1, duration: 0.7 }}
            className="mt-6 font-display text-5xl font-semibold leading-[1.02] tracking-tight text-navy-900 sm:text-6xl lg:text-7xl"
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
            Sova keeps your savings circle honest. Every contribution gets a receipt, every member
            knows their turn, and reminders go out before anyone forgets. The money moves between
            you, Sova just keeps the record.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3, duration: 0.7 }}
            className="mt-9 flex flex-wrap items-center gap-3"
          >
            <a
              href="#waitlist"
              className="group inline-flex items-center gap-2 rounded-2xl bg-electric px-6 py-4 font-medium text-white transition hover:bg-electric-400"
            >
              Join the waitlist
              <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
            </a>
            <DownloadButton />
          </motion.div>

          <motion.ul
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.5, duration: 0.7 }}
            className="mt-10 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate-500"
          >
            {["SMS receipts", "Works on low-end Android", "English, Pidgin, Yoruba, Hausa, Igbo"].map((t) => (
              <li key={t} className="flex items-center gap-2">
                <Check className="size-4 text-electric" /> {t}
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
          {/* orbit rings echoing the logo */}
          <div className="pointer-events-none absolute left-1/2 top-1/2 size-[520px] -translate-x-1/2 -translate-y-1/2">
            <div className="absolute inset-0 animate-spin-slow rounded-full border border-dashed border-electric/20" />
            <div className="absolute inset-12 rounded-full border border-electric/10" />
            <div className="absolute inset-24 rounded-full border border-sky/30" />
          </div>
          <PhoneMock />
        </motion.div>
      </div>
    </section>
  );
}
