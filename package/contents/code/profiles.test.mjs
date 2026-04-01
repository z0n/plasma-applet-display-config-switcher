import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mergeProfiles } from "./profiles.mjs";

describe("mergeProfiles", () => {
  it("returns empty array when both inputs are empty", () => {
    assert.deepEqual(mergeProfiles([], []), []);
  });

  it("returns local profiles when shared is empty", () => {
    const local = [{ name: "A" }, { name: "B" }];
    assert.deepEqual(mergeProfiles([], local), [{ name: "A" }, { name: "B" }]);
  });

  it("returns shared profiles when local is empty", () => {
    const shared = [{ name: "A" }, { name: "B" }];
    assert.deepEqual(mergeProfiles(shared, []), [
      { name: "A" },
      { name: "B" },
    ]);
  });

  it("merges unique profiles from both", () => {
    const shared = [{ name: "A" }];
    const local = [{ name: "B" }];
    assert.deepEqual(mergeProfiles(shared, local), [
      { name: "A" },
      { name: "B" },
    ]);
  });

  it("deduplicates by name, keeping shared version", () => {
    const shared = [{ name: "Monitor", outputs: "shared-data" }];
    const local = [{ name: "Monitor", outputs: "local-data" }];
    const result = mergeProfiles(shared, local);
    assert.equal(result.length, 1);
    assert.equal(result[0].outputs, "shared-data");
  });

  it("handles partial overlap — appends unique locals after shared", () => {
    const shared = [{ name: "A" }, { name: "B" }];
    const local = [{ name: "B" }, { name: "C" }];
    const result = mergeProfiles(shared, local);
    assert.equal(result.length, 3);
    assert.deepEqual(
      result.map((p) => p.name),
      ["A", "B", "C"]
    );
  });

  it("returns identical result when both have same profiles", () => {
    const shared = [{ name: "A" }, { name: "B" }];
    const local = [{ name: "A" }, { name: "B" }];
    const result = mergeProfiles(shared, local);
    assert.equal(result.length, 2);
  });

  it("handles profile names with single quotes", () => {
    const shared = [{ name: "Bob's Monitor" }];
    const local = [{ name: "Alice's TV" }];
    const result = mergeProfiles(shared, local);
    assert.equal(result.length, 2);
    assert.equal(result[0].name, "Bob's Monitor");
    assert.equal(result[1].name, "Alice's TV");
  });

  it("does not mutate the shared input array", () => {
    const shared = [{ name: "A" }];
    const sharedCopy = [...shared];
    mergeProfiles(shared, [{ name: "B" }]);
    assert.deepEqual(shared, sharedCopy);
  });

  it("does not mutate the local input array", () => {
    const local = [{ name: "A" }];
    const localCopy = [...local];
    mergeProfiles([{ name: "B" }], local);
    assert.deepEqual(local, localCopy);
  });
});
