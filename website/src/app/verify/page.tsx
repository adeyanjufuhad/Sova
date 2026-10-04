import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ArrowLeft } from "lucide-react";
import { Logo } from "@/components/ui/logo";
import { VerifyCircle } from "@/components/verify/verify-circle";

export const metadata: Metadata = {
  title: "Verify a circle · Sova",
  description:
    "Check a Sova circle's tamper-evident record and fair payout draw yourself. Every hash is recomputed in your browser.",
};

export default function VerifyPage() {
  return (
    <div className="min-h-screen bg-mist">
      <header className="border-b border-navy-900/10 bg-white">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-4">
          <Link href="/" aria-label="Sova home">
            <Logo variant="navy" />
          </Link>
          <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-slate-600 hover:text-electric">
            <ArrowLeft className="size-4" /> Back to Sova
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-12 sm:py-16">
        <p className="inline-flex items-center gap-2 font-mono text-xs uppercase tracking-[0.2em] text-electric">
          <span className="size-1.5 bg-electric" /> Verify a circle
        </p>
        <h1 className="mt-4 font-display text-4xl font-bold tracking-tight text-navy-900 sm:text-5xl">
          Don&apos;t trust us. Check.
        </h1>
        <p className="mt-4 max-w-2xl text-lg text-slate-600">
          Every Sova circle keeps a tamper-evident record: each payment, payout and dispute is chained to the one
          before it with SHA-256. This page downloads a circle&apos;s record and recomputes every link in your
          browser, along with the fair payout draw.
        </p>

        <div className="mt-10">
          <Suspense fallback={null}>
            <VerifyCircle />
          </Suspense>
        </div>

        <p className="mt-10 text-sm text-slate-500">
          Tamper-evident, not tamper-proof: any change to a past entry breaks every hash after it, so it can&apos;t go
          unnoticed by anyone who saved an earlier chain head. How it works:{" "}
          <a className="text-electric underline" href="https://github.com/adeyanjufuhad/Sova/blob/main/docs/ledger.md">
            the ledger
          </a>{" "}
          and{" "}
          <a className="text-electric underline" href="https://github.com/adeyanjufuhad/Sova/blob/main/docs/fair-draw.md">
            the fair draw
          </a>
          .
        </p>
      </main>
    </div>
  );
}
