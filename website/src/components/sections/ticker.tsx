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
