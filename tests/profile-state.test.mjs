import assert from "node:assert/strict";
import test from "node:test";
import { createProfileState } from "../package/contents/code/profile-state.mjs";

const profile = name => ({name, outputs: [{name: "DP-1", enabled: true}], timestamp: "saved"});
const clone = value => JSON.parse(JSON.stringify(value));

function instance(shared, cached = []) {
    const pending = [];
    const seen = {profiles: null, cache: null, error: "", busy: false, publications: 0};
    const adapter = {
        read: done => pending.push({kind: "read", done}),
        write: (profiles, done) => pending.push({kind: "write", profiles: clone(profiles), done}),
        capture: done => pending.push({kind: "capture", done})
    };
    const state = createProfileState(adapter, typeof cached === "string" ? cached : JSON.stringify(cached), {
        publish(profiles, json) {
            seen.profiles = clone(profiles);
            seen.cache = json;
            seen.publications++;
        },
        error: error => { seen.error = error; },
        busy: busy => { seen.busy = busy; }
    });
    function complete(kind, result) {
        assert.equal(pending.length, 1, "only one adapter operation is in flight");
        const operation = pending.shift();
        assert.equal(operation.kind, kind);
        if (!result) {
            if (kind === "read")
                result = shared.text === undefined ? {status: "missing"} : {status: "ok", text: shared.text};
            else if (kind === "write") {
                shared.text = JSON.stringify(operation.profiles);
                result = {status: "ok"};
            } else
                result = {status: "ok", text: JSON.stringify({outputs: [{name: "HDMI-1", enabled: true}]})};
        }
        operation.done(result);
    }
    return {state, seen, pending, complete};
}

test("last deletion stays deleted when a stale second instance refreshes", () => {
    const initial = [profile("Desk")];
    const shared = {text: JSON.stringify(initial)};
    const a = instance(shared, initial);
    const b = instance(shared, initial);
    a.state.remove("Desk");
    a.complete("read");
    assert.deepEqual(a.seen.profiles, initial, "deletion is not optimistic");
    a.complete("write");
    b.state.refresh();
    b.complete("read");
    assert.equal(shared.text, "[]");
    assert.deepEqual(b.seen.profiles, []);
    assert.equal(b.seen.cache, "[]");
    assert.equal(b.pending.length, 0);
});

test("missing storage migrates the cache, including an empty cache", () => {
    for (const cached of [[], [profile("Desk")]]) {
        const shared = {};
        const a = instance(shared, cached);
        a.state.refresh();
        a.complete("read");
        a.complete("write");
        assert.equal(shared.text, JSON.stringify(cached));
        assert.equal(a.seen.busy, false);
    }
});

test("nonempty shared data replaces stale cache; unchanged refresh does not republish", () => {
    const current = [profile("TV")];
    const a = instance({text: JSON.stringify(current)}, [profile("Desk")]);
    a.state.refresh();
    a.complete("read");
    assert.deepEqual(a.seen.profiles, current);
    const count = a.seen.publications;
    a.state.refresh();
    a.complete("read");
    assert.equal(a.seen.publications, count);
    assert.equal(a.pending.length, 0);
});

test("malformed, empty-text, non-array and invalid-profile storage never seeds from cache", () => {
    for (const text of ["", "{", "null", "{}", "[null]", '[{"name":"Desk"}]']) {
        const shared = {text};
        const cached = [profile("Desk")];
        const a = instance(shared, cached);
        a.state.refresh();
        a.complete("read");
        assert.equal(a.seen.error, "invalid");
        assert.deepEqual(a.seen.profiles, cached);
        assert.equal(a.seen.cache, JSON.stringify(cached));
        assert.equal(shared.text, text);
        assert.equal(a.pending.length, 0);
    }
});

test("failed pre-edit reads preserve state and block writes, with a retry", () => {
    const cached = [profile("Desk")];
    const shared = {text: JSON.stringify(cached)};
    const a = instance(shared, cached);
    a.state.remove("Desk");
    a.complete("read", {status: "error"});
    assert.equal(a.seen.error, "read");
    assert.deepEqual(a.seen.profiles, cached);
    assert.equal(a.pending.length, 0);
    a.state.retry();
    a.complete("read");
    a.complete("write");
    assert.equal(a.seen.error, "");
    assert.deepEqual(a.seen.profiles, []);
});

test("failed writes preserve profiles and cache; retry re-reads other instances' edits", () => {
    const cached = [profile("Desk")];
    const shared = {text: JSON.stringify(cached)};
    const a = instance(shared, cached);
    a.state.remove("Desk");
    a.complete("read");
    a.complete("write", {status: "error"});
    assert.equal(a.seen.error, "write");
    assert.deepEqual(a.seen.profiles, cached);
    assert.equal(a.seen.cache, JSON.stringify(cached));
    shared.text = JSON.stringify([...cached, profile("TV")]);
    a.state.retry();
    a.complete("read");
    a.complete("write");
    assert.deepEqual(a.seen.profiles, [profile("TV")]);
});

test("deletion targets a name after reordering and absence is a no-op", () => {
    const shared = {text: JSON.stringify([profile("TV"), profile("Desk")])};
    const a = instance(shared, [profile("Desk"), profile("TV")]);
    a.state.remove("Desk");
    a.complete("read");
    a.complete("write");
    assert.deepEqual(a.seen.profiles, [profile("TV")]);
    a.state.remove("Desk");
    a.complete("read");
    assert.equal(a.pending.length, 0);
});

test("save captures raw outputs, preserves completed edits and replaces by name", () => {
    const shared = {text: JSON.stringify([profile("Desk"), profile("TV")])};
    const a = instance(shared, [profile("Desk")]);
    const outputs = [{name: "DP-9", currentModeId: "42", customFutureProperty: [1, 2]}];
    a.state.save("Desk");
    a.complete("capture", {status: "ok", text: JSON.stringify({outputs})});
    a.complete("read");
    a.complete("write");
    assert.deepEqual(a.seen.profiles.map(p => p.name), ["Desk", "TV"]);
    assert.deepEqual(a.seen.profiles[0].outputs, outputs);
    assert.ok(Number.isFinite(Date.parse(a.seen.profiles[0].timestamp)));
});

test("a delayed refresh finishes before queued captures and mutations", () => {
    const shared = {text: "[]"};
    const a = instance(shared);
    a.state.refresh();
    a.state.save("One");
    a.state.save("Two");
    a.state.remove("One");
    a.complete("read");
    for (let i = 0; i < 2; i++) {
        a.complete("capture");
        a.complete("read");
        a.complete("write");
    }
    a.complete("read");
    a.complete("write");
    assert.deepEqual(a.seen.profiles.map(p => p.name), ["Two"]);
    assert.equal(a.seen.busy, false);
});

test("failed capture stops before storage; retry captures again", () => {
    for (const result of [{status: "error"}, {status: "ok", text: "{}"}, {status: "ok", text: "{"}]) {
        const a = instance({text: "[]"});
        a.state.save("Desk");
        a.complete("capture", result);
        assert.equal(a.seen.error, "capture");
        assert.equal(a.pending.length, 0);
        a.state.retry();
        a.complete("capture");
        a.complete("read");
        a.complete("write");
        assert.equal(a.seen.profiles[0].name, "Desk");
    }
});

test("retry after failed save reuses the captured snapshot", () => {
    const a = instance({text: "[]"});
    a.state.save("Desk");
    a.complete("capture");
    a.complete("read");
    const attempted = clone(a.pending[0].profiles);
    a.complete("write", {status: "error"});
    a.state.retry();
    a.complete("read");
    a.complete("write");
    assert.deepEqual(a.seen.profiles, attempted);
});

test("a queued popup refresh cannot erase a failed edit's Retry action", () => {
    const a = instance({text: "[]"});
    a.state.save("Desk");
    a.state.refresh();
    a.complete("capture");
    a.complete("read");
    a.complete("write", {status: "error"});
    a.complete("read");
    assert.equal(a.seen.error, "write");
    a.state.retry();
    a.complete("read");
    a.complete("write");
    assert.equal(a.seen.error, "");
    assert.equal(a.seen.profiles[0].name, "Desk");
});

test("a successful refresh clears an earlier refresh error", () => {
    const a = instance({text: "[]"});
    a.state.refresh();
    a.complete("read", {status: "error"});
    a.state.refresh();
    a.complete("read");
    assert.equal(a.seen.error, "");
    a.state.retry();
    assert.equal(a.pending.length, 0);
});

test("simultaneous writers explicitly remain last-write-wins", () => {
    const shared = {text: "[]"};
    const a = instance(shared);
    const b = instance(shared);
    a.state.save("A");
    b.state.save("B");
    a.complete("capture");
    b.complete("capture");
    a.complete("read");
    b.complete("read");
    a.complete("write");
    b.complete("write");
    a.state.refresh();
    a.complete("read");
    assert.deepEqual(a.seen.profiles.map(p => p.name), ["B"]);
});
