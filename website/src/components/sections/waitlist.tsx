"use client";

import { useState } from "react";
import { ArrowRight, CheckCircle2, Loader2 } from "lucide-react";
import { DownloadButton } from "@/components/ui/download-button";
import { Reveal } from "@/components/ui/reveal";
import { cn } from "@/lib/utils";

const roles = [
  { value: "member", label: "I'm in an ajo" },
  { value: "admin", label: "I run a circle" },
  { value: "collector", label: "I'm a collector" },
] as const;

type Status = { kind: "idle" } | { kind: "loading" } | { kind: "done" } | { kind: "error"; message: string };

const inputCls =
  "w-full rounded-xl border border-navy-900/15 bg-white px-4 py-3 text-navy-900 placeholder:text-slate-400 outline-none transition focus:border-electric focus:ring-2 focus:ring-electric/20";

export function Waitlist() {
  const [role, setRole] = useState<(typeof roles)[number]["value"]>("member");
  const [status, setStatus] = useState<Status>({ kind: "idle" });

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    setStatus({ kind: "loading" });
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...Object.fromEntries(form), role }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || "Something went wrong. Please try again.");
      setStatus({ kind: "done" });
    } catch (err) {
      setStatus({ kind: "error", message: err instanceof Error ? err.message : "Something went wrong." });
    }
  }

  return (
    <section id="waitlist" className="scroll-mt-24 px-4 py-24 sm:py-32">
      <div className="relative mx-auto grid max-w-6xl items-center gap-12 overflow-hidden rounded-[2rem] bg-gradient-to-br from-electric via-[#1a44c2] to-navy-800 p-6 sm:p-12 lg:grid-cols-[1fr_1.1fr] lg:p-16">
        <div className="bg-grid-light pointer-events-none absolute inset-0 [mask-image:radial-gradient(ellipse_at_top_left,black,transparent_70%)]" />
        <div className="pointer-events-none absolute -right-24 -top-24 size-[420px] rounded-full bg-sky/40 blur-[120px]" />
        <Reveal className="relative">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky-300">Early access</p>
          <h2 className="mt-4 font-display text-4xl font-semibold tracking-tight text-balance text-white sm:text-6xl">
            Be first when Sova <span className="text-sky-300">goes live.</span>
          </h2>
          <p className="mt-5 max-w-md text-lg text-white/80">
            We&apos;re opening Sova to a small group of traders, circles and collectors first. Join the list and
            we&apos;ll text you when it&apos;s your turn.
          </p>
          <div className="mt-8">
            <DownloadButton tone="blue" />
          </div>
        </Reveal>

        <Reveal delay={0.1} className="relative">
          <div className="relative rounded-3xl bg-white p-6 shadow-[0_30px_60px_-30px_rgba(5,11,24,0.6)] sm:p-8">
            {status.kind === "done" ? (
              <div className="flex flex-col items-center py-10 text-center">
                <CheckCircle2 className="size-14 text-electric" />
                <p className="mt-5 font-display text-2xl font-semibold text-navy-900">You&apos;re on the list.</p>
                <p className="mt-2 max-w-sm text-slate-600">
                  Thank you! We&apos;ll send you an SMS as soon as Sova is ready for you.
                </p>
              </div>
            ) : (
              <form onSubmit={onSubmit} className="space-y-4">
                <fieldset>
                  <legend className="mb-2 text-sm text-slate-600">Which one describes you?</legend>
                  <div className="grid grid-cols-3 gap-2">
                    {roles.map((r) => (
                      <button
                        key={r.value}
                        type="button"
                        onClick={() => setRole(r.value)}
                        aria-pressed={role === r.value}
                        className={cn(
                          "rounded-xl border px-2 py-3 text-xs transition sm:text-sm",
                          role === r.value
                            ? "border-electric bg-electric/10 font-medium text-electric"
                            : "border-navy-900/15 text-slate-600 hover:border-electric/40 hover:text-navy-900",
                        )}
                      >
                        {r.label}
                      </button>
                    ))}
                  </div>
                </fieldset>

                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="block">
                    <span className="mb-1.5 block text-sm text-slate-600">Full name</span>
                    <input name="name" required maxLength={80} autoComplete="name" placeholder="Adaeze Okafor" className={inputCls} />
                  </label>
                  <label className="block">
                    <span className="mb-1.5 block text-sm text-slate-600">Phone number</span>
                    <input
                      name="phone"
                      required
                      type="tel"
                      inputMode="tel"
                      autoComplete="tel"
                      placeholder="0803 000 0000"
                      className={inputCls}
                    />
                  </label>
                  <label className="block">
                    <span className="mb-1.5 block text-sm text-slate-600">City or market</span>
                    <input name="city" maxLength={80} placeholder="Balogun, Lagos" className={inputCls} />
                  </label>
                  <label className="block">
                    <span className="mb-1.5 block text-sm text-slate-600">
                      {role === "collector" ? "Traders you collect from" : "People in your circle"}
                    </span>
                    <input name="group_size" type="number" min={1} max={5000} placeholder="12" className={inputCls} />
                  </label>
                </div>

                {/* honeypot for bots */}
                <input type="text" name="website" tabIndex={-1} autoComplete="off" className="hidden" aria-hidden />

                {status.kind === "error" && (
                  <p role="alert" className="rounded-xl border border-electric/20 bg-electric/5 px-4 py-3 text-sm text-navy-900">
                    {status.message}
                  </p>
                )}

                <button
                  type="submit"
                  disabled={status.kind === "loading"}
                  className="group flex w-full items-center justify-center gap-2 rounded-xl bg-electric px-6 py-4 font-medium text-white transition hover:bg-electric-400 disabled:opacity-60"
                >
                  {status.kind === "loading" ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    <>
                      Join the waitlist
                      <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
                    </>
                  )}
                </button>
                <p className="text-center text-xs text-slate-500">
                  We&apos;ll only use your number to contact you about Sova.
                </p>
              </form>
            )}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
