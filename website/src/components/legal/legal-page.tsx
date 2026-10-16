import type { ReactNode } from "react";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { Logo } from "@/components/ui/logo";

// Shared frame for /privacy and /terms: the same white header as /verify, a
// plain-language summary box, then numbered sections with an index.
export function LegalPage({
  eyebrow,
  title,
  updated,
  intro,
  summary,
  sections,
  other,
}: {
  eyebrow: string;
  title: string;
  updated: string;
  intro: ReactNode;
  summary: ReactNode[];
  sections: { id: string; title: string; body: ReactNode }[];
  other: { href: string; label: string };
}) {
  return (
    <div className="min-h-dvh bg-mist">
      <header className="border-b border-navy-900/10 bg-white">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-4">
          <Link href="/" aria-label="Sova home">
            <Logo variant="navy" />
          </Link>
          <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-slate-600 hover:text-electric">
            <ArrowLeft aria-hidden className="size-4" /> Back to Sova
          </Link>
        </div>
      </header>

      <main id="main" className="mx-auto max-w-3xl px-4 py-12 sm:py-16">
        <p className="text-sm font-semibold text-electric">{eyebrow}</p>
        <h1 className="mt-4 font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-navy-900 sm:text-5xl">
          {title}
        </h1>
        <p className="mt-3 text-sm text-slate-500">Last updated {updated}</p>
        <div className="mt-6 max-w-2xl text-lg text-slate-600">{intro}</div>

        <section aria-labelledby="summary" className="mt-10 rounded-2xl border border-navy-900/10 bg-white p-6 sm:p-8">
          <h2 id="summary" className="font-display text-lg font-bold text-navy-900">
            The short version
          </h2>
          <ul className="mt-4 space-y-3 text-[15px] leading-relaxed text-slate-700">
            {summary.map((item, i) => (
              <li key={i} className="flex gap-3">
                <span aria-hidden className="mt-2.5 size-1.5 shrink-0 rounded-full bg-electric" />
                <span>{item}</span>
              </li>
            ))}
          </ul>
        </section>

        <nav aria-label="On this page" className="mt-10">
          <p className="text-sm font-semibold text-navy-900">On this page</p>
          <ol className="mt-3 grid gap-x-6 gap-y-1.5 text-sm sm:grid-cols-2">
            {sections.map((s, i) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className="text-slate-600 hover:text-electric">
                  <span className="font-mono tabular-nums text-slate-400">{String(i + 1).padStart(2, "0")}</span>{" "}
                  {s.title}
                </a>
              </li>
            ))}
          </ol>
        </nav>

        <div className="mt-10 divide-y divide-navy-900/10 border-t border-navy-900/10">
          {sections.map((s, i) => (
            <section key={s.id} id={s.id} aria-labelledby={`${s.id}-title`} className="scroll-mt-6 py-8">
              <h2 id={`${s.id}-title`} className="flex gap-3 font-display text-xl font-bold text-navy-900">
                <span className="font-mono text-base font-medium tabular-nums text-electric">
                  {String(i + 1).padStart(2, "0")}
                </span>
                {s.title}
              </h2>
              <div className="legal-prose mt-4 space-y-4 text-[15px] leading-relaxed text-slate-700">{s.body}</div>
            </section>
          ))}
        </div>

        <p className="mt-6 text-sm text-slate-500">
          See also:{" "}
          <Link href={other.href} className="text-electric underline">
            {other.label}
          </Link>
          .
        </p>
      </main>
    </div>
  );
}
