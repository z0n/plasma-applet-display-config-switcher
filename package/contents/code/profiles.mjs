export function mergeProfiles(shared, local) {
    let merged = shared.slice();
    for (let i = 0; i < local.length; i++) {
        let p = local[i];
        if (!merged.some(function(s) { return s.name === p.name; }))
            merged.push(p);
    }
    return merged;
}
