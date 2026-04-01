# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Plasma 6 plasmoid (applet) that lets users save and switch between display configurations. Uses `kscreen-doctor` CLI to capture and apply display settings.

## Build & Install

```bash
# Development install (no CMake needed)
kpackagetool6 -t Plasma/Applet --install package/

# Upgrade after changes
kpackagetool6 -t Plasma/Applet --upgrade package/

# Remove
kpackagetool6 -t Plasma/Applet --remove dev.markusrenken.displayconfigswitcher

# Test without installing (requires plasma-sdk)
plasmoidviewer -a package/

# CMake install (system-wide)
cmake -B build && cmake --build build && sudo cmake --install build
```

After upgrading, restart plasmashell to see changes: `systemctl --user restart plasma-plasmashell.service` or `plasmashell --replace &`

## Architecture

This is a pure QML plasmoid with no C++ backend. All files live under `package/`.

- **`package/metadata.json`** - Plugin metadata (ID: `dev.markusrenken.displayconfigswitcher`). Must have `KPackageStructure: "Plasma/Applet"` and `X-Plasma-API-Minimum-Version: "6.0"`. About tab is auto-generated from `KPlugin` fields (`Authors`, `License`, `Website`, `BugReportUrl`).
- **`package/contents/ui/main.qml`** - Entry point. Always `main.qml` in Plasma 6 (not configurable). Root element must be `PlasmoidItem`.
- **`package/contents/config/main.xml`** - KConfig schema defining persistent settings.

## Key Plasma 6 Patterns

- **Command execution**: Uses `Plasma5Support.DataSource` with `engine: "executable"` to run shell commands. This is the standard Plasma 6 approach (there is no newer alternative).
- **Display config**: Captured via `kscreen-doctor -j` (JSON output), applied via `kscreen-doctor output.NAME.enable/disable/mode/position` commands. Multiple args in one call for atomic changes.
- **Profile storage**: Per-instance cache in `Plasmoid.configuration.profiles`, synced to shared file `~/.config/displayconfigswitcher-profiles.json` via shell commands. Shared file is source of truth; per-instance is a fast cache for immediate UI rendering.

## Gotchas

- **`kcfgfile name` doesn't update existing plasmoid instances**: Plasma caches the config file location when a widget is first added. Changing `main.xml` and upgrading does not migrate existing instances — they keep reading from the old location. Use `name=""` and manage shared config manually via shell commands.
- **DataSource timing in `Component.onCompleted`**: Commands run via `connectSource()` during `onCompleted` may not trigger `onNewData` reliably. Use `Qt.callLater()` to defer as a precaution.
- **`onPropertyChanged` parameter injection removed in Qt 6**: Use `root.propertyName` explicitly (e.g., `if (root.expanded)` not `if (expanded)`).
- **Shell escaping for JSON**: Single-quote escaping for `printf`: `json.replace(/'/g, "'\"'\"'")`. The executable DataSource runs through `sh -c`, so `$HOME` and `${XDG_CONFIG_HOME:-...}` expand.
- **QML `.mjs` imports**: Use `export function` syntax — works in both QML (`import "file.mjs" as Ns`) and Node.js. Standard `.js` files expose top-level functions without `export`.

## Plasma 6 QML Conventions

- Import `org.kde.plasma.plasmoid 2.0`, `org.kde.plasma.components 3.0`, `org.kde.kirigami`
- Use `Kirigami.Units` for spacing/sizing, `Kirigami.Theme` for colors
- Wrap all user-visible strings in `i18n()` for translations
- `compactRepresentation` = panel icon, `fullRepresentation` = popup content
- Properties like `expanded`, `toolTipMainText` go on the root `PlasmoidItem`, not the `Plasmoid` attached object
