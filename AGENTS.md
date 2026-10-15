# Repository guidance

## Documentation audience
- Keep `README.md` human-facing: installation, usage, user-visible limitations, and contributor test/release commands. Keep it concise and task-oriented.
- Put agent workflows, code-navigation pointers and implementation invariants in `AGENTS.md` or linked agent docs. Put dated research and verification logs in `docs/research/`; update the README only with lasting information useful to users or contributors.

## Development and verification
- Pure-QML Plasma 6 applet; no compiled backend or build step for local development. CMake only installs the package (requires ECM/KF6 and Plasma development packages).
- Tests: `node --test tests/*.test.mjs` for synchronization, display application and shell storage; `sh tests/run-qml-tests.sh` for isolated Qt 6/Plasma adapter integration. See `README.md#testing` for dependencies.
- Run from the repository root: `plasmoidviewer -a package/` (requires Plasma 6, plasma-sdk and `kscreen-doctor`). Applying profiles changes the running desktop's displays.
- For synchronization changes, manually check that deleting the final profile in one instance leaves another empty after reopening its popup. Application tests use simulated displays; distinguish those results from real display-switching verification.
- For local installation, upgrades, shell reloads, and removal, follow `README.md#installation`.
- System-wide install: `cmake -B build && cmake --build build && sudo cmake --install build`.

## Upstream sources
- When verifying KDE or Qt behavior, inspect the source references in `opencode.json`; their descriptions identify the relevant implementation.
- References follow upstream default branches. Check the installed dependency version and compare the corresponding release source before drawing version-specific conclusions.
- Treat cached reference checkouts as read-only; OpenCode refreshes them automatically.
- For compatibility work, read `docs/research/kde-compatibility-audit.md` for the dated upstream evidence and verification gaps; recheck versions before treating its findings as current.

## Runtime constraints
- `package/contents/ui/main.qml` contains UI. Its root is `PlasmoidItem`; `expanded` and tooltip properties belong there, not on the `Plasmoid` attached object.
- Profile synchronization lives in `package/contents/code/profile-state.mjs`, exposed by `ProfileState.qml`; keep authority, mutation ordering and publication there. Callers request refresh/save/remove/retry, targeting names rather than list indices.
- `ProfileStorage.qml` and `ProfileApplication.qml` use `CommandRunner.qml` for asynchronous `Plasma5Support.DataSource` commands. Each owner serializes requests. Preserve unique source keys, disconnect on completion and defer callbacks. Keep the startup shared-file read deferred with `Qt.callLater`.
- Profiles store raw `kscreen-doctor -j` outputs with a name and timestamp. `profile-application.mjs` preflights live outputs, matches saved dimensions/refresh rate to live mode IDs, translates settings and verifies the result. Missing `enabled` can mean no Disable capability. Keep shell-quoted output arguments in one apply invocation; verify actual state because command exit zero can still mean failure.
- `Plasmoid.configuration.profiles` is a JSON-string per-instance cache defined in `package/contents/config/main.xml`. Cross-instance storage is `${XDG_CONFIG_HOME:-$HOME/.config}/displayconfigswitcher-profiles.json`, read on startup and popup expansion.
- Valid shared profiles, including `[]`, override the cache. Only an absent file triggers migration; invalid or unreadable storage blocks edits. Refresh before edits; publish profiles/cache only after a successful write. Cross-instance edits remain last-write-wins.
- Retry re-reads shared profiles before repeating a failed edit and retains a successful capture after a failed save. Popup refreshes preserve pending edit retries; idle popups do not poll.
- Storage commands in `profile-storage.mjs` quote paths and single-quote-escape JSON for `printf`, then rename a writer-specific temporary file. Preserve escaping, missing/error distinction and atomic replacement. New array publication refreshes QML bindings.
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
