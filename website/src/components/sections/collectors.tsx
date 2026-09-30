import { ArrowRight, BadgeCheck, Calculator, FileText, Route } from "lucide-react";
import { Reveal } from "@/components/ui/reveal";
import { BorderBeam } from "@/components/ui/border-beam";

const owing = [
  { name: "Mama Nkechi", stall: "Row C · Fabrics", amt: "₦2,000", late: false },
  { name: "Alhaji Sani", stall: "Row F · Grains", amt: "₦5,000", late: true },
  { name: "Iya Ronke", stall: "Row A · Pepper", amt: "₦1,500", late: false },
  { name: "Emeka", stall: "Row D · Phones", amt: "₦3,000", late: false },
];

function Dashboard() {
  return (
    <div className="relative rounded-3xl border border-white/15 bg-navy-950/80 p-5 shadow-[0_40px_100px_-30px_rgba(0,0,0,0.8)] backdrop-blur">
      <BorderBeam size={240} duration={12} delay={3} />
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs text-slate-400">Collector dashboard</p>
          <p className="font-display text-lg font-semibold text-white">Who&apos;s owing today</p>
        </div>
        <span className="rounded-full bg-white/5 px-3 py-1 text-xs text-slate-300">4 groups · 63 traders</span>
      </div>

      <div className="mt-5 grid grid-cols-3 gap-2">
        {[
          { k: "Collected", v: "₦184,500" },
          { k: "Outstanding", v: "₦11,500" },
          { k: "Your commission", v: "₦6,150" },
        ].map((s) => (
          <div key={s.k} className="rounded-2xl bg-white/[0.04] p-3">
            <p className="text-[10px] uppercase tracking-wider text-slate-500">{s.k}</p>
            <p className="mt-1 font-display text-base font-semibold text-white sm:text-lg">{s.v}</p>
          </div>
        ))}
      </div>

      <ul className="mt-4 divide-y divide-white/5">
        {owing.map((o) => (
          <li key={o.name} className="flex items-center justify-between py-3">
            <div>
              <p className="text-sm text-slate-100">{o.name}</p>
              <p className="text-xs text-slate-500">{o.stall}</p>
            </div>
            <div className="flex items-center gap-3">
              {o.late && (
                <span className="rounded-full bg-sky/15 px-2 py-0.5 text-[10px] font-medium text-sky">1 day late</span>
              )}
              <span className="font-mono text-sm text-white">{o.amt}</span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

const perks = [
  { icon: Route, title: "Daily collection list", body: "See who's owing and plan your round through the market." },
  { icon: Calculator, title: "Commission worked out", body: "Your fee is calculated automatically every cycle." },
  { icon: FileText, title: "Monthly statements", body: "Show members clean records and grow your reputation." },
  { icon: BadgeCheck, title: "Verified collector badge", body: "Stand out from fake organisers with a verified identity." },
];

export function Collectors() {
  return (
    <section id="collectors" className="relative scroll-mt-24 overflow-hidden px-4 py-24 sm:py-32">
      <div className="absolute inset-0 bg-gradient-to-br from-electric via-navy-700 to-navy-950" />
      <div className="bg-grid absolute inset-0 opacity-60 [mask-image:linear-gradient(to_bottom,black,transparent)]" />
      <div className="pointer-events-none absolute -left-20 -top-20 size-[500px] rounded-full bg-sky/30 blur-[120px]" />

      <div className="relative mx-auto grid max-w-6xl items-center gap-14 lg:grid-cols-2">
        <div>
          <Reveal>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky-300">For alajo &amp; esusu collectors</p>
            <h2 className="mt-4 font-display text-3xl font-semibold tracking-tight text-balance text-white sm:text-5xl">
              Run every group from one phone.
            </h2>
            <p className="mt-4 text-lg text-white/75">
              You already manage dozens of traders from memory and a notebook. Sova gives you a dashboard,
              and gives your members proof, so they trust you more, not less.
            </p>
          </Reveal>

          <div className="mt-10 grid gap-3 sm:grid-cols-2">
            {perks.map((p, i) => (
              <Reveal key={p.title} delay={i * 0.08}>
                <div className="glass h-full rounded-2xl p-4">
                  <p.icon className="size-5 text-sky-300" />
                  <p className="mt-3 font-medium text-white">{p.title}</p>
                  <p className="mt-1 text-sm text-white/65">{p.body}</p>
                </div>
              </Reveal>
            ))}
          </div>

          <Reveal delay={0.2}>
            <a
              href="#waitlist"
              className="group mt-10 inline-flex items-center gap-2 rounded-2xl bg-white px-6 py-4 font-medium text-navy-900 transition hover:bg-sky-300"
            >
              Register as a collector
              <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
            </a>
          </Reveal>
        </div>

        <Reveal delay={0.15}>
          <Dashboard />
        </Reveal>
      </div>
    </section>
  );
}
