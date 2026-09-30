import { Marquee } from "@/components/ui/marquee";

const words = [
  "Ajo",
  "Esusu",
  "Adashe",
  "Savings circles",
  "Market collectors",
  "SMS receipts",
  "Payout order",
  "No lost notebooks",
];

export function Ticker() {
  return (
    <div className="relative border-y border-white/10 bg-navy-950/60 py-5">
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 w-24 bg-gradient-to-r from-ink to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 w-24 bg-gradient-to-l from-ink to-transparent" />
      <Marquee className="[--duration:35s]">
        {words.map((w) => (
          <span key={w} className="flex items-center gap-10 font-mono text-sm uppercase tracking-[0.25em] text-slate-400">
            {w}
            <span className="size-1.5 rounded-full bg-electric" />
          </span>
        ))}
      </Marquee>
    </div>
  );
}
