"use client";

import { useRef } from "react";
import Image from "next/image";
import { BookOpenCheck, Check, LayoutDashboard, MessageSquareText } from "lucide-react";
import { AnimatedBeam } from "@/components/ui/animated-beam";
import { Reveal } from "@/components/ui/reveal";
import { cn } from "@/lib/utils";

function Node({
  ref,
  className,
  children,
  label,
}: {
  ref: React.Ref<HTMLDivElement>;
  className?: string;
  children: React.ReactNode;
  label: string;
}) {
  return (
    <div className="z-10 flex flex-col items-center gap-2">
      <div
        ref={ref}
        className={cn(
          "flex size-14 items-center justify-center rounded-full border border-navy-900/10 bg-white text-electric",
          className,
        )}
      >
        {children}
      </div>
      <span className="text-xs font-medium text-slate-600">{label}</span>
    </div>
  );
}

function Initial({ letter }: { letter: string }) {
  return <span className="font-display text-lg font-semibold text-navy-900">{letter}</span>;
}

function FlowDiagram() {
  const containerRef = useRef<HTMLDivElement>(null);
  const m1 = useRef<HTMLDivElement>(null);
  const m2 = useRef<HTMLDivElement>(null);
  const m3 = useRef<HTMLDivElement>(null);
  const hub = useRef<HTMLDivElement>(null);
  const o1 = useRef<HTMLDivElement>(null);
  const o2 = useRef<HTMLDivElement>(null);
  const o3 = useRef<HTMLDivElement>(null);

  return (
    <div
      ref={containerRef}
      className="relative flex h-[380px] w-full items-center justify-center overflow-hidden rounded-3xl border border-navy-900/10 bg-white p-6 sm:p-10"
    >
      <div className="flex size-full max-w-lg items-center justify-between">
        <div className="flex h-full flex-col justify-between">
          <Node ref={m1} label="Aisha">
            <Initial letter="A" />
          </Node>
          <Node ref={m2} label="Tunde">
            <Initial letter="T" />
          </Node>
          <Node ref={m3} label="Ngozi">
            <Initial letter="N" />
          </Node>
        </div>

        <Node ref={hub} label="Sova records" className="size-20 border-2 border-electric">
          <Image src="/brand/sova-mark-navy.png" alt="" width={44} height={44} className="size-11" />
        </Node>

        <div className="flex h-full flex-col justify-between">
          <Node ref={o1} label="SMS receipt">
            <MessageSquareText className="size-6" />
          </Node>
          <Node ref={o2} label="Group record">
            <BookOpenCheck className="size-6" />
          </Node>
          <Node ref={o3} label="Collector view">
            <LayoutDashboard className="size-6" />
          </Node>
        </div>
      </div>

      <AnimatedBeam containerRef={containerRef} fromRef={m1} toRef={hub} curvature={-60} endYOffset={-10} duration={4} />
      <AnimatedBeam containerRef={containerRef} fromRef={m2} toRef={hub} duration={4} delay={0.4} />
      <AnimatedBeam containerRef={containerRef} fromRef={m3} toRef={hub} curvature={60} endYOffset={10} duration={4} delay={0.8} />
      <AnimatedBeam containerRef={containerRef} fromRef={hub} toRef={o1} curvature={-60} startYOffset={-10} duration={4} delay={1.6} />
      <AnimatedBeam containerRef={containerRef} fromRef={hub} toRef={o2} duration={4} delay={2} />
      <AnimatedBeam containerRef={containerRef} fromRef={hub} toRef={o3} curvature={60} startYOffset={10} duration={4} delay={2.4} />
    </div>
  );
}

export function RecordFlow() {
  return (
    <section className="px-4 py-24 sm:py-32">
      <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-2">
        <Reveal>
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-electric">No wallet, no middleman</p>
          <h2 className="mt-4 font-display text-3xl font-semibold tracking-tight text-balance text-navy-900 sm:text-5xl">
            Money moves between members. Sova keeps the record.
          </h2>
          <p className="mt-4 max-w-lg text-lg text-slate-600">
            Members pay each other by transfer or cash, the way they always have. Sova never holds your
            contributions, so there&apos;s no wallet to hack and no company sitting on your savings.
          </p>
          <ul className="mt-8 space-y-3">
            {[
              "No Sova wallet, no locked funds",
              "Both sides confirm each payment",
              "A clear history anyone in the group can check",
            ].map((t) => (
              <li key={t} className="flex items-center gap-3 text-navy-800">
                <span className="grid size-6 shrink-0 place-items-center rounded-full bg-electric text-white">
                  <Check className="size-3.5" />
                </span>
                {t}
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={0.1}>
          <FlowDiagram />
        </Reveal>
      </div>
    </section>
  );
}
