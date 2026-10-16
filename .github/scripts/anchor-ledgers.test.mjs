// node --test .github/scripts/anchor-ledgers.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";

import { mergeAnchors } from "./anchor-ledgers.mjs";

const h = (c) => c.repeat(64);

test("adds a first checkpoint for every circle", () => {
  const { file, added } = mergeAnchors(null, [{ key: "b", seq: 3, hash: h("1") }, { key: "a", seq: 9, hash: h("2") }], "T1");
  assert.equal(added, 2);
  assert.deepEqual(Object.keys(file.circles), ["a", "b"]);
  assert.deepEqual(file.circles.b, [{ seq: 3, hash: h("1"), at: "T1" }]);
});

test("appends only when a head moved, and never replaces old checkpoints", () => {
  const first = mergeAnchors(null, [{ key: "a", seq: 3, hash: h("1") }, { key: "b", seq: 5, hash: h("2") }], "T1").file;
  const { file, added, suspicious } = mergeAnchors(first, [{ key: "a", seq: 4, hash: h("3") }, { key: "b", seq: 5, hash: h("2") }], "T2");
  assert.equal(added, 1);
  assert.deepEqual(suspicious, []);
  assert.deepEqual(file.circles.a, [
    { seq: 3, hash: h("1"), at: "T1" },
    { seq: 4, hash: h("3"), at: "T2" },
  ]);
  assert.equal(file.circles.b.length, 1);
});

test("keeps circles that are no longer listed", () => {
  const first = mergeAnchors(null, [{ key: "gone", seq: 2, hash: h("1") }], "T1").file;
  assert.ok(mergeAnchors(first, [], "T2").file.circles.gone);
});

test("flags a head that went backwards or changed in place, and still records it", () => {
  const first = mergeAnchors(null, [{ key: "a", seq: 6, hash: h("1") }, { key: "b", seq: 6, hash: h("2") }], "T1").file;
  const { file, suspicious } = mergeAnchors(first, [{ key: "a", seq: 4, hash: h("3") }, { key: "b", seq: 6, hash: h("4") }], "T2");
  assert.deepEqual(suspicious, ["a", "b"]);
  assert.equal(file.circles.a.length, 2);
});
