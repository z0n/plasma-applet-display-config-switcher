import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {prepareApplication, verifyApplication, createProfileApplication, applicationCommand,
    isEnabled, modeLabel} from "../package/contents/code/profile-application.mjs";

const mode = (id, refreshRate = 59.94, name = "1920x1080@60") => ({
    id, name, size: {width: 1920, height: 1080}, refreshRate
});
const output = (changes = {}) => ({name: "DP-1", connected: true, enabled: true,
    currentModeId: "saved", modes: [mode("saved")], pos: {x: 0, y: 0}, scale: 1,
    rotation: 1, ...changes});
const profile = (...outputs) => ({name: "Desk", outputs});
const config = (...outputs) => ({outputs});

test("missing enabled restores an active output without unsupported enable/disable commands", () => {
    const saved = output({enabled: undefined});
    const live = output({enabled: undefined, currentModeId: "live", modes: [mode("live")]});
    const plan = prepareApplication(profile(saved), config(live));
    assert.equal(isEnabled(saved), true);
    assert.deepEqual(plan.issues, []);
    assert.ok(plan.args.includes("output.DP-1.mode.live"));
    assert.ok(plan.args.includes("output.DP-1.position.0,0"));
    assert.equal(plan.args.some(arg => /\.(enable|disable)$/.test(arg)), false);
    assert.deepEqual(verifyApplication(plan.expected, config(live)), []);
});

test("explicit false disables, but unsupported disabling stops the whole plan", () => {
    const saved = output({enabled: false});
    assert.deepEqual(prepareApplication(profile(saved), config(output())).args, ["output.DP-1.disable"]);
    const plan = prepareApplication(profile(saved), config(output({enabled: undefined})));
    assert.deepEqual(plan.args, []);
    assert.deepEqual(plan.issues, ["DP-1: disable"]);
});

test("mode matching uses dimensions and precise refresh against live IDs, including empty X11 names", () => {
    const saved = output({modes: [mode("saved", 59.94, "")]});
    const live = output({currentModeId: "other", modes: [mode("other", 60), mode("new", 59.94)]});
    const plan = prepareApplication(profile(saved), config(live));
    assert.deepEqual(plan.issues, []);
    assert.ok(plan.args.includes("output.DP-1.mode.new"));
    assert.equal(modeLabel(saved), "1920x1080@60");
    assert.deepEqual(verifyApplication(plan.expected, config(live)), ["DP-1: mode"]);
    assert.deepEqual(verifyApplication(plan.expected, config({...live, currentModeId: "new"})), []);
});

test("legacy modes with names but no dimensions resolve only unambiguous live matches", () => {
    const saved = output({modes: [{id: "saved", name: "1920x1080@60"}]});
    const live = output({modes: [mode("new")]});
    assert.ok(prepareApplication(profile(saved), config(live)).args.includes("output.DP-1.mode.new"));
    live.modes.push(mode("ambiguous", 60));
    assert.deepEqual(prepareApplication(profile(saved), config(live)).issues, ["DP-1: mode"]);
});

test("unavailable modes never fall back to stale numeric IDs", () => {
    const saved = output();
    const live = output({modes: [mode("saved", 144)]});
    const plan = prepareApplication(profile(saved), config(live));
    assert.deepEqual(plan.args, []);
    assert.deepEqual(plan.issues, ["DP-1: mode"]);
});

test("zero overscan and all eight rotation values are restored", () => {
    for (const [rotation, argument] of [[1, "normal"], [2, "left"], [4, "inverted"], [8, "right"],
        [16, "flipped"], [32, "flipped90"], [64, "flipped180"], [128, "flipped270"]]) {
        const saved = output({rotation, overscan: 0});
        const plan = prepareApplication(profile(saved), config(output({overscan: 10})));
        assert.deepEqual(plan.issues, []);
        assert.ok(plan.args.includes("output.DP-1.overscan.0"));
        assert.ok(plan.args.includes("output.DP-1.rotation." + argument));
    }
});

test("existing HDR, VRR, scale, position, priority and brightness conversions are retained", () => {
    const saved = output({scale: 1.25, pos: {x: -1920, y: 0}, priority: 2,
        vrrPolicy: 2, hdr: false, wcg: true, "sdr-brightness": 200, brightness: 0.175});
    const plan = prepareApplication(profile(saved), config(saved));
    assert.deepEqual(plan.issues, []);
    for (const setting of ["scale.1.25", "position.-1920,0", "priority.2", "vrrpolicy.automatic",
        "hdr.disable", "wcg.enable", "sdr-brightness.200", "brightness.18"])
        assert.ok(plan.args.includes("output.DP-1." + setting), setting);
    assert.deepEqual(verifyApplication(plan.expected, config({...saved, brightness: 0.18})), []);
});

test("unsupported optional settings block application rather than being silently skipped", () => {
    const plan = prepareApplication(profile(output({brightness: 0.5})), config(output()));
    assert.deepEqual(plan.args, []);
    assert.deepEqual(plan.issues, ["DP-1: brightness"]);
});

test("a missing active connector blocks every output; absent disabled connectors are harmless", () => {
    const plan = prepareApplication(profile(output(), output({name: "HDMI-1"})), config(output()));
    assert.deepEqual(plan.args, []);
    assert.deepEqual(plan.issues, ["HDMI-1: disconnected"]);
    const disabled = output({name: "HDMI-1", enabled: false});
    assert.deepEqual(prepareApplication(profile(output(), disabled), config(output())).issues, []);
    assert.deepEqual(prepareApplication(profile(output()), config(output({connected: false}))).args, []);
});

test("verification reports settings that were ignored, even if the command succeeded", () => {
    const saved = output({overscan: 0, rotation: 16});
    const plan = prepareApplication(profile(saved), config(saved));
    assert.deepEqual(verifyApplication(plan.expected, config(output({overscan: 10}))),
        ["DP-1: rotation", "DP-1: overscan"]);
    assert.deepEqual(verifyApplication(plan.expected, config()), ["DP-1: disconnected"]);
});

test("the shell receives each output argument literally, including quotes and substitutions", () => {
    const args = ["output.DP-'$(printf injected);# .enable", "output.DP-1.scale.1.25"];
    const command = 'kscreen-doctor() { printf "%s\\n" "$@"; }; ' + applicationCommand(args);
    assert.equal(execFileSync("sh", ["-c", command], {encoding: "utf8"}), args.join("\n") + "\n");
});

function harness() {
    const pending = [];
    const events = [];
    const controller = createProfileApplication({
        capture: complete => pending.push({kind: "query", complete}),
        apply: (args, complete) => pending.push({kind: "apply", args, complete})
    }, {
        busy: value => events.push(["busy", value]),
        error: (code, details) => events.push(["error", code, details])
    });
    function query(value = config(output())) {
        const request = pending.shift();
        assert.equal(request.kind, "query");
        request.complete({status: "ok", text: JSON.stringify(value)});
    }
    return {controller, pending, events, query};
}

test("application queries, submits all outputs once, then verifies; repeated clicks cannot overlap", () => {
    const h = harness();
    const second = output({name: "HDMI-1", enabled: false});
    h.controller.apply(profile(output(), second));
    h.controller.apply(profile(output()));
    assert.equal(h.pending.length, 1);
    h.query(config(output(), second));
    const request = h.pending.shift();
    assert.equal(request.kind, "apply");
    assert.ok(request.args.includes("output.DP-1.enable"));
    assert.ok(request.args.includes("output.HDMI-1.disable"));
    request.complete({status: "ok"});
    h.query(config(output(), second));
    assert.deepEqual(h.events.slice(-2), [["error", "", ""], ["busy", false]]);
    assert.equal(h.pending.length, 0);
});

test("preflight failure makes no apply request and permits a later attempt", () => {
    const h = harness();
    h.controller.apply(profile(output()));
    h.query(config());
    assert.deepEqual(h.events.slice(-2), [["error", "preflight", "DP-1: disconnected"], ["busy", false]]);
    assert.equal(h.pending.length, 0);
    h.controller.apply(profile(output()));
    assert.equal(h.pending.length, 1);
});

test("nonzero exit and libkscreen's zero-exit failure message are both surfaced", () => {
    for (const result of [{status: "error", stderr: "Invalid command"},
        {status: "ok", stdout: "applying config failed! rejected"}]) {
        const h = harness();
        h.controller.apply(profile(output()));
        h.query();
        h.pending.shift().complete(result);
        assert.equal(h.events.at(-2)[1], "apply");
        assert.equal(h.pending.length, 0);
        assert.deepEqual(h.events.at(-1), ["busy", false]);
    }
});

test("zero exit without the desired state produces a verification error", () => {
    const h = harness();
    h.controller.apply(profile(output({rotation: 16})));
    h.query();
    h.pending.shift().complete({status: "ok"});
    h.query();
    assert.deepEqual(h.events.at(-2), ["error", "verify", "DP-1: rotation"]);
});

test("invalid queries are reported separately before and after application", () => {
    for (const afterApply of [false, true]) {
        const h = harness();
        h.controller.apply(profile(output()));
        if (afterApply) {
            h.query();
            h.pending.shift().complete({status: "ok"});
        }
        h.pending.shift().complete({status: "ok", text: "not JSON"});
        assert.deepEqual(h.events.at(-2), ["error", afterApply ? "verifyQuery" : "query", ""]);
        assert.deepEqual(h.events.at(-1), ["busy", false]);
    }
});

test("malformed query structures finish without applying further commands and allow another attempt", () => {
    for (const broken of [null, [], {}, {name: "OTHER", modes: {}},
        {name: "OTHER", modes: [null]}, {name: "OTHER", modes: [{size: "1920x1080"}]}]) {
        for (const afterApply of [false, true]) {
            const h = harness();
            h.controller.apply(profile(output()));
            if (afterApply) {
                h.query();
                h.pending.shift().complete({status: "ok"});
            }
            h.query(config(output(), broken));
            assert.deepEqual(h.events.slice(-2), [
                ["error", afterApply ? "verifyQuery" : "query", ""], ["busy", false]
            ]);
            assert.equal(h.pending.length, 0);
            h.controller.apply(profile(output()));
            h.query();
            h.pending.shift().complete({status: "ok"});
            h.query();
            assert.deepEqual(h.events.slice(-2), [["error", "", ""], ["busy", false]]);
        }
    }
});

test("malformed saved structures fail preflight as a whole and do not issue commands", () => {
    for (const broken of [null, {name: "DP-2", modes: {}}, {name: "DP-2", modes: [null]}]) {
        const h = harness();
        const saved = profile(output(), broken);
        assert.deepEqual(prepareApplication(saved, config(output())).issues, ["invalid"]);
        h.controller.apply(saved);
        h.query();
        assert.deepEqual(h.events.slice(-2), [["error", "preflight", "invalid"], ["busy", false]]);
        assert.equal(h.pending.length, 0);
        assert.deepEqual(verifyApplication([], config(broken)), ["invalid"]);
    }
});

test("unconvertible setting values report preflight failure rather than stranding application", () => {
    const h = harness();
    // Valid JSON with an unfamiliar setting shape that cannot coerce to a number.
    const saved = profile(output({brightness: {toString: null, valueOf: null}}));
    h.controller.apply(saved);
    h.query(config(output({brightness: 1})));
    assert.deepEqual(h.events.slice(-2), [["error", "preflight", "invalid"], ["busy", false]]);
    assert.equal(h.pending.length, 0);
    h.controller.apply(profile(output()));
    assert.equal(h.pending.length, 1);
});

test("summary helpers tolerate malformed modes and unfamiliar label values", () => {
    for (const value of [null, {modes: {}}, {modes: [null]},
        {currentModeId: "a", modes: [{id: "a", size: {width: {toString: null}}, refreshRate: 60}]}]) {
        assert.equal(modeLabel(value), "");
        assert.doesNotThrow(() => isEnabled(value));
    }
});

test("application retains sparse snapshots and ignores future metadata", () => {
    const sparse = {name: "DP-1", connected: true, modes: null, pos: null,
        future: {unknown: [null, 42]}};
    const plan = prepareApplication(profile(sparse), config(sparse));
    assert.deepEqual(plan.issues, []);
    assert.deepEqual(plan.args, ["output.DP-1.scale.1"]);
    assert.deepEqual(verifyApplication(plan.expected, config({...sparse, scale: 1})), []);
    assert.deepEqual(prepareApplication(profile(), config()).issues, []);
});
