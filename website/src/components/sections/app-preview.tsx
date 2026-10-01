"use client";

import { Award, Check, ChevronRight, Clock3, Plus, Share2 } from "lucide-react";
import { ContainerScroll } from "@/components/ui/container-scroll-animation";
import { cn } from "@/lib/utils";

function Screen({ title, children, className }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("flex h-full w-full flex-col rounded-3xl border border-navy-900/10 bg-white p-4", className)}>
      <div className="flex items-center justify-between text-[10px] text-slate-400">
        <span>9:41</span>
        <span>4G</span>
      </div>
      <p className="mt-3 font-display text-lg font-semibold text-navy-900">{title}</p>
      <div className="mt-3 flex-1 space-y-2.5 overflow-hidden">{children}</div>
    </div>
  );
}

function HomeScreen() {
  const circles = [
    { name: "Balogun Market Ajo", amt: "₦10,000 weekly", turn: "Turn 5 of 12", due: "Pay Friday" },
    { name: "Office Esusu", amt: "₦50,000 monthly", turn: "Turn 2 of 6", due: "Paid" },
    { name: "Church Adashe", amt: "₦2,000 daily", turn: "Turn 18 of 30", due: "Pay today" },
  ];
  return (
    <Screen title="My circles">
      <div className="rounded-2xl bg-electric p-4 text-white">
        <p className="text-[11px] text-white/70">Your next payout</p>
        <p className="mt-1 font-display text-2xl font-semibold">₦120,000</p>
        <p className="text-[11px] text-white/70">Balogun Market Ajo · in 7 weeks</p>
      </div>
      {circles.map((c) => (
        <div key={c.name} className="flex items-center justify-between rounded-2xl border border-navy-900/10 p-3">
          <div>
            <p className="text-sm font-medium text-navy-900">{c.name}</p>
            <p className="text-[11px] text-slate-500">
              {c.amt} · {c.turn}
            </p>
          </div>
          <span
            className={cn(
              "rounded-full px-2 py-0.5 text-[10px] font-medium",
              c.due === "Paid" ? "bg-electric/10 text-electric" : "bg-navy-900 text-white",
            )}
          >
            {c.due}
          </span>
        </div>
      ))}
      <div className="flex items-center justify-center gap-2 rounded-2xl border border-dashed border-electric/40 p-3 text-sm font-medium text-electric">
        <Plus className="size-4" /> Start a new circle
      </div>
    </Screen>
  );
}

function GroupScreen() {
  const members = [
    { n: "Iya Bisi", s: "Collected", icon: Check },
    { n: "Chinedu", s: "Collected", icon: Check },
    { n: "Aisha B.", s: "Paid", icon: Check },
    { n: "Ngozi E.", s: "Due today", icon: Clock3 },
    { n: "Mama Chidinma", s: "Collects Fri", icon: ChevronRight },
  ];
  return (
    <Screen title="Balogun Market Ajo" className="hidden md:flex">
      <div className="grid grid-cols-3 gap-2 text-center">
        {[
          ["12", "members"],
          ["9/12", "paid"],
          ["Fri", "payout"],
        ].map(([v, k]) => (
          <div key={k} className="rounded-xl bg-mist p-2">
            <p className="font-display text-base font-semibold text-navy-900">{v}</p>
            <p className="text-[10px] text-slate-500">{k}</p>
          </div>
        ))}
      </div>
      <p className="pt-1 text-[10px] uppercase tracking-wider text-slate-400">Payout order</p>
      {members.map((m, i) => (
        <div key={m.n} className="flex items-center justify-between">
          <span className="flex items-center gap-2.5">
            <span className="grid size-7 place-items-center rounded-full bg-electric/10 font-mono text-[11px] text-electric">
              {i + 1}
            </span>
            <span className="text-sm text-navy-900">{m.n}</span>
          </span>
          <span className="flex items-center gap-1 text-[11px] text-slate-500">
            <m.icon className="size-3" /> {m.s}
          </span>
        </div>
      ))}
    </Screen>
  );
}

function RecordScreen() {
  return (
    <Screen title="My Sova record" className="hidden md:flex">
      <div className="rounded-2xl border border-navy-900/10 p-4 text-center">
        <p className="text-[11px] text-slate-500">On-time payments</p>
        <p className="font-display text-4xl font-bold text-electric">98%</p>
        <p className="text-[11px] text-slate-500">46 of 47 contributions</p>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-xl bg-mist p-3">
          <p className="font-display text-lg font-semibold text-navy-900">4</p>
          <p className="text-[10px] text-slate-500">cycles completed</p>
        </div>
        <div className="rounded-xl bg-mist p-3">
          <p className="font-display text-lg font-semibold text-navy-900">31 wks</p>
          <p className="text-[10px] text-slate-500">saving with Sova</p>
        </div>
      </div>
      <div className="flex items-center gap-3 rounded-2xl bg-navy-900 p-3 text-white">
        <Award className="size-5 text-sky" />
        <p className="text-sm">12-week on-time streak</p>
      </div>
      <div className="flex items-center justify-center gap-2 rounded-2xl bg-electric p-3 text-sm font-medium text-white">
        <Share2 className="size-4" /> Share my record
      </div>
    </Screen>
  );
}

export function AppPreview() {
  return (
    <section id="app" className="flex flex-col overflow-hidden px-4">
      <ContainerScroll
        titleComponent={
          <>
            <p className="inline-flex items-center gap-2 font-mono text-xs uppercase tracking-[0.2em] text-electric"><span className="size-1.5 bg-electric" /> The Sova app</p>
            <h2 className="mt-4 font-display text-4xl font-bold tracking-tight text-navy-900 md:text-6xl">
              Your whole circle,
              <br />
              in your pocket.
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-lg text-slate-600">
              Coming soon to Android. Built for small phones, slow networks and busy market days.
            </p>
            <div className="h-20 md:h-28" />
          </>
        }
      >
        <div className="grid h-full grid-cols-1 gap-4 p-3 md:grid-cols-3 md:p-0">
          <HomeScreen />
          <GroupScreen />
          <RecordScreen />
        </div>
      </ContainerScroll>
    </section>
  );
}
