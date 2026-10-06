import { ArrowRight, Check, Link2 } from "lucide-react";
import { AdirePattern } from "@/components/ui/adire";
import { Reveal } from "@/components/ui/reveal";
import { SectionHeading } from "@/components/ui/section-heading";

// An illustration of what the public record looks like: the entry kinds and the
// hash rule are the real ones (see docs/ledger.md); the hashes are examples.
const entries = [
  { seq: 14, kind: "payment_marked", text: "Ngozi marked ₦10,000 as sent", hash: "9f2c41e07ab3" },
  { seq: 15, kind: "payment_confirmed", text: "Tunde confirmed it arrived", hash: "41d8a0c96e57" },
  { seq: 16, kind: "dispute_vote", text: "Aisha voted: it arrived", hash: "c07e5b2f19da" },
  { seq: 17, kind: "payout_confirmed", text: "Tunde received ₦90,000 for turn 5", hash: "e6b19d3a7c40" },
];

function LedgerMock() {
  return (
    <div className="relative">
      <div className="overflow-hidden rounded-3xl border border-white/10 bg-navy-800">
        <div className="flex items-center justify-between border-b border-white/10 px-5 py-4">
          <p className="text-sm font-semibold text-white">Circle record</p>
          <p className="text-xs font-semibold text-sky-300">Example</p>
        </div>
        <ol className="divide-y divide-white/10">
          {entries.map((e) => (
            <li key={e.seq} className="grid grid-cols-[2.25rem_1fr] items-center gap-3 px-5 py-4 sm:grid-cols-[2.25rem_1fr_auto]">
              <span className="font-mono text-xs text-white/40 tabular-nums">#{e.seq}</span>
              <div className="min-w-0">
                <p className="truncate text-sm text-white">{e.text}</p>
                <p className="truncate font-mono text-[11px] text-white/45">{e.kind}</p>
              </div>
              <span className="hidden items-center gap-1.5 font-mono text-[11px] text-sky-300 tabular-nums sm:flex">
                <Link2 aria-hidden className="size-3.5" />
                {e.hash}…
              </span>
            </li>
          ))}
        </ol>
        {/* Bottom padding leaves room for the overlapping card below. */}
        <p className="border-t border-white/10 px-5 pt-4 pb-14 font-mono text-[11px] leading-relaxed text-white/50">
          hash = SHA-256(previous hash | seq | kind | body)
        </p>
      </div>

      {/* Overlapping result card: depth from layering, not shadows. */}
      <div className="relative -mt-8 ml-auto w-[88%] rounded-2xl border border-navy-900/10 bg-white p-5 sm:-mr-6 sm:w-[78%]">
        <p className="text-sm font-semibold text-navy-900">Rechecked in your browser</p>
        <ul className="mt-3 space-y-2 text-sm text-navy-800">
          {["Every hash links to the one before", "The draw seed matches its sealed fingerprint", "The payout order recomputes exactly"].map(
            (t) => (
              <li key={t} className="flex items-start gap-2.5">
                <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-electric text-white">
                  <Check aria-hidden className="size-3" />
                </span>
                {t}
              </li>
            ),
          )}
        </ul>
      </div>
    </div>
  );
}

/** Full-bleed navy band: the record, shown as the product it is. */
export function LedgerBand() {
  return (
    <section id="record" className="relative scroll-mt-24 overflow-hidden bg-navy-900 px-4 py-24 sm:py-32">
      <AdirePattern id="ledger-adire" className="text-white/[0.04]" />
      <div className="relative mx-auto grid max-w-6xl items-center gap-14 lg:grid-cols-12">
        <div className="lg:col-span-5">
          <SectionHeading tone="dark" className="lg:block" eyebrow="Tamper-evident record" title="Don't trust us. Check." />
          <p className="mt-6 max-w-[46ch] text-lg text-pretty text-white/75">
            Every payment, payout, vote and dispute is chained to the one before it. Change one past entry and every
            link after it breaks, so anyone can tell. You don&apos;t need an account to check a circle.
          </p>
          <a
            href="/verify/"
            className="group mt-8 inline-flex items-center gap-2 rounded-2xl bg-white px-6 py-4 font-semibold text-navy-900 transition-colors hover:bg-mist active:scale-[0.98]"
          >
            Verify a circle
            <ArrowRight aria-hidden className="size-4 transition-transform group-hover:translate-x-0.5" />
          </a>
          <p className="mt-4 text-sm text-white/50">Tamper-evident, not tamper-proof: a change can&apos;t go unnoticed.</p>
        </div>
        <Reveal delay={0.1} className="lg:col-span-7">
          <LedgerMock />
        </Reveal>
      </div>
    </section>
  );
}
