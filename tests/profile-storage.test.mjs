import assert from "node:assert/strict";
import test from "node:test";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { readCommand, writeCommand } from "../package/contents/code/profile-storage.mjs";

function fixture(t) {
    const directory = mkdtempSync(join(tmpdir(), "profile-storage-"));
    t.after(() => rmSync(directory, {recursive: true, force: true}));
    const config = join(directory, "config with ' quotes");
    mkdirSync(config);
    const file = join(config, "displayconfigswitcher-profiles.json");
    const run = command => spawnSync("/bin/sh", ["-c", command], {
        encoding: "utf8", env: {...process.env, XDG_CONFIG_HOME: config}
    });
    return {directory, config, file, run};
}

test("runtime commands distinguish absence, empty content and read failure", t => {
    const f = fixture(t);
    assert.equal(f.run(readCommand()).status, 44);
    writeFileSync(f.file, "");
    assert.equal(f.run(readCommand()).status, 0);
    rmSync(f.file);
    mkdirSync(f.file);
    assert.equal(f.run(readCommand()).status, 1);
    rmSync(f.file, {recursive: true});
    symlinkSync(join(f.directory, "absent"), f.file);
    assert.equal(f.run(readCommand()).status, 1);
});

test("runtime write round-trips hostile-looking text and cleans temporary files", t => {
    const f = fixture(t);
    const profiles = [{name: "Bob's $(exit 99) `exit 98`\nDesk; \\", outputs: []}];
    assert.equal(f.run(writeCommand(profiles)).status, 0);
    assert.deepEqual(JSON.parse(f.run(readCommand()).stdout), profiles);
    assert.deepEqual(readdirSync(f.config), ["displayconfigswitcher-profiles.json"]);
    assert.equal(f.run(writeCommand([])).status, 0);
    assert.equal(readFileSync(f.file, "utf8"), "[]");
});

test("failed rename reports failure and removes the temporary file", t => {
    const f = fixture(t);
    // A file cannot replace a directory; -T prevents mv treating it as a target directory.
    mkdirSync(f.file);
    assert.notEqual(f.run(writeCommand([])).status, 0);
    assert.deepEqual(readdirSync(f.config), ["displayconfigswitcher-profiles.json"]);
    assert.deepEqual(readdirSync(f.file), []);
});
