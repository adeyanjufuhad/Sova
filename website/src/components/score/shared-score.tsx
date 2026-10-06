"use client";

import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { BadgeCheck, Link2Off, Loader2 } from "lucide-react";
import { AdirePattern } from "@/components/ui/adire";
import { ApiError, callApi } from "@/lib/api";

interface SharedCard {
  displayName: string;
  score: number;
  band: string;
  onTimeRate: number;
  consistencyRate: number;
  completionRate: number;
  confirmedPayments: number;
  completedCircles: number;
  activeCircles: number;
  memberSince: string;
  sharedAt: string;
}

const pct = (n: number) => `${Math.round(n * 100)}%`;
const date = (s: string) =>
  new Intl.DateTimeFormat("en-NG", { day: "numeric", month: "long", year: "numeric" }).format(new Date(s));

function Part({ label, weight, value }: { label: string; weight: number; value: number }) {
  return (
    <div>
      <div className="flex items-baseline justify-between gap-3 text-sm">
        <span className="font-semibold text-navy-900">{label}</span>
        <span className="text-slate-500 tabular-nums">
          <span className="font-semibold text-navy-900">{pct(value)}</span> · {weight}% of score
        </span>
      </div>
      <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-electric/10">
        <div className="h-full rounded-full bg-electric" style={{ width: pct(Math.min(1, Math.max(0, value))) }} />
      </div>
    </div>
  );
}

/** Loads a shared score by its link token and shows the card as Sova checked it. */
export function SharedScore() {
  const token = useSearchParams().get("t");
  const [state, setState] = useState<{ token: string; card?: SharedCard; error?: string; gone?: boolean } | null>(null);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    callApi(`/public/scores/${encodeURIComponent(token)}`)
      .then((card: SharedCard) => !cancelled && setState({ token, card }))
      .catch(
        (err) =>
          !cancelled &&
          setState({
            token,
            gone: err instanceof ApiError && (err.status === 404 || err.status === 400),
            error: err instanceof Error ? err.message : "Something went wrong.",
          }),
      );
    return () => {
      cancelled = true;
    };
  }, [token]);

  if (!token || state?.gone) {
    return (
      <div className="rounded-3xl border border-navy-900/10 bg-white p-8 text-center">
        <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-electric/10 text-electric">
          <Link2Off aria-hidden className="size-6" />
        </span>
        <p className="mt-5 font-display text-xl font-bold text-navy-900">This link isn&apos;t active</p>
        <p className="mx-auto mt-2 max-w-sm text-slate-600">
          The member may have stopped sharing or made a new link. Ask them to send you their current link.
        </p>
      </div>
    );
  }

  const current = state?.token === token ? state : null;
  if (!current) {
    return (
      <p aria-live="polite" className="flex items-center justify-center gap-2 py-16 text-slate-500">
        <Loader2 aria-hidden className="size-4 animate-spin" /> Checking the score with Sova…
      </p>
    );
  }
  if (current.error || !current.card) {
    return (
      <p role="alert" className="rounded-2xl border border-electric/20 bg-electric/5 px-5 py-4 text-navy-900">
        {current.error}
      </p>
    );
  }

  const c = current.card;
  return (
    <div className="space-y-4">
      <div className="relative overflow-hidden rounded-3xl bg-electric p-6 text-white sm:p-8">
        <AdirePattern id="score-adire" className="text-white/10" />
        <div className="relative flex items-start justify-between gap-6">
          <div>
            <p className="text-sm font-semibold text-sky-300">Sova Score</p>
            <p className="mt-2 font-display text-3xl font-extrabold tracking-[-0.02em]">{c.displayName}</p>
            <p className="mt-1 text-sm text-white/75">Saving with Sova since {date(c.memberSince)}</p>
          </div>
          <div className="text-right">
            <p className="font-display text-6xl font-extrabold leading-none tracking-[-0.03em] tabular-nums sm:text-7xl">
              {c.score}
            </p>
            <p className="mt-1 text-sm text-white/75">
              out of 100 · <span className="font-semibold text-white">{c.band}</span>
            </p>
          </div>
        </div>
        <dl className="relative mt-8 grid grid-cols-3 gap-4 border-t border-white/20 pt-5 text-sm">
          <div>
            <dt className="text-white/70">Paid on time</dt>
            <dd className="mt-0.5 text-lg font-bold tabular-nums">{pct(c.onTimeRate)}</dd>
          </div>
          <div>
            <dt className="text-white/70">Payments</dt>
            <dd className="mt-0.5 text-lg font-bold tabular-nums">{c.confirmedPayments}</dd>
          </div>
          <div>
            <dt className="text-white/70">Circles finished</dt>
            <dd className="mt-0.5 text-lg font-bold tabular-nums">{c.completedCircles}</dd>
          </div>
        </dl>
      </div>

      <p className="flex items-start gap-2 rounded-2xl border border-navy-900/10 bg-white px-5 py-4 text-sm text-navy-800">
        <BadgeCheck aria-hidden className="mt-0.5 size-4 shrink-0 text-electric" />
        Checked by Sova: this card comes straight from the member&apos;s confirmed payments, as they stood on{" "}
        {date(c.sharedAt)}. Payments only count once both the payer and the collector confirmed them.
      </p>

      <div className="space-y-4 rounded-3xl border border-navy-900/10 bg-white p-6 sm:p-8">
        <p className="font-display text-lg font-bold text-navy-900">How the score is made</p>
        <Part label="Paid on time" weight={60} value={c.onTimeRate} />
        <Part label="Paid every turn" weight={25} value={c.consistencyRate} />
        <Part label="Circles finished" weight={15} value={c.completionRate} />
        <p className="text-sm text-slate-600">
          {c.activeCircles} circle{c.activeCircles === 1 ? "" : "s"} still running. Turns that aren&apos;t due yet
          don&apos;t count.
        </p>
      </div>
    </div>
  );
}
