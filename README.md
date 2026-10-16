# Sova ledger anchors

This branch is written by a scheduled GitHub Actions job (`.github/workflows/ledger-anchors.yml` on `main`).
Every few hours it reads the chain head of every Sova circle's tamper-evident ledger and appends it to
`anchors.json`. Checkpoints are only ever added, never replaced, and every change is a commit, so git
history shows when each checkpoint was published.

Circles appear under a key, not their id: `key = SHA-256("sova-anchor|" + circle id), hex`. Only someone who already has a circle's verify link
can find its checkpoints. The website's verify page (`/verify/?c=<circle id>`) checks the chain against them.

How the ledger works: https://github.com/adeyanjufuhad/Sova/blob/main/docs/ledger.md
