import { ArrowLeftRight, ArrowRight, BadgeCheck, Bell, CloudOff, Landmark, Mic, Phone, Store } from "lucide-react";
import { Reveal } from "@/components/ui/reveal";
import { AdirePattern } from "@/components/ui/adire";

// What's next, honestly labelled. Nothing here is built yet.
const next = [
  { icon: ArrowLeftRight, title: "Swap turns, hand over a slot", body: "Swap your turn with a willing member, or hand your place to someone the admin approves." },
  { icon: Bell, title: "Reminders", body: "In-app reminders before your day first; SMS and WhatsApp later." },
  { icon: Store, title: "Collector mode", body: "For alajo and market collectors: a daily list of who's owing across many groups." },
  { icon: Phone, title: "USSD for basic phones", body: "Record and check payments without a smartphone or data." },
  { icon: Mic, title: "Voice and local languages", body: "Spoken prompts in Pidgin, Yoruba, Hausa and Igbo." },
  { icon: CloudOff, title: "Works offline", body: "Record payments without signal; sync when the network returns." },
  { icon: BadgeCheck, title: "Shareable Sova Score", body: "A trust card built from your on-time record, shared only when you choose." },
  { icon: Landmark, title: "Savings history as credit history", body: "Let lenders see your record, with your permission. Sova itself will never lend." },
];

export function Roadmap() {
  return (
    <section id="roadmap" className="relative scroll-mt-24 overflow-hidden px-4 py-24 sm:py-32">
      <div className="absolute inset-0 bg-electric" />
      <AdirePattern id="roadmap-adire" className="text-white/[0.08]" />

      <div className="relative mx-auto max-w-6xl">
        <Reveal className="max-w-2xl">
          <p className="flex items-center gap-2 text-sm font-semibold text-sky-300">
            Roadmap
          </p>
          <h2 className="mt-4 font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-balance text-white sm:text-6xl">
            What we&apos;re building next.
          </h2>
          <p className="mt-4 text-lg text-white/75">
            Sova works today for self-run circles. These come next, in roughly this order. None of them are live yet.
          </p>
        </Reveal>

        <div className="mt-12 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {next.map((p, i) => (
            <Reveal key={p.title} delay={i * 0.05}>
              <div className="h-full rounded-2xl border border-white/15 bg-white/10 p-5">
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
            className="group mt-10 inline-flex items-center gap-2 rounded-2xl bg-white px-6 py-4 font-medium text-navy-900 transition hover:bg-mist"
          >
            Tell us what you need first
            <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
          </a>
        </Reveal>
      </div>
    </section>
  );
}
