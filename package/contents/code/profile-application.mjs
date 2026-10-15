const rotations = {1: "normal", 2: "left", 4: "inverted", 8: "right",
    16: "flipped", 32: "flipped90", 64: "flipped180", 128: "flipped270"};
const vrrPolicies = {0: "never", 1: "always", 2: "automatic"};

export function isEnabled(output) {
    if (output.connected === false)
        return false;
    if (output.enabled !== undefined)
        return output.enabled === true;
    // Newer libkscreen omits enabled for outputs without Disable capability.
    return output.connected === true || !!currentMode(output);
}

function currentMode(output) {
    return (output.modes || []).find(mode => String(mode.id) === String(output.currentModeId));
}

export function modeLabel(output) {
    const mode = currentMode(output);
    if (!mode)
        return "";
    return mode.name || (mode.size ? mode.size.width + "x" + mode.size.height
        + "@" + Math.round(mode.refreshRate) : "");
}

function sameMode(a, b) {
    if (a.size && b.size && Number.isFinite(a.refreshRate) && Number.isFinite(b.refreshRate))
        return a.size.width === b.size.width && a.size.height === b.size.height
            && Math.abs(a.refreshRate - b.refreshRate) < 0.01;
    return !!a.name && a.name === b.name;
}

// Preflight the entire profile before emitting any display-changing command.
// Live mode IDs avoid stale IDs and rounded-refresh-rate selector collisions.
export function prepareApplication(profile, config) {
    const args = [];
    const expected = [];
    const issues = [];
    if (!profile || !Array.isArray(profile.outputs) || !config || !Array.isArray(config.outputs))
        return {args, expected, issues: ["invalid"]};
    for (const saved of profile.outputs) {
        if (!saved || typeof saved.name !== "string") {
            issues.push("invalid");
            continue;
        }
        const enabled = isEnabled(saved);
        const live = config.outputs.find(output => output.name === saved.name && output.connected !== false);
        if (!live) {
            if (enabled)
                issues.push(saved.name + ": disconnected");
            continue; // Already absent outputs need no disable command.
        }
        const target = {name: saved.name, enabled};
        const add = (command, value) => args.push("output." + saved.name + "." + command
            + (value === undefined ? "" : "." + value));
        if (live.enabled !== undefined) {
            add(enabled ? "enable" : "disable");
        } else if (!enabled) {
            issues.push(saved.name + ": disable");
        }
        expected.push(target);
        if (!enabled)
            continue;

        const mode = currentMode(saved);
        if (mode) {
            const matches = (live.modes || []).filter(candidate => sameMode(mode, candidate));
            if (matches.length === 1) {
                add("mode", matches[0].id);
                target.mode = matches[0];
            } else {
                issues.push(saved.name + ": mode");
            }
        } else if (saved.currentModeId !== undefined && saved.currentModeId !== "") {
            issues.push(saved.name + ": mode");
        }
        if (saved.pos) {
            add("position", saved.pos.x + "," + saved.pos.y);
            target.pos = saved.pos;
        }
        add("scale", saved.scale || 1);
        target.scale = saved.scale || 1;
        if (saved.rotation !== undefined) {
            if (rotations[saved.rotation]) {
                add("rotation", rotations[saved.rotation]);
                target.rotation = saved.rotation;
            } else {
                issues.push(saved.name + ": rotation");
            }
        }
        if (saved.priority > 0) {
            add("priority", saved.priority);
            target.priority = saved.priority;
        }
        for (const key of ["vrrPolicy", "hdr", "wcg", "sdr-brightness", "brightness", "overscan"]) {
            if (saved[key] === undefined)
                continue;
            // These JSON fields are capability-dependent. Older backends or
            // different hardware may not support a setting in a saved profile.
            if (live[key] === undefined) {
                issues.push(saved.name + ": " + key);
                continue;
            }
            let value = saved[key];
            let command = key;
            if (key === "vrrPolicy") {
                command = "vrrpolicy";
                value = vrrPolicies[value];
                if (value === undefined) {
                    issues.push(saved.name + ": " + key);
                    continue;
                }
            } else if (key === "hdr" || key === "wcg") {
                value = value ? "enable" : "disable";
            } else if (key === "brightness") {
                value = Math.round(value * 100);
            }
            add(command, value);
            target[key] = key === "brightness" ? value / 100 : saved[key];
        }
    }
    return {args: issues.length ? [] : args, expected, issues};
}

export function applicationCommand(args) {
    return "kscreen-doctor " + args.map(arg => "'" + arg.replace(/'/g, "'\"'\"'") + "'").join(" ");
}

export function verifyApplication(expected, config) {
    if (!config || !Array.isArray(config.outputs))
        return ["invalid"];
    const differences = [];
    for (const target of expected) {
        const live = config.outputs.find(output => output.name === target.name && output.connected !== false);
        if (!live) {
            if (target.enabled)
                differences.push(target.name + ": disconnected");
            continue;
        }
        for (const key of Object.keys(target)) {
            if (key === "name")
                continue;
            let matches;
            if (key === "enabled")
                matches = isEnabled(live) === target.enabled;
            else if (key === "mode")
                matches = !!currentMode(live) && sameMode(target.mode, currentMode(live));
            else if (key === "pos")
                matches = !!live.pos && live.pos.x === target.pos.x && live.pos.y === target.pos.y;
            else if (typeof target[key] === "number")
                matches = typeof live[key] === "number" && Math.abs(live[key] - target[key]) < 0.001;
            else
                matches = live[key] === target[key];
            if (!matches)
                differences.push(target.name + ": " + key);
        }
    }
    return differences;
}

// Adapter callbacks are asynchronous; a single application owns the query,
// atomic apply, and verification sequence. Repeated clicks cannot overlap it.
export function createProfileApplication(adapter, events) {
    let busy = false;
    function finish(code, details) {
        events.error(code || "", details || "");
        busy = false;
        events.busy(false);
    }
    function query(complete, failure) {
        adapter.capture(result => {
            let config;
            try {
                if (result.status !== "ok")
                    throw new Error("Query failed");
                config = JSON.parse(result.text);
                if (!config || !Array.isArray(config.outputs))
                    throw new Error("Invalid query");
            } catch (_) {
                finish(failure);
                return;
            }
            complete(config);
        });
    }
    return {
        apply(profile) {
            if (busy)
                return;
            busy = true;
            events.busy(true);
            events.error("", "");
            query(config => {
                const plan = prepareApplication(profile, config);
                if (plan.issues.length) {
                    finish("preflight", plan.issues.join(", "));
                    return;
                }
                if (!plan.args.length) {
                    finish("empty");
                    return;
                }
                adapter.apply(plan.args, result => {
                    // libkscreen can report SetConfigOperation failure on
                    // stdout while still exiting zero. Also verify actual state.
                    const details = ((result.stdout || "") + "\n" + (result.stderr || "")).trim();
                    if (result.status !== "ok" || details.includes("applying config failed!")) {
                        finish("apply", details.slice(0, 2000));
                        return;
                    }
                    query(actual => {
                        const differences = verifyApplication(plan.expected, actual);
                        finish(differences.length ? "verify" : "", differences.join(", "));
                    }, "verifyQuery");
                });
            }, "query");
        }
    };
}
