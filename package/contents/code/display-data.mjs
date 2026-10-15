function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Only check containers that callers traverse, not a version-specific settings
// schema. Keep unknown fields, sparse outputs and legacy modes intact. Null or
// missing optional containers mean absent data, as in the existing consumers.
export function hasDisplayStructure(config) {
    return isObject(config) && Array.isArray(config.outputs) && config.outputs.every(output =>
        isObject(output) && typeof output.name === "string"
        && (output.pos == null || isObject(output.pos))
        && (output.modes == null || (Array.isArray(output.modes) && output.modes.every(mode =>
            isObject(mode) && (mode.size == null || isObject(mode.size))))));
}
