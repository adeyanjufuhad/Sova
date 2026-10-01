import { Marquee } from "@/components/ui/marquee";

// Real Nigerian markets where ajo and esusu are part of daily trade.
// (Places Sova is built for, not partners.)
const markets = [
  "Balogun, Lagos",
  "Kurmi, Kano",
  "Onitsha Main Market",
  "Ariaria, Aba",
  "Dugbe, Ibadan",
  "Alaba International, Lagos",
  "Wuse, Abuja",
  "Oil Mill, Port Harcourt",
  "Ogbete, Enugu",
  "Sabon Gari, Kano",
  "Bodija, Ibadan",
  "Oshodi, Lagos",
];

export function Ticker() {
  return (
    <div className="border-y border-navy-900/10 bg-white">
      <div className="mx-auto flex max-w-6xl items-center gap-6 px-4 py-5">
        <p className="hidden shrink-0 border-r border-navy-900/10 pr-6 text-sm font-semibold text-navy-900 md:block">Built for traders in</p>
        <Marquee className="min-w-0 flex-1 [--duration:50s]">
          {markets.map((m) => (
            <span key={m} className="flex items-center gap-10 whitespace-nowrap text-sm font-medium text-slate-600">
              {m}
              <span className="size-1.5 rotate-45 bg-electric" />
            </span>
          ))}
        </Marquee>
      </div>
    </div>
  );
}
