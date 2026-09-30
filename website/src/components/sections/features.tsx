import { CloudOff, ListOrdered, MessageSquareText, Mic, Smartphone } from "lucide-react";
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

function ReceiptVisual() {
  return (
    <div className="mt-6 space-y-2">
      {[
        { text: "Ngozi, your ₦10,000 for Balogun Market Ajo is due tomorrow.", t: "Thu 6:00pm" },
        { text: "Received! Ngozi paid ₦10,000. Turn 5 of 12. Ref SV-4821", t: "Fri 9:12am" },
      ].map((m) => (
        <div key={m.t} className="max-w-sm rounded-2xl rounded-bl-md bg-mist px-4 py-3">
          <p className="text-sm text-navy-800">{m.text}</p>
          <p className="mt-1 text-[11px] text-slate-500">{m.t}</p>
        </div>
      ))}
    </div>
  );
}

function OrderVisual() {
  const rows = [
    { n: "Iya Bisi", tag: "5 cycles on time", w: "w-full" },
    { n: "Chinedu", tag: "3 cycles on time", w: "w-4/5" },
    { n: "New member", tag: "Collects last", w: "w-2/5" },
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

const small = [
  {
    icon: Mic,
    title: "Speaks your language",
    body: "Voice prompts and big, clear icons in English, Pidgin, Yoruba, Hausa and Igbo. Less reading, less typing.",
  },
  {
    icon: CloudOff,
    title: "Works without signal",
    body: "Record payments offline in the market. Sova syncs once your network comes back.",
  },
  {
    icon: Smartphone,
    title: "Light on your phone",
    body: "A small app built for low-storage Android phones and expensive data.",
  },
];

export function Features() {
  return (
    <section id="features" className="scroll-mt-24 bg-mist px-4 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          eyebrow="Features"
          title="Everything your circle argues about, settled."
          sub="Built around the real reasons ajo groups break: forgotten payments, disputed records and people who collect early and disappear."
        />

        <div className="mt-16 grid gap-4 md:grid-cols-6">
          <Reveal className="md:col-span-4">
            <Card className="h-full p-7 sm:p-8">
              <IconTile icon={MessageSquareText} />
              <h3 className="mt-6 font-display text-2xl font-semibold text-navy-900">Reminders and receipts by SMS</h3>
              <p className="mt-2 max-w-md text-slate-600">
                Every member gets a reminder before their day and a receipt from Sova when they pay. It works on any
                phone, even without the app.
              </p>
              <ReceiptVisual />
            </Card>
          </Reveal>

          <Reveal delay={0.1} className="md:col-span-2">
            <Card className="h-full p-7">
              <IconTile icon={ListOrdered} />
              <h3 className="mt-6 font-display text-xl font-semibold text-navy-900">Fair payout order</h3>
              <p className="mt-2 text-sm text-slate-600">New members collect last. A good record moves you up next cycle.</p>
              <OrderVisual />
            </Card>
          </Reveal>

          {small.map((f, i) => (
            <Reveal key={f.title} delay={0.1 * i} className="md:col-span-2">
              <Card className="h-full p-7">
                <IconTile icon={f.icon} />
                <h3 className="mt-6 font-display text-xl font-semibold text-navy-900">{f.title}</h3>
                <p className="mt-2 text-sm text-slate-600">{f.body}</p>
              </Card>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
