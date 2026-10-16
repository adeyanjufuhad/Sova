"use client";

import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Anchor, ArrowRight, CircleCheck, CircleX, Dices, ExternalLink, Link2, Loader2, ShieldCheck } from "lucide-react";
import { callApi } from "@/lib/api";
import { site } from "@/lib/site";
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

type Checkpoint = { seq: number; hash: string; at: string };
/** The circle's published chain heads, each checked against this record. */
type AnchorCheck =
  | { state: "unreachable" }
  | { state: "none" }
  | { state: "checked"; checkpoints: (Checkpoint & { ok: boolean })[]; allOk: boolean };

type Result = { ledger: Ledger; entries: Checked[]; firstBroken: number | null; draw: DrawCheck; anchors: AnchorCheck };

const GENESIS = "0".repeat(64);

async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data as BufferSource);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const text = (s: string) => new TextEncoder().encode(s);
const hexBytes = (hex: string) => new Uint8Array(hex.match(/../g)!.map((h) => parseInt(h, 16)));

/**
 * Fetches the public anchors (docs/ledger.md, "Public anchors"). They live outside
 * Sova's servers, so failing to load them never blocks the rest of the check.
 */
async function loadAnchors(): Promise<Record<string, Checkpoint[]> | null> {
  try {
    const res = await fetch(site.anchorsUrl, { cache: "no-store" });
    if (res.status === 404) return {}; // nothing published yet
    if (!res.ok) return null;
    return ((await res.json()) as { circles?: Record<string, Checkpoint[]> }).circles ?? {};
  } catch {
    return null;
  }
}

/** A chain only grows, so every checkpoint must still be the hash at its seq. */
async function checkAnchors(circleId: string, entries: Entry[], published: Record<string, Checkpoint[]> | null): Promise<AnchorCheck> {
  if (!published) return { state: "unreachable" };
  const list = published[await sha256Hex(text(`sova-anchor|${circleId}`))];
  if (!list?.length) return { state: "none" };
  const checkpoints = list.map((c) => ({ ...c, ok: entries[c.seq - 1]?.hash === c.hash }));
  return { state: "checked", checkpoints, allOk: checkpoints.every((c) => c.ok) };
}

/** Recomputes every hash and the fair draw, entirely in this browser. */
async function check(ledger: Ledger, published: Record<string, Checkpoint[]> | null): Promise<Result> {
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
  return { ledger, entries, firstBroken, draw, anchors: await checkAnchors(ledger.circle.id, ledger.entries, published) };
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
    case "member_left":
      return `${who(d.member)} left before the turns were drawn`;
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
      return d.decidedBy === "dispute"
        ? `${who(d.payer)}'s ${naira(d.amount)} for turn ${d.turn} confirmed by the dispute's outcome`
        : `${who(d.collector)} confirmed ${who(d.payer)}'s ${naira(d.amount)} arrived`;
    case "payout_confirmed":
      return Number(d.shortfall) > 0
        ? `${who(d.collector)} received ${naira(d.received)} of ${naira(d.expected)} for turn ${d.turn}: ${naira(d.shortfall)} short`
        : `${who(d.collector)} received the full ${naira(d.received)} for turn ${d.turn}`;
    case "dispute_opened":
      return d.kind === "payment"
        ? `${who(d.raisedBy)} disputed ${who(d.payer)}'s turn ${d.turn} payment: ${d.reason}`
        : `Dispute opened: ${d.reason}`;
    case "dispute_vote":
      return `${who(d.voter)} voted that the turn ${d.turn} payment ${d.side === "payer" ? "arrived" : "did not arrive"}`;
    case "turns_swapped": {
      const a = d.a as Person & { turn: number };
      const b = d.b as Person & { turn: number };
      return `${who(a)} and ${who(b)} swapped turns by agreement: ${who(a)} now collects turn ${a.turn}, ${who(b)} turn ${b.turn}`;
    }
    case "slot_handed_over":
      return `${who(d.leaving)} handed their place (turn ${d.turn}) to ${who(d.replacement)}, approved by the admin`;
    case "dispute_resolved":
      return `Turn ${d.turn} dispute closed: ${d.note}`;
    case "circle_completed":
      return "Circle completed: every turn paid out";
    case "circle_cancelled":
      return `${who(d.by)} cancelled the circle before it started`;
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

const day = (iso: string) =>
  new Date(iso).toLocaleString("en-NG", { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" });

function AnchorCard({ anchors }: { anchors: AnchorCheck }) {
  const title =
    anchors.state === "checked"
      ? anchors.allOk
        ? "Public anchors: every checkpoint matches"
        : "Public anchors: a checkpoint doesn't match"
      : anchors.state === "none"
        ? "Public anchors: not published yet"
        : "Public anchors: couldn't be loaded";
  const shown = anchors.state === "checked" ? anchors.checkpoints.slice(-5).reverse() : [];
  return (
    <div className="rounded-3xl border border-navy-900/10 bg-white p-6 sm:p-8">
      <div className="flex items-center gap-3">
        <Anchor className="size-6 shrink-0 text-electric" />
        <h2 className="font-display text-xl font-bold text-navy-900">{title}</h2>
      </div>
      <p className="mt-3 text-sm text-slate-600">
        Every 6 hours Sova publishes each circle&apos;s chain head to a public GitHub branch, outside its own database.
        A record can only grow, so each earlier checkpoint must still match.
        {anchors.state === "none" && " This circle has no checkpoint yet; it gets one at the next run."}
        {anchors.state === "unreachable" && " The anchor file couldn't be downloaded just now; the checks above don't depend on it."}
      </p>
      {anchors.state === "checked" && (
        <ul className="mt-5 space-y-3">
          {shown.map((c) => (
            <Tick
              key={`${c.seq}-${c.at}`}
              ok={c.ok}
              label={`${day(c.at)}: entry #${c.seq} ${c.ok ? "matches" : "has a different hash now"} (${c.hash.slice(0, 12)}…)`}
            />
          ))}
          {anchors.checkpoints.length > shown.length && (
            <li className="pl-8 text-sm text-slate-500">
              and {anchors.checkpoints.length - shown.length} earlier checkpoint(s), {anchors.checkpoints.slice(0, -shown.length).every((c) => c.ok) ? "all matching" : "not all matching"}
            </li>
          )}
        </ul>
      )}
      <a
        href={site.anchorsHistoryUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-5 inline-flex items-center gap-1.5 text-sm font-medium text-electric hover:underline"
      >
        When each anchor was published <ExternalLink className="size-3.5" />
      </a>
    </div>
  );
}

function Picker({ onPick }: { onPick: (id: string) => void }) {
  const [value, setValue] = useState("");
  // null while loading; an empty list if they couldn't be fetched.
  const [demos, setDemos] = useState<{ id: string; name: string }[] | null>(null);
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
        <label className="flex min-w-0 flex-1 items-center gap-3 rounded-xl border border-navy-900/15 px-4 focus-within:border-electric focus-within:ring-2 focus-within:ring-electric/20">
          <Link2 className="size-4 shrink-0 text-slate-400" />
          <input
            name="circle"
            aria-label="Circle verify link or id"
            autoComplete="off"
            spellCheck={false}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="Paste a circle's verify link or id…"
            className="w-full min-w-0 py-3 text-navy-900 outline-none placeholder:text-slate-400"
          />
        </label>
        <button type="submit" className="inline-flex items-center justify-center gap-2 rounded-xl bg-electric px-6 py-3 font-semibold text-white transition hover:bg-electric-400 active:scale-[0.98]">
          Verify <ArrowRight className="size-4" />
        </button>
      </form>
      <p className="mt-6 text-sm text-slate-500">Or check one of the demo circles:</p>
      <div aria-live="polite" className="mt-3 flex flex-wrap gap-2">
        {demos === null && <span className="text-sm text-slate-400">Loading demo circles…</span>}
        {demos?.length === 0 && (
          <span className="text-sm text-slate-500">
            The demo circles couldn&apos;t be loaded. Paste a circle&apos;s link above, or reload the page to try again.
          </span>
        )}
        {demos?.map((c) => (
          <button
            key={c.id}
            type="button"
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
  const id = params.get("c");
  // Settled results, tagged with the circle they belong to; anything else is still loading.
  const [state, setState] = useState<{ id: string; result?: Result; error?: string } | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    Promise.all([callApi(`/public/circles/${id}/ledger`) as Promise<Ledger>, loadAnchors()])
      .then(([ledger, published]) => check(ledger, published))
      .then((result) => !cancelled && setState({ id, result }))
      .catch((err) => !cancelled && setState({ id, error: err instanceof Error ? err.message : "Something went wrong." }));
    return () => {
      cancelled = true;
    };
  }, [id]);

  // A full page load on purpose: on the static host, client-side transitions to /verify/ failed.
  // eslint-disable-next-line @next/next/no-location-assign-relative-destination
  const pick = (c: string) => window.location.assign(`/verify/?c=${c}`);
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

  const { ledger, entries, firstBroken, draw, anchors } = state.result;
  const changedSincePublished = anchors.state === "checked" && !anchors.allOk;
  const intact = firstBroken === null && !changedSincePublished;
  const head = entries[entries.length - 1];
  const drawOk = draw ? draw.commitmentOk && draw.orderOk && draw.sealedFirst : null;

  return (
    <div className="space-y-6">
      <div className={cn("rounded-3xl p-6 sm:p-8", intact ? "bg-electric text-white" : "border-2 border-navy-900 bg-white text-navy-900")}>
        <div className="flex items-center gap-3">
          {intact ? <ShieldCheck className="size-8 shrink-0" /> : <CircleX className="size-8 shrink-0" />}
          <p className="font-display text-2xl font-bold sm:text-3xl">
            {intact ? "Record intact" : firstBroken !== null ? `Entry ${firstBroken} doesn't match` : "Changed after it was published"}
          </p>
        </div>
        <p className={cn("mt-3", intact ? "text-white/85" : "text-slate-600")}>
          {ledger.circle.name} · {entries.length} entries checked in your browser
          {intact
            ? ". Every hash links to the one before it."
            : firstBroken !== null
              ? ". Everything from this entry on can't be trusted."
              : ". The hashes link up, but they no longer match a chain head published earlier (see below)."}
        </p>
        {head && (
          <p className={cn("mt-4 break-all font-mono text-xs", intact ? "text-white/70" : "text-slate-500")}>
            Chain head #{head.seq}: {head.hash}
          </p>
        )}
      </div>

      <AnchorCard anchors={anchors} />

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
                <span className="grid size-6 shrink-0 place-items-center rounded-full bg-electric/10 text-xs font-semibold text-electric tabular-nums">{i + 1}</span>
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
