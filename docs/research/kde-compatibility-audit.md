# KDE compatibility audit

Research date: **2026-10-15**. Local baseline: `ee7325c6f835d7b3259726ef6193495b4271d95a` (`main`, clean at start). Scope: source inspection, official upstream documentation, and the limited local checks below. **No display-changing tests were performed.** No application code was changed or issues created. Local line references below refer to this baseline, principally `package/contents/ui/main.qml` (abbreviated `main.qml`).

## Executive conclusion

The pure-QML packaging and Plasma imports still exist in Plasma 6.8. There is no evidence that this applet requires a compiled backend merely to remain loadable. However, profile replay has concrete correctness gaps: capability-dependent absence of `enabled` is misinterpreted, zero overscan is not restored, reflected rotations are omitted, and X11 mode names are unsuitable for replay. Apply failures are also invisible. Fix those before expanding coverage of newer display settings.

## Implementation follow-up

Implementation follow-up on `feat/profile-state-improvements`: the working changes
now address omitted `enabled`, live mode matching (including empty X11 mode names),
zero overscan, reflected rotations, unavailable connectors/settings, apply-error
reporting and post-apply verification in `profile-application.mjs` and
`ProfileApplication.qml`. README dependency and X11 guidance was updated. The
findings below describe the original audit baseline, not the updated line numbers.
Verification of these changes: 33 Node tests passed; the isolated Qt/Plasma suite
passed 8 checks (including setup/cleanup); Qt 6 qmllint reported only unqualified
`i18n()` access warnings; an isolated offscreen applet startup passed. A read-only
query of two real outputs passed preflight and comparison with their current
state. Real display-changing application and Plasma 6.8 runtime testing remain
manual follow-ups. Optional extra settings listed below remain outside replay.

## Verified release baseline and date limits

Official published announcements, not projected schedules, establish:

| Component      | Latest stable identified | Publication | Relevant dependency facts                                                                                     |
| -------------- | ------------------------ | ----------- | ------------------------------------------------------------------------------------------------------------- |
| Plasma         | **6.8.0**                | 2026-10-14  | Released libplasma and libkscreen require Qt ≥6.11.0 and KF ≥6.30.0 in their source builds.                   |
| KDE Frameworks | **6.31.0**               | 2026-10-09  | Announcement states Qt ≥6.10.0.                                                                               |
| Qt             | **6.12.0 LTS**           | 2026-09-30  | Latest Qt Framework release identified in the official release feed; this is not Plasma's minimum Qt version. |

Sources: [Plasma announcement][R1], [Frameworks announcement][R2], [Qt announcement][R3], [Qt release feed][R4], [libplasma build requirements][P1], [libkscreen build requirements][K1]. The fetched KDE announcement index reaches October 14 and Qt's release feed reaches October 7, 2026; the Qt Framework announcement itself reaches September 30. Thus sources reach the requested month but do not publish a newer release on October 15. This is the latest **identified published** baseline, not proof of absence of a same-day update or of distribution availability. All three Plasma source tags `v6.8.0` were fetched successfully; no development-branch implementation is substituted for the stable baseline.

## Concrete defects and recommended priorities

### P1 — Missing `enabled` is treated as disabled

**Evidence:** libkscreen 6.8 serializes `enabled` only when the output supports `Capability::Disable` ([serializer, lines 75–79][K2]). `main.qml:163–166` uses a truthiness check, so an absent property selects `.disable` and skips mode, position, scale, and all other enabled-output settings. The summary at `main.qml:313` also hides that output.

**Impact:** profiles captured for outputs without this capability cannot restore their ordinary settings. This does **not** prove that the applet actually switches such a screen off: upstream `Doctor::setEnabled` explicitly rejects enable/disable requests for such outputs ([doctor, lines 949–957][K3]). The proven defect is misclassification and skipped replay. Hardware prevalence was not measured.

**Action:** normalize missing enable state separately from explicit `false`, using connected/current output information; do not emit enable/disable operations for unsupported outputs. Preserve compatibility with older saved JSON. Add a fixture with an active output whose JSON omits `enabled`, alongside explicit true/false fixtures.

### P1 — Mode replay is backend-dependent; historical X11 profiles lose mode restoration

`main.qml:106–113,124–126` resolves a saved mode ID to `modes[].name` and emits a mode argument only when that name is nonempty. Current `Doctor::findMode` accepts a live mode ID or a synthesized `WIDTHxHEIGHT@ROUND(refreshRate)` string, not an arbitrary JSON mode name ([doctor, lines 967–988][K3]). Wayland currently constructs exactly that name ([Wayland backend, lines 498–501][K4]), so this path works for ordinary Wayland modes.

The XRandR backend in the last pre-6.8 stable series leaves `m_name` unset (assignment is commented out), then serializes it via `setName(m_name)` ([6.7.5 XRandR source][K5]). Therefore the applet omits mode restoration for these profiles. This is an existing backend compatibility defect, not a new Wayland regression.

**Action:** derive a portable selector from saved mode size and refresh rate, or match saved size/rate against a freshly queried mode list and use the corresponding live ID. The latter also addresses ambiguity between rates that round to the same integer (for example 59.94 and 60). Never blindly replay stale numeric IDs across sessions. Verify an X11-captured fixture if historical X11 support remains promised.

### P2 — Zero overscan and reflected rotations are not restored

* `main.qml:153–154` sends overscan only when greater than zero. Switching from a nonzero overscan profile to a saved zero leaves the old overscan unchanged. Upstream permits **0–100** ([doctor, lines 281–288][K3]); the serializer includes zero when supported ([K2]). Test property presence rather than positivity.
* `main.qml:58–63,133–135` maps only rotations 1, 2, 4, and 8. Upstream also defines 16/32/64/128 as `Flipped`, `Flipped90`, `Flipped180`, `Flipped270` ([enum, lines 105–114][K6]) and accepts their lowercase CLI spellings ([doctor, lines 257–280][K3]). A saved reflected transform is silently omitted. Complete the mapping and verify all eight values. This is missing coverage within an already replayed property, not an API removal.

### P2 — Apply outcome is discarded; hotplug/version mismatches are opaque

At `main.qml:188–222`, results are routed only for capture and shared storage. Apply stdout/stderr/exit status are read but never surfaced. `main.qml:159–169` also submits every saved connector without querying current outputs. A missing connector makes upstream parsing return early ([doctor, lines 194–198][K3]); unsupported commands and invalid modes have similar paths. Do not assume all-or-nothing behavior: parsing mutates an in-memory configuration before the later apply step.

**Action:** add a distinct apply-result path, preflight current connectors/capabilities, and re-query to verify intended settings. Do not equate exit code zero with successful restoration: 6.8's `configReceived` prints `applying config failed!` on failure and subsequently exits zero ([doctor, lines 613–637][K3]). This source behavior strengthens the case for post-apply verification.

Profiles captured on newer releases may also contain values/commands unavailable on older releases. For example the applet replays `brightness` whenever present, while the 6.0 doctor parser does not implement that subcommand; the old SDR-brightness minimum is 100, versus 50 in 6.8 ([6.0 parser][K7], [current parser][K3]). Supporting Plasma 6.0 loading is not a promise that a new profile can be fully replayed on it. Prefer capability/version-aware translation and explicit skipped-setting feedback.

### P2 — Documentation overstates present X11 support and omits runtime dependencies

`README.md:18` says “Works on both X11 and Wayland” without version qualification. Plasma **6.8 has retired starting Plasma X11 sessions**; X11 applications continue through XWayland ([R1]). This is now a released change, not merely a future trajectory. XWayland application support does not supply an X11 Plasma session or make XRandR the correct display-management backend under Wayland. Qualify the claim by Plasma series and historical testing; acknowledge the mode issue above.

`README.md:22,48–51` should identify the runtime Plasma5Support QML module/executable engine, Kirigami and Plasma QML modules, and the package providing `kscreen-doctor` (upstream **libkscreen**, distro names vary). `kpackagetool6` is built by **KPackage**, not plasma-sdk ([F1]); `plasmoidviewer` remains the separately documented development viewer. Missing Plasma5Support would prevent the import at `main.qml:9`, regardless of whether the desktop is called Plasma 6.

## Interfaces verified as present and compatible in principle

### Command execution and display translation

Plasma5Support 6.8 registers `org.kde.plasma.plasma5support` and compiles `datasource.cpp` ([S1]); it builds the executable engine ([S2]). That engine supplies `stdout`, `stderr`, and `exit code`, and invokes `KProcess::setShellCommand` ([S3], lines 26–41), matching `main.qml:178–192`. The project describes this as a **migration aid**, recommending migration of dataengines to QML imports ([S4]). That is architectural guidance, not evidence that the current engine is removed or a published removal deadline. Keep the dependency explicit; replacing it is optional engineering work.

`kscreen-doctor` is still built and installed by 6.8 ([K8]), despite the release announcement introducing `kscreenctl`. The new tool does not by itself require migration. This audit does not establish its profile format or substitution compatibility.

Output names remain accepted, now alongside UUIDs and numeric IDs ([K3], lines 140–160). Existing position, scale, normal rotations, VRR enum mapping, HDR/WCG toggles, positive priority, SDR brightness and percentage brightness translations match the inspected parser and serializer ([K2], [K3], [K6]). Fractional brightness multiplied by 100 at `main.qml:152` matches the CLI's division by 100; integer rounding loses precision but matches the integer CLI contract. One invocation for all output arguments remains appropriate. Names and shell arguments still need quoting/validation when constructing shell commands; preserve JSON single-quote escaping in any future execution refactor.

### QML types and API deprecation check

The unversioned QtQuick/Controls/Layouts imports, `PlasmoidItem` root, and explicit required delegate properties are consistent with the current approach. Qt documents `ComponentBehavior: Bound` since 6.4, required delegate properties for bound delegates, and function-annotation enforcement since 6.7 ([Q1]); `main.qml:1,287–291` follows that model. No source-level mismatch in the used function signatures was identified; this is not a runtime parser check.

Plasma 6.8 still registers `org.kde.plasma.components` 3.0 ([P2]) and exports the used extras `Heading`, `PlasmoidHeading`, and `PlaceholderMessage` ([P3]). `PlasmoidItem` tooltip properties and inherited switch-size properties still exist ([P4], [P5]), matching `main.qml:12–22`. The `TextField.qml` deprecation found concerns **`clearButtonShown`**, not the entire TextField type ([P6], lines 25–30); this applet does not use that property. No mandatory replacement of these imported components was established.

Kirigami 6.31 still declares `Units.gridUnit` and `Theme.smallFont` ([F2], [F3]), used at `main.qml:19–20,322`. This is a targeted API inspection, not an exhaustive deprecation audit of every transitive Qt/KDE implementation. Plasma 6.8's new Union theme is explicitly beta/opt-in ([R1]); visual verification under Breeze and Union is useful but not evidence of a current applet defect.

### Metadata and installation/build

`package/metadata.json:19–20` retains `X-Plasma-API-Minimum-Version: "6.0"` and `KPackageStructure: "Plasma/Applet"`; the current loader still consults the minimum-version metadata ([P7]). No reason to bump that declaration solely to equal the latest Plasma release was found. It is not a substitute for a tested minimum support matrix.

`CMakeLists.txt:15` uses a still-existing `plasma_install_package` macro, which delegates to KPackage installation ([P8]). A compiled applet is not required. Local `KF_MIN_VERSION` is used for ECM lookup; local `QT_MIN_VERSION` is set but never passed to a Qt lookup, and `find_package(Plasma REQUIRED)` has no explicit version. These declarations do not independently enforce the implied runtime floor. Installed Plasma development configuration supplies its own dependency checks; current upstream build minima are higher than the applet's old constants ([P1]). Document ECM and libplasma development packages for optional CMake installation, without imposing those source-build dependencies on users installing a pure-QML package with KPackage.

## Optional feature coverage, not loading incompatibilities

The raw saved `outputs` array (`main.qml:84–87`) is only as complete as upstream JSON. Replay (`main.qml:120–156`) implements a subset. Current JSON also exposes RGB range, automatic rotation policy, ICC profile path, replication source, follow-preferred-mode, DDC/CI policy, maximum bits per color, and EDR policy ([K2]); they are not restored. CLI supports several of these, including `rgbrange`, `iccprofile`, `mirror`, `ddcCi`, `maxbpc` and `edrPolicy` ([K3]). Treat these as scoped feature work unless full-fidelity profile restoration is explicitly promised. Replication would require mapping a saved source ID back to a connector rather than reusing the ID.

Conversely, current CLI supports settings such as HDR ICC profile, gamut widening, brightness overrides, color-profile source, dimming and automatic brightness which are **not all serialized by `serializeOutput`** ([K2], [K3]). Adding replay arguments alone cannot restore absent capture data. Decide the profile schema and capture mechanism first. `kscreenctl` evaluation is an optional follow-up, not a prerequisite to fixing current defects.

## Local verification performed

The installed Wayland environment reports Plasma workspace, Plasma5Support, libkscreen and KScreen **6.7.5**, Kirigami/KPackage/ECM **6.31.0**, and Qt base/declarative **6.12.0** (`pacman -Q`). These checks do not constitute runtime verification of Plasma 6.8.

- `/usr/lib/qt6/bin/qmllint package/contents/ui/main.qml` exited successfully, with six unqualified-access warnings for Plasma-provided `i18n()` calls and no missing-import/API diagnostics. The unqualified `/usr/bin/qmllint` was an unsuitable default and exited 255 without diagnostics; the explicit Qt 6 executable was used instead.
- `kscreen-doctor -j` exited zero and returned valid JSON for two active outputs, including the fields and matching mode IDs expected by the applet. This was a read-only query.
- `plasmoidviewer -a <absolute-package-path>` with `QT_QPA_PLATFORM=offscreen` and isolated XDG config/data/cache/state directories stayed running for a 12-second startup smoke check, then was terminated by the check. Its only diagnostic was the standard QML-debugging notice. This does not establish visual correctness or exercise popup interactions or profile application.
- `cmake -S . -B /tmp/opencode/display-config-switcher-compat-build` and `cmake --install /tmp/opencode/display-config-switcher-compat-build --prefix /tmp/opencode/display-config-switcher-compat-install` succeeded. Installation was staged under the temporary prefix, not into the running desktop.

## Suggested further verification (not performed)

1. Add focused translation fixtures for omitted `enabled`, zero overscan, all rotations, empty XRandR mode names, rounded-rate collisions, missing connectors, and old/new CLI capability boundaries.
2. On Plasma 6.8 with a distribution-supported Qt/KF combination, load with `plasmoidviewer -a package/`; exercise save/apply/overwrite/delete and review QML diagnostics and command outcomes. Verify outcomes by re-querying `kscreen-doctor -j`.
3. Exercise a real multi-output Wayland configuration, hotplug and unsupported capabilities. Test HDR/VRR/brightness only on suitable hardware; validate all-output transaction behavior.
4. If retaining a broad Plasma 6 promise, test the oldest supported release and a pre-6.8 X11 installation separately. Report exactly which combinations and operations pass; dependency/source presence alone does not establish runtime compatibility.

No glossary or ADR files were present, so no domain-document conflict was identified. Existing shared-file fallback/concurrency behavior is outside this upstream-compatibility audit.

## Primary sources and reproducibility

Source links below are pinned to release commits/tags where possible; release announcements and Qt documentation are dated/versioned publications. Checked source commits: libkscreen `e6b870e8aa3ba197a1df4d58f166c95a86e17121`, libplasma `a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a`, plasma5support `73c1b1c82523d0e6e0634c6e3b2f46b05f758186` (all `v6.8.0`), Kirigami `eecf183a956fdbfbf331c0ef61fd6e35220d4275` (`v6.31.0`). Temporary clones were inspected under `/tmp/opencode/audit-*`.

[R1]: https://kde.org/announcements/plasma/6/6.8.0/
[R2]: https://kde.org/announcements/frameworks/6/6.31.0/
[R3]: https://www.qt.io/blog/qt-6.12-released
[R4]: https://www.qt.io/blog/tag/releases
[K1]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/CMakeLists.txt
[K2]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/src/configserializer.cpp
[K3]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/src/doctor/doctor.cpp
[K4]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/backends/kwayland/waylandoutputdevice.cpp
[K5]: https://invent.kde.org/plasma/libkscreen/-/blob/v6.7.5/backends/xrandr/xrandrmode.cpp
[K6]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/src/output.h
[K7]: https://invent.kde.org/plasma/libkscreen/-/blob/v6.0.0/src/doctor/doctor.cpp
[K8]: https://invent.kde.org/plasma/libkscreen/-/blob/e6b870e8aa3ba197a1df4d58f166c95a86e17121/src/doctor/CMakeLists.txt
[S1]: https://invent.kde.org/plasma/plasma5support/-/blob/73c1b1c82523d0e6e0634c6e3b2f46b05f758186/src/declarativeimports/CMakeLists.txt
[S2]: https://invent.kde.org/plasma/plasma5support/-/blob/73c1b1c82523d0e6e0634c6e3b2f46b05f758186/src/dataengines/executable/CMakeLists.txt
[S3]: https://invent.kde.org/plasma/plasma5support/-/blob/73c1b1c82523d0e6e0634c6e3b2f46b05f758186/src/dataengines/executable/executable.cpp
[S4]: https://invent.kde.org/plasma/plasma5support/-/blob/73c1b1c82523d0e6e0634c6e3b2f46b05f758186/README.md
[P1]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/CMakeLists.txt
[P2]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/declarativeimports/CMakeLists.txt
[P3]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/declarativeimports/plasmaextracomponents/CMakeLists.txt
[P4]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/plasmaquick/plasmoid/plasmoiditem.h
[P5]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/plasmaquick/appletquickitem.h
[P6]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/declarativeimports/plasmacomponents3/TextField.qml
[P7]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/src/plasmaquick/appletquickitem.cpp
[P8]: https://invent.kde.org/plasma/libplasma/-/blob/a3a89f0a51dab1d7df8ac0bcd8aa4cbec94e422a/PlasmaMacros.cmake
[F1]: https://invent.kde.org/frameworks/kpackage/-/blob/v6.31.0/src/kpackagetool/CMakeLists.txt
[F2]: https://invent.kde.org/frameworks/kirigami/-/blob/eecf183a956fdbfbf331c0ef61fd6e35220d4275/src/platform/units.h
[F3]: https://invent.kde.org/frameworks/kirigami/-/blob/eecf183a956fdbfbf331c0ef61fd6e35220d4275/src/platform/platformtheme.h
[Q1]: https://doc.qt.io/qt-6/qtqml-documents-structure.html
