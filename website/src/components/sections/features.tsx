import {
  ArrowLeftRight,
  CheckCheck,
  CloudOff,
  FileSignature,
  Gavel,
  Globe,
  Handshake,
  ListOrdered,
  Mic,
  ReceiptText,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { Reveal } from "@/components/ui/reveal";
import { SectionHeading } from "@/components/ui/section-heading";

function IconTile({ icon: Icon }: { icon: React.ComponentType<{ className?: string }> }) {
  return (
    <span className="grid size-11 place-items-center rounded-2xl bg-electric/10 text-electric">
      <Icon className="size-5" />
    </span>
  );
}

function Soon() {
  return (
    <span className="ml-2 inline-block rounded-full bg-electric/10 px-2 py-0.5 align-middle font-mono text-[10px] font-medium uppercase tracking-wider text-electric">
      Coming soon
    </span>
  );
}

function ReceiptVisual() {
  return (
    <div className="mt-6 space-y-2">
      {[
        { text: "Ngozi marked ₦10,000 as sent to Mama Chidinma. Bank ref FT2610ABC.", t: "Fri 9:04am" },
        { text: "Mama Chidinma confirmed it arrived. Receipt SV-4821, turn 5 of 12.", t: "Fri 9:12am" },
      ].map((m) => (
        <div key={m.t} className="flex max-w-sm items-start gap-2 rounded-2xl rounded-bl-md bg-mist px-4 py-3">
          <CheckCheck className="mt-0.5 size-4 shrink-0 text-electric" />
          <div>
            <p className="text-sm text-navy-800">{m.text}</p>
            <p className="mt-1 text-[11px] text-slate-500">{m.t}</p>
          </div>
        </div>
      ))}
    </div>
  );
}

function OrderVisual() {
  const rows = [
    { n: "Chinedu", tag: "hash 1f3a…", w: "w-1/4" },
    { n: "Iya Bisi", tag: "hash 6c09…", w: "w-3/5" },
    { n: "Mama Chidinma", tag: "Admin, pledged last", w: "w-full" },
  ];
  return (
    <ul className="mt-6 space-y-2.5">
      {rows.map((r, i) => (
        <li key={r.n} className="flex items-center gap-3">
          <span className="grid size-7 shrink-0 place-items-center rounded-full bg-electric/10 font-mono text-xs text-electric">
            {i + 1}
          </span>
          <div className="flex-1">
            <div className="flex justify-between text-sm">
              <span className="text-navy-800">{r.n}</span>
              <span className="text-xs text-slate-500">{r.tag}</span>
            </div>
            <div className="mt-1.5 h-1 rounded-full bg-navy-900/5">
              <div className={`h-full rounded-full bg-electric ${r.w}`} />
            </div>
          </div>
        </li>
      ))}
    </ul>
  );
}

// The fixes for how circles actually break.
type Item = { icon: typeof Gavel; title: string; body: string; soon?: boolean };

const trust: Item[] = [
  {
    icon: FileSignature,
    title: "Group rules everyone signs",
    body: "Late fines, leaving early, sickness and emergencies agreed up front. Sova saves who accepted which version, and when.",
  },
  {
    icon: ReceiptText,
    title: "Proof of payment",
    body: "Record the bank reference and attach a photo of the receipt. Only your circle can see it, and the collector confirms with their PIN.",
  },
  {
    icon: Handshake,
    title: "Members vouch for newcomers",
    body: "A new member joins on someone's word. If they collect and stop paying, the group sees it on the record.",
  },
  {
    icon: Gavel,
    title: "Disputes the circle decides",
    body: "A short payout opens a dispute automatically. If a payment is disputed, the members not involved vote on whether the money arrived, and every vote goes on the record.",
  },
  {
    icon: ArrowLeftRight,
    title: "Swap turns, hand over a slot",
    body: "Swap your turn with a willing member, or hand your place to someone the admin approves.",
    soon: true,
  },
];

const basics: Item[] = [
  { icon: Globe, title: "Works in your browser", body: "Try Sova from any phone or computer, no download needed. Android app too." },
  { icon: Mic, title: "Speaks your language", body: "Voice prompts in Pidgin, Yoruba, Hausa and Igbo.", soon: true },
  { icon: CloudOff, title: "Works without signal", body: "Record payments offline and sync when network returns.", soon: true },
];

export function Features() {
  return (
    <section id="features" className="scroll-mt-24 bg-mist px-4 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          eyebrow="Features"
          title="Everything your circle argues about, settled."
          sub="Built around the real reasons ajo groups break: forgotten payments, disputed records, emergencies mid-cycle and people who collect early and disappear."
        />

        <div className="mt-16 grid gap-4 md:grid-cols-6">
          <Reveal className="md:col-span-4">
            <Card className="h-full p-7 sm:p-8">
              <IconTile icon={ReceiptText} />
              <h3 className="mt-6 font-display text-2xl font-bold text-navy-900">A receipt both sides confirm</h3>
              <p className="mt-2 max-w-md text-slate-600">
                The payer marks the money as sent; the collector confirms it arrived with their PIN. Both get the same
                receipt, so &ldquo;I paid&rdquo; and &ldquo;I never got it&rdquo; can&apos;t both be true.
              </p>
              <ReceiptVisual />
            </Card>
          </Reveal>

          <Reveal delay={0.1} className="md:col-span-2">
            <Card className="h-full p-7">
              <IconTile icon={ListOrdered} />
              <h3 className="mt-6 font-display text-xl font-bold text-navy-900">A payout order nobody can rig</h3>
              <p className="mt-2 text-sm text-slate-600">
                Sova seals a random seed before anyone joins, then draws the order from it when the circle is full. Anyone
                can check the result.
              </p>
              <OrderVisual />
            </Card>
          </Reveal>

          {trust.map((f, i) => (
            <Reveal key={f.title} delay={0.06 * i} className={i < 3 ? "md:col-span-2" : "md:col-span-3"}>
              <Card className="h-full p-7">
                <IconTile icon={f.icon} />
                <h3 className="mt-6 font-display text-xl font-bold text-navy-900">
                  {f.title}
                  {f.soon && <Soon />}
                </h3>
                <p className="mt-2 text-sm text-slate-600">{f.body}</p>
              </Card>
            </Reveal>
          ))}

          <Reveal className="md:col-span-6">
            <ul className="grid divide-y divide-navy-900/10 rounded-3xl border border-navy-900/10 bg-white md:grid-cols-3 md:divide-x md:divide-y-0">
              {basics.map((b) => (
                <li key={b.title} className="flex items-start gap-4 p-6">
                  <b.icon className="mt-0.5 size-5 shrink-0 text-electric" />
                  <div>
                    <p className="font-bold text-navy-900">
                      {b.title}
                      {b.soon && <Soon />}
                    </p>
                    <p className="mt-1 text-sm text-slate-600">{b.body}</p>
                  </div>
                </li>
              ))}
            </ul>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
