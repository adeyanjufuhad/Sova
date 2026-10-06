import { X } from "lucide-react";
import { AdirePattern } from "@/components/ui/adire";
import { Logo } from "@/components/ui/logo";
import { Reveal } from "@/components/ui/reveal";

const promises = [
  {
    title: "We never hold your money",
    body: "Contributions go straight from member to member, through your own bank or in cash. There is no Sova wallet to empty.",
  },
  {
    title: "Your record belongs to you",
    body: "Your payment history is yours. It is only shared with a lender, landlord or supplier when you choose to share it.",
  },
  {
    title: "We do not sell your data",
    body: "Your name, number and payments are used to run your circle and nothing else. Sova is built to follow the Nigeria Data Protection Act.",
  },
  {
    title: "Every naira is accounted for",
    body: "Both sides confirm each payment, short payouts open a dispute on their own, and disputes are settled by the record, not by memory.",
  },
];

export function SovaPromise() {
  return (
    <section id="promise" className="scroll-mt-24 bg-mist px-4 py-24 sm:py-32">
      <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[1fr_1.25fr]">
        <Reveal className="lg:sticky lg:top-32 lg:self-start">
          <p className="flex items-center gap-2 font-mono text-xs uppercase tracking-[0.2em] text-electric">
            <span className="size-1.5 bg-electric" /> Our promise
          </p>
          <h2 className="mt-4 font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-balance text-navy-900 sm:text-5xl">
            Trust is the whole product.
          </h2>
          <p className="mt-4 max-w-md text-lg text-slate-600">
            An ajo only works when everyone believes the record. These are the rules Sova is built on, and they
            don&apos;t change.
          </p>

          <div className="mt-8">
            <p className="text-sm font-semibold text-navy-900">What Sova is not</p>
            <ul className="mt-3 flex flex-wrap gap-2">
              {["Not a bank", "Not a lender", "Not a wallet"].map((t) => (
                <li
                  key={t}
                  className="flex items-center gap-1.5 rounded-full border border-navy-900/15 bg-white px-3 py-1.5 text-sm font-medium text-navy-800"
                >
                  <X className="size-3.5 text-electric" /> {t}
                </li>
              ))}
            </ul>
          </div>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="overflow-hidden rounded-3xl border border-navy-900/10 bg-white">
            <div className="relative h-16 overflow-hidden bg-electric">
              <AdirePattern id="promise-adire" className="text-white/15" />
            </div>
            <ol className="divide-y divide-navy-900/10">
              {promises.map((p, i) => (
                <li key={p.title} className="flex gap-5 px-6 py-6 sm:px-8">
                  <span className="font-mono text-sm font-semibold text-electric">0{i + 1}</span>
                  <div>
                    <h3 className="text-lg font-bold text-navy-900">{p.title}</h3>
                    <p className="mt-1.5 text-slate-600">{p.body}</p>
                  </div>
                </li>
              ))}
            </ol>
            <div className="flex items-center justify-between border-t border-navy-900/10 px-6 py-5 sm:px-8">
              <Logo variant="navy" />
              <p className="text-sm italic text-slate-500">The Sova team</p>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
