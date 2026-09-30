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
    <div className="relative bg-electric py-5">
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 w-24 bg-gradient-to-r from-electric to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 w-24 bg-gradient-to-l from-electric to-transparent" />
      <Marquee className="[--duration:35s]">
        {words.map((w) => (
          <span key={w} className="flex items-center gap-10 font-mono text-sm uppercase tracking-[0.25em] text-white/85">
            {w}
            <span className="size-1.5 rounded-full bg-white/60" />
          </span>
        ))}
      </Marquee>
    </div>
  );
}
