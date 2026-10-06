"use client";

import { OrbitingCircles, type Orbit } from "@/components/ui/orbiting-circles";
import { SectionHeading } from "@/components/ui/section-heading";

// The same savings tradition, by the names people across Africa know it.
function NameTag({ name, place, primary }: { name: string; place: string; primary?: boolean }) {
  return (
    <span
      className={
        primary
          ? "flex h-10 items-center gap-2 whitespace-nowrap rounded-full bg-electric px-4 text-sm font-semibold text-white"
          : "flex h-10 items-center gap-2 whitespace-nowrap rounded-full border border-navy-900/10 bg-white px-4 text-sm font-semibold text-navy-900"
      }
    >
      {name}
      <span className={primary ? "text-xs font-medium text-white/70" : "text-xs font-medium text-slate-500"}>{place}</span>
    </span>
  );
}

const tag = (name: string, place: string, angle: number, primary = false) => ({
  id: name,
  angle,
  content: <NameTag name={name} place={place} primary={primary} />,
});

const orbits: Orbit[] = [
  {
    size: "size-110 md:size-180",
    duration: 60,
    items: [tag("Ajo", "Yoruba", -50, true), tag("Adashe", "Hausa", 10, true), tag("Isusu", "Igbo", 70, true)],
  },
  {
    size: "size-150 md:size-220",
    duration: 80,
    items: [tag("Susu", "Ghana", -70), tag("Tontine", "Cameroon", -20), tag("Esusu", "Nigeria", 30), tag("Chama", "Kenya", 80)],
  },
  {
    size: "size-180 md:size-265",
    duration: 100,
    items: [tag("Stokvel", "South Africa", -40), tag("Equb", "Ethiopia", 15), tag("Likelemba", "DR Congo", 55)],
  },
];

export function Circle() {
  return (
    <section className="relative overflow-hidden pt-24 sm:pt-32">
      {/* Ghost watermark: the tradition's names, faint and oversized, behind the orbit. */}
      <p
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-[46%] select-none whitespace-nowrap text-center font-display text-[13vw] font-extrabold leading-none tracking-[-0.05em] text-navy-900/[0.035] lg:text-[11.5vw]"
      >
        ajo esusu adashe
      </p>
      <SectionHeading
        align="center"
        className="px-4"
        eyebrow="Across Africa"
        title="One tradition. Many names."
        sub="Rotating savings circles helped Africans save for generations, long before banks reached every market. Sova is built on that trust, not against it."
      />
      <div className="mt-6">
        <OrbitingCircles orbits={orbits} />
      </div>
    </section>
  );
}
