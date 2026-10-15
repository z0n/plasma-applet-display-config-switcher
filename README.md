# Display Config Switcher

A Plasma 6 plasmoid that lets you save and switch between display configurations.

> [!NOTE]
> This project was primarily developed with [Claude Code](https://claude.ai/code).  
> I quickly created this for myself as there seems to be no maintained alternative.  
> I can't really guarantee best practices are followed, but it works fine for me.  
> If you're using it and it works, great! If not or something is missing, feel free to create an issue and I'll see what I can do.

![Screenshot](screenshot.png)

## Features

- Save your current display configuration as a named profile
- Switch between saved profiles from the panel
- Uses `kscreen-doctor` under the hood for display management
- Works on both X11 and Wayland

## Installation

Requires Plasma 6 and `kscreen-doctor` (included with KDE Plasma).

```bash
kpackagetool6 -t Plasma/Applet --install package/
```

After installation, add "Display Config Switcher" to your panel via the widget picker.

To upgrade after pulling new changes:

```bash
kpackagetool6 -t Plasma/Applet --upgrade package/
```

Restart the Plasma Shell afterwards, e.g. via `systemctl --user restart plasma-plasmashell.service`

To remove:

```bash
kpackagetool6 -t Plasma/Applet --remove dev.markusrenken.displayconfigswitcher
```

## Development

### Requirements

- Plasma 6 development environment
- `kpackagetool6` (from `plasma-sdk` or equivalent package)
- `plasmoidviewer` (from `plasma-sdk`, optional, for testing without installing)
- CMake (optional, for system-wide install)

### Testing

Run the profile-state and shell-storage tests with Node.js 18 or newer:

```bash
node --test tests/*.test.mjs
```

Exercise the QML module and Plasma executable adapter with Qt 6 QtTest:

```bash
sh tests/run-qml-tests.sh
# Optional: pass your Qt 6 qmltestrunner path as the first argument.
```

The QML harness uses an isolated config directory and a fake `kscreen-doctor`;
it does not change your display configuration.

For a manual Plasma check:

```bash
plasmoidviewer -a package/
```

Check saving, overwriting, deletion, error messages and Retry. With two instances,
delete the final profile in one, then reopen the other: both should show no
profiles. Applying a profile changes the running desktop's displays.

### Shared profile behavior

Profiles live in `${XDG_CONFIG_HOME:-$HOME/.config}/displayconfigswitcher-profiles.json`.
Each widget keeps an instance cache for startup. Valid shared profiles always win,
including an empty array. Only a missing shared file is seeded from the cache;
invalid content or read failures leave the displayed profiles intact and show an
error. The containing config directory must exist and be accessible.

The widget refreshes on startup, popup expansion and before edits. Edits target
profiles by name and appear only after the shared write succeeds. Failed writes
leave the displayed profiles and cache unchanged. Retry repeats the failed
operation against the latest shared profiles; a successfully captured snapshot
is retained when retrying a failed save.

Operations are serialized within each instance. Across instances, simultaneous
edits remain last-write-wins. An open, idle popup does not poll for changes.

The synchronization module is `package/contents/code/profile-state.mjs`, exposed
to the applet by `ProfileState.qml`. `ProfileStorage.qml` and
`profile-storage.mjs` implement the runtime storage/capture adapter. Tests exercise
the same state module with a deterministic adapter.

## Releasing

1. Include a `Version` bump in [package/metadata.json](package/metadata.json) in your PR
2. Merge the PR to main
3. Tag the merge commit and push the tag:
   ```bash
   git pull origin main
   git tag v<version>
   git push origin v<version>
   ```
4. GitHub Actions builds the `.plasmoid` file and creates a [GitHub Release](https://github.com/z0n/plasma-applet-display-config-switcher/releases)
5. Upload the `.plasmoid` from the release to the [KDE Store](https://store.kde.org)
