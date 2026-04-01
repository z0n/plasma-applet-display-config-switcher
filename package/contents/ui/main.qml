pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "../code/profiles.mjs" as Profiles

PlasmoidItem {
    id: root

    property var profiles: []
    property string _pendingProfileName: ""
    readonly property string _sharedFile: "${XDG_CONFIG_HOME:-$HOME/.config}/displayconfigswitcher-profiles.json"

    switchWidth: Kirigami.Units.gridUnit * 20
    switchHeight: Kirigami.Units.gridUnit * 15
    toolTipMainText: i18n("Display Config Switcher")
    toolTipSubText: i18n("Save and switch between display configurations")

    onExpandedChanged: {
        if (root.expanded)
            root.readSharedProfiles();
    }

    function loadProfiles() {
        try {
            root.profiles = JSON.parse(Plasmoid.configuration.profiles);
        } catch (e) {
            root.profiles = [];
        }
    }

    function saveProfiles() {
        Plasmoid.configuration.profiles = JSON.stringify(root.profiles);
        root.writeSharedProfiles();
    }

    function writeSharedProfiles() {
        var json = JSON.stringify(root.profiles);
        var escaped = json.replace(/'/g, "'\"'\"'");
        var f = root._sharedFile;
        executable.run("printf '%s' '" + escaped + "' > " + f + ".tmp && mv " + f + ".tmp " + f);
    }

    function readSharedProfiles() {
        executable.run("cat " + root._sharedFile + " 2>/dev/null || true");
    }

    function captureCurrentConfig(profileName: string) {
        root._pendingProfileName = profileName;
        executable.run("kscreen-doctor -j");
    }

    readonly property var _rotationMap: ({
        1: "normal",  // None
        2: "left",
        4: "inverted",
        8: "right"
    })

    readonly property var _vrrPolicyMap: ({
        0: "never",
        1: "always",
        2: "automatic"
    })

    function handleConfigCapture(stdout: string, exitCode: int) {
        if (exitCode !== 0 || !stdout)
            return;

        var config;
        try {
            config = JSON.parse(stdout);
        } catch (e) {
            return;
        }
        if (!config.outputs)
            return;

        var profile = {
            "name": root._pendingProfileName,
            "outputs": config.outputs,
            "timestamp": new Date().toISOString()
        };
        // Replace existing profile with same name, or add new
        var found = false;
        for (var j = 0; j < root.profiles.length; j++) {
            if (root.profiles[j].name === root._pendingProfileName) {
                root.profiles[j] = profile;
                found = true;
                break;
            }
        }
        if (!found)
            root.profiles.push(profile);

        root.saveProfiles();
        root.loadProfiles(); // refresh bindings
        root._pendingProfileName = "";
    }

    function _findModeName(output: var): string {
        if (!output.modes || !output.currentModeId)
            return "";
        for (var i = 0; i < output.modes.length; i++) {
            if (output.modes[i].id === output.currentModeId)
                return output.modes[i].name;
        }
        return "";
    }

    function _outputArg(out: var, cmd: string, value: string): string {
        return "output." + out.name + "." + cmd + "." + value;
    }

    function _enabledOutputArgs(out: var): list<string> {
        var args = [];
        args.push("output." + out.name + ".enable");

        var modeName = root._findModeName(out);
        if (modeName)
            args.push(root._outputArg(out, "mode", modeName));
        if (out.pos)
            args.push(root._outputArg(out, "position", out.pos.x + "," + out.pos.y));

        args.push(root._outputArg(out, "scale", String(out.scale || 1)));

        // Properties that need enum mapping
        var rot = root._rotationMap[out.rotation];
        if (rot)
            args.push(root._outputArg(out, "rotation", rot));
        var vrr = root._vrrPolicyMap[out.vrrPolicy];
        if (vrr !== undefined)
            args.push(root._outputArg(out, "vrrpolicy", vrr));

        // Boolean toggle properties
        if (out.hdr !== undefined)
            args.push(root._outputArg(out, "hdr", out.hdr ? "enable" : "disable"));
        if (out.wcg !== undefined)
            args.push(root._outputArg(out, "wcg", out.wcg ? "enable" : "disable"));

        // Numeric properties
        if (out.priority > 0)
            args.push(root._outputArg(out, "priority", String(out.priority)));
        if (out["sdr-brightness"] !== undefined)
            args.push(root._outputArg(out, "sdr-brightness", String(out["sdr-brightness"])));
        if (out.brightness !== undefined)
            args.push(root._outputArg(out, "brightness", String(Math.round(out.brightness * 100))));
        if (out.overscan > 0)
            args.push(root._outputArg(out, "overscan", String(out.overscan)));

        return args;
    }

    function applyProfile(profile: var) {
        var args = [];
        for (var i = 0; i < profile.outputs.length; i++) {
            var out = profile.outputs[i];
            if (out.enabled)
                args = args.concat(root._enabledOutputArgs(out));
            else
                args.push("output." + out.name + ".disable");
        }
        if (args.length > 0)
            executable.run("kscreen-doctor " + args.join(" "));
    }

    function deleteProfile(idx: int) {
        root.profiles.splice(idx, 1);
        root.saveProfiles();
        root.loadProfiles();
    }

    Plasma5Support.DataSource {
        id: executable

        engine: "executable"
        connectedSources: []

        function run(cmd: string) {
            executable.connectSource(cmd);
        }

        onNewData: function(source, data) {
            var stdout = data["stdout"];
            var stderr = data["stderr"];
            var exitCode = data["exit code"];
            executable.disconnectSource(source);
            if (source === "kscreen-doctor -j") {
                root.handleConfigCapture(stdout, exitCode);
            } else if (source.indexOf("displayconfigswitcher-profiles.json") !== -1) {
                if (source.startsWith("cat ")) {
                    // Shared file read result — merge with per-instance profiles
                    let shared = [];
                    if (exitCode === 0 && stdout.trim().length > 0) {
                        try {
                            let parsed = JSON.parse(stdout);
                            if (Array.isArray(parsed))
                                shared = parsed;
                        } catch (e) {
                            console.warn("Display Config Switcher: shared profiles parse error:", e);
                        }
                    }
                    let merged = Profiles.mergeProfiles(shared, root.profiles);
                    if (merged.length > 0) {
                        let changed = JSON.stringify(merged) !== JSON.stringify(root.profiles);
                        root.profiles = merged;
                        Plasmoid.configuration.profiles = JSON.stringify(merged);
                        if (changed || shared.length !== merged.length)
                            root.writeSharedProfiles();
                    }
                }
            }
        }
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            source: "preferences-desktop-display"
            anchors.fill: parent
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 15
        Layout.minimumWidth: Kirigami.Units.gridUnit * 15
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        PlasmaExtras.PlasmoidHeading {
            Layout.fillWidth: true

            RowLayout {
                anchors.fill: parent

                PlasmaExtras.Heading {
                    level: 3
                    text: i18n("Display Profiles")
                    Layout.fillWidth: true
                }

                PlasmaComponents3.ToolButton {
                    id: addButton

                    text: i18n("Save current display configuration")
                    icon.name: "list-add"
                    display: PlasmaComponents3.AbstractButton.IconOnly

                    onClicked: saveDialog.open()

                    PlasmaComponents3.ToolTip {
                        text: addButton.text
                    }
                }
            }
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: profileList

                model: root.profiles
                clip: true

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - (Kirigami.Units.gridUnit * 4)
                    visible: profileList.count === 0
                    text: i18n("No profiles saved")
                    explanation: i18n("Click the + button to save your current display configuration")
                    iconName: "preferences-desktop-display"
                }

                delegate: PlasmaComponents3.ItemDelegate {
                    id: profileDelegate

                    required property int index
                    required property var modelData

                    width: profileList.width

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            PlasmaComponents3.Label {
                                text: profileDelegate.modelData.name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents3.Label {
                                text: {
                                    var parts = [];
                                    for (var i = 0; i < profileDelegate.modelData.outputs.length; i++) {
                                        var out = profileDelegate.modelData.outputs[i];
                                        if (out.enabled) {
                                            var modeName = root._findModeName(out);
                                            parts.push(out.name + (modeName ? " " + modeName : ""));
                                        }
                                    }
                                    return parts.join(", ");
                                }
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            id: applyButton

                            text: i18n("Apply this profile")
                            icon.name: "media-playback-start"
                            display: PlasmaComponents3.AbstractButton.IconOnly

                            onClicked: root.applyProfile(profileDelegate.modelData)

                            PlasmaComponents3.ToolTip {
                                text: applyButton.text
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            id: overwriteButton

                            text: i18n("Overwrite with current configuration")
                            icon.name: "document-save"
                            display: PlasmaComponents3.AbstractButton.IconOnly

                            onClicked: root.captureCurrentConfig(profileDelegate.modelData.name)

                            PlasmaComponents3.ToolTip {
                                text: overwriteButton.text
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            id: deleteButton

                            text: i18n("Delete this profile")
                            icon.name: "edit-delete"
                            display: PlasmaComponents3.AbstractButton.IconOnly

                            onClicked: root.deleteProfile(profileDelegate.index)

                            PlasmaComponents3.ToolTip {
                                text: deleteButton.text
                            }
                        }
                    }
                }
            }
        }

        QQC2.Dialog {
            id: saveDialog

            title: i18n("Save Display Profile")
            anchors.centerIn: parent
            modal: true
            standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

            onAccepted: {
                if (profileNameField.text.trim() !== "") {
                    root.captureCurrentConfig(profileNameField.text.trim());
                    profileNameField.text = "";
                }
            }
            onRejected: {
                profileNameField.text = "";
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: i18n("Profile name:")
                }

                PlasmaComponents3.TextField {
                    id: profileNameField

                    Layout.fillWidth: true
                    placeholderText: i18n("e.g., Dual Monitors, TV Mode")
                }
            }
        }
    }

    Component.onCompleted: {
        root.loadProfiles();
        Qt.callLater(root.readSharedProfiles);
    }
}
