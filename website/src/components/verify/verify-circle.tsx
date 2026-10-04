"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowRight, CircleCheck, CircleX, Dices, Link2, Loader2, ShieldCheck } from "lucide-react";
import { callApi } from "@/lib/api";
import { cn } from "@/lib/utils";

type Entry = { seq: number; kind: string; body: string; prevHash: string; hash: string };
type Ledger = { circle: { id: string; name: string; status: string; memberCount: number }; entries: Entry[] };
type Person = { id: string; name: string };
type Checked = Entry & { data: Record<string, unknown>; ok: boolean };

type DrawCheck = {
  commitment: string;
  seed: string;
  commitmentOk: boolean;
  orderOk: boolean;
  sealedFirst: boolean;
  order: (Person & { key: string })[];
  adminLast: boolean;
} | null;

type Result = { ledger: Ledger; entries: Checked[]; firstBroken: number | null; draw: DrawCheck };

const GENESIS = "0".repeat(64);

async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data as BufferSource);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const text = (s: string) => new TextEncoder().encode(s);
const hexBytes = (hex: string) => new Uint8Array(hex.match(/../g)!.map((h) => parseInt(h, 16)));

/** Recomputes every hash and the fair draw, entirely in this browser. */
async function check(ledger: Ledger): Promise<Result> {
  let prev = GENESIS;
  let firstBroken: number | null = null;
  const entries: Checked[] = [];
  for (const [i, e] of ledger.entries.entries()) {
    const hash = await sha256Hex(text(`${prev}|${e.seq}|${e.kind}|${e.body}`));
    const ok = firstBroken === null && e.seq === i + 1 && e.prevHash === prev && hash === e.hash;
    if (!ok && firstBroken === null) firstBroken = e.seq;
    entries.push({ ...e, data: JSON.parse(e.body), ok });
    prev = e.hash;
  }

  const find = (kind: string) => entries.find((e) => e.kind === kind);
  const created = find("circle_created");
  const committed = find("draw_committed");
  const revealed = find("draw_revealed");
  let draw: DrawCheck = null;
  if (committed && revealed && created) {
    const seed = revealed.data.seed as string;
    const order = revealed.data.order as Person[];
    const adminId = (created.data.admin as Person).id;
    const adminLast = Boolean(created.data.adminCollectsLast);
    const keyed = await Promise.all(order.map(async (m) => ({ ...m, key: await sha256Hex(text(`${seed}:${m.id}`)) })));
    const expected = [...keyed].sort(
      (a, b) =>
        Number(adminLast && a.id === adminId) - Number(adminLast && b.id === adminId) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0),
    );
    draw = {
      commitment: committed.data.commitment as string,
      seed,
      commitmentOk: (await sha256Hex(hexBytes(seed))) === committed.data.commitment,
      orderOk: expected.every((m, i) => m.id === order[i]!.id),
      sealedFirst: entries.filter((e) => e.kind === "member_joined").every((e) => e.seq > committed.seq),
      order: keyed,
      adminLast,
    };
  }
  return { ledger, entries, firstBroken, draw };
}

const naira = (n: unknown) => `₦${Number(n).toLocaleString("en-NG")}`;
const who = (p: unknown) => (p as Person | undefined)?.name ?? "Someone";

function describe(e: Checked): string {
  const d = e.data;
  switch (e.kind) {
    case "circle_created":
      return `${who(d.admin)} created ${d.name}: ${naira(d.contribution)} ${d.cycle}, ${d.members} members${d.adminCollectsLast ? ", admin pledged to collect last" : ""}`;
    case "draw_committed":
      return `Payout draw sealed: commitment ${String(d.commitment).slice(0, 12)}…`;
    case "rules_published":
      return `Rules version ${d.version} published (late fee ${naira(d.lateFee)}, ${d.graceDays} day(s) grace)`;
    case "member_joined":
      return `${who(d.member)} joined`;
    case "member_vouched":
      return `${who(d.voucher)} vouched for ${who(d.member)}`;
    case "rules_accepted":
      return `${who(d.member)} accepted rules version ${d.version}`;
    case "draw_revealed":
      return `Draw revealed: ${(d.order as Person[]).map((m, i) => `${i + 1}. ${m.name}`).join(", ")}`;
    case "turn_opened":
      return `Turn ${d.turn} opened: ${who(d.collector)} collects, due ${d.due}`;
    case "payment_marked":
      return `${who(d.payer)} marked ${naira(d.amount)} as sent for turn ${d.turn}`;
    case "payment_confirmed":
      return `${who(d.collector)} confirmed ${who(d.payer)}'s ${naira(d.amount)} arrived`;
    case "payout_confirmed":
      return Number(d.shortfall) > 0
        ? `${who(d.collector)} received ${naira(d.received)} of ${naira(d.expected)} for turn ${d.turn}: ${naira(d.shortfall)} short`
        : `${who(d.collector)} received the full ${naira(d.received)} for turn ${d.turn}`;
    case "dispute_opened":
      return `Dispute opened: ${d.reason}`;
    case "circle_completed":
      return "Circle completed: every turn paid out";
    default:
      return e.kind;
  }
}

const when = (e: Checked) => {
  const at = e.data.at as string | undefined;
  return at ? new Date(at).toLocaleDateString("en-NG", { day: "numeric", month: "short", year: "numeric" }) : "";
};

function Tick({ ok, label }: { ok: boolean; label: string }) {
  return (
    <li className="flex items-start gap-3">
      {ok ? <CircleCheck className="mt-0.5 size-5 shrink-0 text-electric" /> : <CircleX className="mt-0.5 size-5 shrink-0 text-navy-900" />}
      <span className={cn("text-sm", ok ? "text-navy-800" : "font-semibold text-navy-900")}>{label}</span>
    </li>
  );
}

function Picker({ onPick }: { onPick: (id: string) => void }) {
  const [value, setValue] = useState("");
  const [demos, setDemos] = useState<{ id: string; name: string }[]>([]);
  useEffect(() => {
    callApi("/public/demo-circles")
      .then((d) => setDemos(d.circles))
      .catch(() => setDemos([]));
  }, []);
  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const id = value.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)?.[0];
    if (id) onPick(id.toLowerCase());
  };
  return (
    <div className="rounded-3xl border border-navy-900/10 bg-white p-6 sm:p-8">
      <form onSubmit={submit} className="flex flex-col gap-3 sm:flex-row">
        <label className="flex flex-1 items-center gap-3 rounded-xl border border-navy-900/15 px-4 focus-within:border-electric">
          <Link2 className="size-4 shrink-0 text-slate-400" />
          <input
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="Paste a circle's verify link or id"
            className="w-full py-3 text-navy-900 outline-none placeholder:text-slate-400"
          />
        </label>
        <button type="submit" className="inline-flex items-center justify-center gap-2 rounded-xl bg-electric px-6 py-3 font-semibold text-white hover:bg-electric-400">
          Verify <ArrowRight className="size-4" />
        </button>
      </form>
      <p className="mt-6 text-sm text-slate-500">Or check one of the demo circles:</p>
      <div className="mt-3 flex flex-wrap gap-2">
        {demos.length === 0 && <span className="text-sm text-slate-400">Loading demo circles…</span>}
        {demos.map((c) => (
          <button
            key={c.id}
            onClick={() => onPick(c.id)}
            className="rounded-full border border-navy-900/15 px-4 py-2 text-sm text-navy-800 hover:border-electric hover:text-electric"
          >
            {c.name}
          </button>
        ))}
      </div>
    </div>
  );
}

export function VerifyCircle() {
  const params = useSearchParams();
  const router = useRouter();
  const id = params.get("c");
  // Settled results, tagged with the circle they belong to; anything else is still loading.
  const [state, setState] = useState<{ id: string; result?: Result; error?: string } | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    callApi(`/public/circles/${id}/ledger`)
      .then((ledger: Ledger) => check(ledger))
      .then((result) => !cancelled && setState({ id, result }))
      .catch((err) => !cancelled && setState({ id, error: err instanceof Error ? err.message : "Something went wrong." }));
    return () => {
      cancelled = true;
    };
  }, [id]);

  const pick = (c: string) => router.push(`/verify/?c=${c}`);
  if (!id) return <Picker onPick={pick} />;
  if (state?.id !== id) {
    return (
      <div className="flex items-center gap-3 rounded-3xl border border-navy-900/10 bg-white p-8 text-slate-600">
        <Loader2 className="size-5 animate-spin text-electric" /> Downloading the record and checking every hash…
      </div>
    );
  }
  if (!state.result) {
    return (
      <div className="space-y-4">
        <div className="rounded-3xl border border-electric/20 bg-mist p-6 text-navy-900">{state.error}</div>
        <Picker onPick={pick} />
      </div>
    );
  }

  const { ledger, entries, firstBroken, draw } = state.result;
  const intact = firstBroken === null;
  const head = entries[entries.length - 1];
  const drawOk = draw ? draw.commitmentOk && draw.orderOk && draw.sealedFirst : null;

  return (
    <div className="space-y-6">
      <div className={cn("rounded-3xl p-6 sm:p-8", intact ? "bg-electric text-white" : "border-2 border-navy-900 bg-white text-navy-900")}>
        <div className="flex items-center gap-3">
          {intact ? <ShieldCheck className="size-8" /> : <CircleX className="size-8" />}
          <p className="font-display text-2xl font-bold sm:text-3xl">{intact ? "Record intact" : `Entry ${firstBroken} doesn't match`}</p>
        </div>
        <p className={cn("mt-3", intact ? "text-white/85" : "text-slate-600")}>
          {ledger.circle.name} · {entries.length} entries checked in your browser
          {intact ? ". Every hash links to the one before it." : ". Everything from this entry on can't be trusted."}
        </p>
        {head && (
          <p className={cn("mt-4 break-all font-mono text-xs", intact ? "text-white/70" : "text-slate-500")}>
            Chain head #{head.seq}: {head.hash}
          </p>
        )}
      </div>

      {draw && (
        <div className="rounded-3xl border border-navy-900/10 bg-white p-6 sm:p-8">
          <div className="flex items-center gap-3">
            <Dices className="size-6 text-electric" />
            <h2 className="font-display text-xl font-bold text-navy-900">
              Payout draw: {drawOk ? "fair and unchanged" : "does not check out"}
            </h2>
          </div>
          <ul className="mt-5 space-y-3">
            <Tick ok={draw.sealedFirst} label="The draw was sealed before anyone joined" />
            <Tick ok={draw.commitmentOk} label="The revealed seed matches the sealed commitment (SHA-256)" />
            <Tick ok={draw.orderOk} label={`Recomputing the order from the seed gives the same turns${draw.adminLast ? " (admin pledged to collect last)" : ""}`} />
          </ul>
          <ol className="mt-6 divide-y divide-navy-900/5 rounded-2xl border border-navy-900/10">
            {draw.order.map((m, i) => (
              <li key={m.id} className="flex items-center gap-3 px-4 py-2.5 text-sm">
                <span className="grid size-6 shrink-0 place-items-center rounded-full bg-electric/10 font-mono text-xs text-electric">{i + 1}</span>
                <span className="flex-1 text-navy-800">{m.name}</span>
                <span className="font-mono text-xs text-slate-400">{m.key.slice(0, 10)}…</span>
              </li>
            ))}
          </ol>
        </div>
      )}

      <div className="rounded-3xl border border-navy-900/10 bg-white">
        <h2 className="px-6 pt-6 font-display text-xl font-bold text-navy-900 sm:px-8">Everything on the record</h2>
        <ol className="mt-4 divide-y divide-navy-900/5">
          {entries.map((e) => (
            <li key={e.seq} className="flex gap-4 px-6 py-3.5 sm:px-8">
              <span className="w-8 shrink-0 pt-0.5 font-mono text-xs text-slate-400">#{e.seq}</span>
              <div className="min-w-0 flex-1">
                <p className="text-sm text-navy-900">{describe(e)}</p>
                <p className="mt-0.5 truncate font-mono text-[11px] text-slate-400">
                  {when(e)} · {e.hash.slice(0, 16)}…
                </p>
              </div>
              {e.ok ? (
                <CircleCheck className="size-4 shrink-0 text-electric" aria-label="Hash checks out" />
              ) : (
                <CircleX className="size-4 shrink-0 text-navy-900" aria-label="Hash does not match" />
              )}
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}
