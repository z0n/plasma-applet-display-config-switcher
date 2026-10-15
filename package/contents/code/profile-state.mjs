import {hasDisplayStructure} from "./display-data.mjs";

// The storage adapter completes read/write/capture with a result object.
// All operations (including capture) run in order within this instance.
export function createProfileState(storage, cache, events) {
    let profiles;
    try {
        profiles = parseProfiles(cache);
    } catch (_) {
        profiles = [];
    }
    let queue = [];
    let active = false;
    let failed = null;
    let published = JSON.stringify(profiles);
    events.publish(profiles, published);

    function publish(next) {
        const json = JSON.stringify(next);
        if (json !== published) {
            profiles = next;
            published = json;
            events.publish(next, json);
        }
    }

    function finish(operation, error) {
        if (error) {
            // Keep the message and Retry action tied to the same operation.
            // Popup refreshes must not disguise a retained edit as a read retry.
            if (!failed || operation.kind !== "refresh" || failed.kind === "refresh") {
                failed = operation;
                events.error(error);
            }
        } else if (operation.kind === "refresh" && failed && failed.kind === "refresh") {
            failed = null;
            events.error("");
        }
        active = false;
        events.busy(false);
        runNext();
    }

    function persist(operation, next) {
        storage.write(next, function(result) {
            if (result.status !== "ok") {
                finish(operation, "write");
                return;
            }
            publish(next);
            finish(operation);
        });
    }

    function readFor(operation) {
        storage.read(function(result) {
            let next;
            const missing = result.status === "missing";
            if (missing) {
                next = profiles.slice();
            } else if (result.status === "ok") {
                try {
                    next = parseProfiles(result.text);
                } catch (_) {
                    finish(operation, "invalid");
                    return;
                }
            } else {
                finish(operation, "read");
                return;
            }

            const before = JSON.stringify(next);
            if (operation.kind === "save") {
                const index = next.findIndex(function(profile) {
                    return profile.name === operation.name;
                });
                if (index !== -1 && !operation.replaceExisting) {
                    publish(next);
                    finish(operation, "exists");
                    return;
                }
                if (index === -1)
                    next.push(operation.profile);
                else
                    next[index] = operation.profile;
            } else if (operation.kind === "remove") {
                next = next.filter(function(profile) {
                    return profile.name !== operation.name;
                });
            }

            // Establish missing storage even for an empty collection. A valid
            // empty file is authoritative on every subsequent read.
            if (missing || JSON.stringify(next) !== before) {
                persist(operation, next);
            } else {
                publish(next);
                finish(operation);
            }
        });
    }

    function runNext() {
        if (active || queue.length === 0)
            return;
        const operation = queue.shift();
        active = true;
        if (operation.kind !== "refresh" || !failed) {
            failed = null;
            events.error("");
        }
        events.busy(true);
        if (operation.kind === "save" && !operation.profile) {
            storage.capture(function(result) {
                let config;
                try {
                    if (result.status !== "ok")
                        throw new Error("Capture failed");
                    config = JSON.parse(result.text);
                    if (!hasDisplayStructure(config))
                        throw new Error("Invalid capture");
                } catch (_) {
                    finish(operation, "capture");
                    return;
                }
                operation.profile = {
                    name: operation.name,
                    outputs: config.outputs,
                    timestamp: new Date().toISOString()
                };
                readFor(operation);
            });
        } else {
            readFor(operation);
        }
    }

    function enqueue(operation) {
        queue.push(operation);
        runNext();
    }

    return {
        refresh: function() { enqueue({kind: "refresh"}); },
        save: function(name, replaceExisting = false) {
            enqueue({kind: "save", name: name, replaceExisting: replaceExisting});
        },
        remove: function(name) { enqueue({kind: "remove", name: name}); },
        cancelEdit: function() {
            if (!active && failed && failed.kind !== "refresh") {
                failed = null;
                events.error("");
            }
        },
        retry: function() {
            if (failed && !active)
                enqueue(failed);
        }
    };
}

function parseProfiles(text) {
    const profiles = JSON.parse(text);
    if (!Array.isArray(profiles) || profiles.some(function(profile) {
        return !hasDisplayStructure(profile) || typeof profile.name !== "string";
    }))
        throw new Error("Invalid profiles");
    return profiles;
}
