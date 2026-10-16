// Publishes every circle's chain head outside Sova's database (docs/ledger.md,
// "Public anchors"). Run by .github/workflows/ledger-anchors.yml:
//
//   node .github/scripts/anchor-ledgers.mjs <path to anchors.json>
//
// It reads GET /public/chain-heads from the API and appends a checkpoint for
// every circle whose head changed since the last run. Checkpoints are only
// ever added, never replaced, so each one keeps the git timestamp it was
// published with. No dependencies: plain Node 22.
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const ABOUT =
  "Chain heads of Sova circle ledgers, published outside Sova's database so later changes to a record are visible. " +
  "Checkpoints are appended, never replaced; git history shows when each one was published.";

export const KEY_RULE = 'key = SHA-256("sova-anchor|" + circle id), hex';

export const CHECK_RULE =
  "For every checkpoint of a circle, ledger entry number `seq` must have hash `hash`. " +
  "A chain only grows, so a checkpoint that no longer matches means the record changed after it was published.";

const README = `# Sova ledger anchors

This branch is written by a scheduled GitHub Actions job (\`.github/workflows/ledger-anchors.yml\` on \`main\`).
Every few hours it reads the chain head of every Sova circle's tamper-evident ledger and appends it to
\`anchors.json\`. Checkpoints are only ever added, never replaced, and every change is a commit, so git
history shows when each checkpoint was published.

Circles appear under a key, not their id: \`${KEY_RULE}\`. Only someone who already has a circle's verify link
can find its checkpoints. The website's verify page (\`/verify/?c=<circle id>\`) checks the chain against them.

How the ledger works: https://github.com/adeyanjufuhad/Sova/blob/main/docs/ledger.md
`;

const empty = () => ({ about: ABOUT, keyRule: KEY_RULE, checkRule: CHECK_RULE, circles: {} });

/**
 * Appends a checkpoint for every head that differs from that circle's latest one.
 * Returns the new file, how many checkpoints were added, and circles whose head
 * went backwards or changed at the same seq (worth a warning: the verify page
 * will flag them).
 */
export function mergeAnchors(file, heads, at) {
  const next = { ...empty(), circles: { ...(file?.circles ?? {}) } };
  let added = 0;
  const suspicious = [];
  for (const { key, seq, hash } of heads) {
    const list = next.circles[key] ?? [];
    const last = list[list.length - 1];
    if (last && last.seq === seq && last.hash === hash) continue;
    if (last && (seq < last.seq || (seq === last.seq && hash !== last.hash))) suspicious.push(key);
    next.circles[key] = [...list, { seq, hash, at }];
    added++;
  }
  // Stable order keeps diffs small.
  next.circles = Object.fromEntries(Object.entries(next.circles).sort(([a], [b]) => (a < b ? -1 : 1)));
  return { file: next, added, suspicious };
}

/** The API sleeps when idle and answers with an HTML waking page first; keep asking until it answers in JSON. */
async function fetchHeads(apiUrl, attempts = 12) {
  for (let i = 1; ; i++) {
    try {
      const res = await fetch(`${apiUrl}/public/chain-heads`);
      if (res.ok && res.headers.get("content-type")?.includes("json")) {
        const data = await res.json();
        if (Array.isArray(data.heads)) return data;
      }
    } catch {
      // waking up or unreachable: retry below
    }
    if (i >= attempts) throw new Error(`No chain heads from ${apiUrl} after ${attempts} attempts.`);
    await new Promise((r) => setTimeout(r, 10_000));
  }
}

async function main() {
  const path = process.argv[2];
  if (!path) throw new Error("Usage: node anchor-ledgers.mjs <anchors.json>");
  const apiUrl = (process.env.SOVA_API_URL || "https://sova-api.rumptycloud.app").replace(/\/$/, "");

  const current = await readFile(path, "utf8").then(JSON.parse, () => null);
  const { heads, at } = await fetchHeads(apiUrl);
  const { file, added, suspicious } = mergeAnchors(current, heads, at);
  for (const key of suspicious) console.log(`::warning::Circle ${key.slice(0, 12)}… has a head that does not extend its last checkpoint.`);

  await writeFile(path, `${JSON.stringify(file, null, 2)}\n`);
  await writeFile(new URL("README.md", pathToFileURL(path)), README);
  console.log(`${heads.length} circles, ${added} new checkpoint(s).`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
