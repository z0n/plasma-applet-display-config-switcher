# Repository guidance

## Development and verification
- Pure-QML Plasma 6 applet; no compiled backend or build step for local development. CMake only installs the package (requires ECM/KF6 and Plasma development packages).
- Run from the repository root: `plasmoidviewer -a package/` (requires Plasma 6, plasma-sdk and `kscreen-doctor`). This is the documented manual verification path; no automated tests, lint or formatter tasks are configured. Applying profiles changes the running desktop's displays.
- For local installation, upgrades, shell reloads, and removal, follow `README.md#installation`.
- System-wide install: `cmake -B build && cmake --build build && sudo cmake --install build`.

## Upstream sources
- When verifying KDE or Qt behavior, inspect the source references in `opencode.json`; their descriptions identify the relevant implementation.
- References follow upstream default branches. Check the installed dependency version and compare the corresponding release source before drawing version-specific conclusions.
- Treat cached reference checkouts as read-only; OpenCode refreshes them automatically.

## Runtime constraints
- `package/contents/ui/main.qml` contains both UI and all persistence/display logic. Its root is `PlasmoidItem`; `expanded` and tooltip properties belong there, not on the `Plasmoid` attached object.
- Commands run asynchronously through `Plasma5Support.DataSource` with `engine: "executable"`. `onNewData` disconnects each source and routes results by command text; update that routing when changing commands or the shared filename. Keep the startup shared-file read deferred with `Qt.callLater`.
- Profiles store raw `kscreen-doctor -j` outputs with a name and timestamp. Applying uses output **names**, resolves `currentModeId` to a mode **name**, maps rotation/VRR enums to CLI strings, and converts fractional brightness to percent. Keep all output arguments in one `kscreen-doctor` invocation.
- `Plasmoid.configuration.profiles` is a JSON-string per-instance cache defined in `package/contents/config/main.xml`. Cross-instance storage is `${XDG_CONFIG_HOME:-$HOME/.config}/displayconfigswitcher-profiles.json`, read on startup and popup expansion.
- A nonempty shared array overrides the cache; an empty/missing/invalid shared file currently gets seeded from a nonempty instance cache. Account for this fallback when changing deletion or synchronization behavior.
- Shared writes single-quote-escape JSON for `printf`, then write a `.tmp` file and rename it. Preserve shell escaping. After mutating the profiles array, `saveProfiles()` followed by `loadProfiles()` refreshes QML bindings.
- Keep `<kcfgfile name="" />`; changing the KConfig filename does not migrate existing widget instances because Plasma caches their config location. Sharing is implemented explicitly through the JSON file.
- Keep `KPackageStructure: "Plasma/Applet"` and `X-Plasma-API-Minimum-Version: "6.0"` in metadata. The About tab is generated from `KPlugin` fields.
- Use explicit object references in handlers and bound delegates (`root.expanded`, `profileDelegate.modelData`). Follow the existing unversioned imports, `Kirigami.Units`/`Kirigami.Theme`, and `i18n()` for user-visible strings.

## Releases
- `.github/workflows/release.yml` runs on `v*` tags and requires the tag without `v` to exactly match `KPlugin.Version` in `package/metadata.json`; include the version bump before tagging.
- A `.plasmoid` is a ZIP of the **contents** of `package/`, not the enclosing directory. CI validates metadata/entrypoint presence and packages the archive; it does not exercise QML or display behavior.

## Agent skills

### Issue tracker
Issues and specs live in GitHub Issues. Before tracker operations, read `docs/agents/issue-tracker.md`.

### Triage labels
Use the five canonical triage labels. Before triaging, read `docs/agents/triage-labels.md`.

### Domain docs
Single-context layout: root `GLOSSARY.md` and `docs/adr/`. Before exploring, read `docs/agents/domain.md`.
