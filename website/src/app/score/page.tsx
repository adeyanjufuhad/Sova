import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ArrowLeft } from "lucide-react";
import { Logo } from "@/components/ui/logo";
import { SharedScore } from "@/components/score/shared-score";

export const metadata: Metadata = {
  title: "Sova Score · Sova",
  description: "A savings record shared by a Sova member, checked by Sova.",
  // Shared links are personal; keep them out of search results.
  robots: { index: false, follow: false },
};

export default function ScorePage() {
  return (
    <div className="min-h-dvh bg-mist">
      <header className="border-b border-navy-900/10 bg-white">
        <div className="mx-auto flex max-w-2xl items-center justify-between px-4 py-4">
          <Link href="/" aria-label="Sova home">
            <Logo variant="navy" />
          </Link>
          <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-slate-600 hover:text-electric">
            <ArrowLeft aria-hidden className="size-4" /> What is Sova?
          </Link>
        </div>
      </header>

      <main id="main" className="mx-auto max-w-2xl px-4 py-12 sm:py-16">
        <h1 className="font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-navy-900 sm:text-5xl">
          A shared savings record
        </h1>
        <p className="mt-4 text-lg text-slate-600">
          Someone in an ajo, esusu or adashe circle shared their Sova Score with you. It shows how reliably they pay
          their circle.
        </p>

        <div className="mt-10">
          <Suspense fallback={null}>
            <SharedScore />
          </Suspense>
        </div>

        <p className="mt-10 text-sm text-slate-500">
          A Sova Score describes a member&apos;s record of paying their savings circle. It is not a credit rating, and
          Sova is not a bank, lender or wallet: it never holds, lends or invests money.
        </p>
      </main>
    </div>
  );
}
