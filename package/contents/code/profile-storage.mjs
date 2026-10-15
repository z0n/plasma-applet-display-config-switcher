// Shell commands are kept with the runtime adapter, not synchronization policy.
const fileAssignment = 'file="${XDG_CONFIG_HOME:-$HOME/.config}/displayconfigswitcher-profiles.json"; ';

export function readCommand() {
    // Do not mistake an inaccessible directory or a dangling symlink for a
    // missing file. Exit 44 is reserved for an absent file in a usable directory.
    return fileAssignment
        + 'if [ -f "$file" ]; then cat -- "$file"; '
        + 'elif [ ! -e "$file" ] && [ ! -L "$file" ] '
        + '&& [ -d "${file%/*}" ] && [ -x "${file%/*}" ]; then exit 44; '
        + 'else exit 1; fi';
}

export function writeCommand(profiles) {
    const escaped = JSON.stringify(profiles).replace(/'/g, "'\"'\"'");
    // Each writer owns a temporary file; concurrent instances remain
    // last-write-wins without corrupting each other's temporary content.
    return fileAssignment
        + 'tmp=$(mktemp "$file.tmp.XXXXXX") || exit 1; '
        + 'trap \'rm -f -- "$tmp"\' EXIT; '
        + "printf '%s' '" + escaped + "' > \"$tmp\" && mv -T -- \"$tmp\" \"$file\"";
}
