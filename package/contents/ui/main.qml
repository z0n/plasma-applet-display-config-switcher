pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import "../code/profile-application.mjs" as Application

PlasmoidItem {
    id: root

    ProfileState {
        id: profileState
        objectName: "profileState"
        onPublished: function(json) { Plasmoid.configuration.profiles = json; }
    }

    ProfileApplication { id: profileApplication }

    switchWidth: Kirigami.Units.gridUnit * 20
    switchHeight: Kirigami.Units.gridUnit * 15
    toolTipMainText: i18n("Display Config Switcher")
    toolTipSubText: i18n("Save and switch between display configurations")

    onExpandedChanged: {
        if (root.expanded)
            profileState.refresh();
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            source: "preferences-desktop-display"
            anchors.fill: parent
        }
    }

    fullRepresentation: ColumnLayout {
        id: fullView

        property string editorMode: ""
        property string targetName: ""
        property bool submitted: false
        readonly property bool busy: profileState.busy || profileApplication.busy
        readonly property bool duplicateName: profileState.profiles.some(profile => profile.name === profileNameField.text.trim())

        function cancelEdit() {
            fullView.editorMode = "";
            fullView.targetName = "";
            fullView.submitted = false;
            profileNameField.text = "";
            addButton.forceActiveFocus();
        }

        function confirmEdit(name, deleting) {
            fullView.cancelEdit();
            fullView.targetName = name;
            fullView.editorMode = deleting ? "delete" : "update";
        }

        function submitEdit() {
            if (fullView.busy || fullView.editorMode === "")
                return;
            const name = fullView.editorMode === "create" ? profileNameField.text.trim() : fullView.targetName;
            if (name.length === 0)
                return;
            fullView.submitted = true;
            if (fullView.editorMode === "delete")
                profileState.remove(name);
            else
                profileState.save(name);
        }

        Keys.onEscapePressed: function(event) {
            if (fullView.editorMode !== "" && !fullView.busy) {
                fullView.cancelEdit();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }

        Connections {
            target: root
            function onExpandedChanged() {
                if (!root.expanded)
                    fullView.cancelEdit();
            }
        }

        Connections {
            target: profileState
            function onBusyChanged() {
                if (!profileState.busy && fullView.submitted && profileState.error === "")
                    fullView.cancelEdit();
            }
            function onProfilesChanged() {
                if ((fullView.editorMode === "update" || fullView.editorMode === "delete")
                    && !profileState.profiles.some(profile => profile.name === fullView.targetName))
                    fullView.cancelEdit();
            }
        }

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
                    objectName: "addProfileButton"
                    enabled: !profileState.busy && !profileApplication.busy

                    text: i18n("Save current display configuration")
                    icon.name: "list-add"
                    display: PlasmaComponents3.AbstractButton.IconOnly

                    onClicked: {
                        fullView.cancelEdit();
                        fullView.editorMode = "create";
                        profileNameField.forceActiveFocus();
                    }

                    PlasmaComponents3.ToolTip {
                        text: addButton.text
                    }
                }
            }
        }

        ColumnLayout {
            id: createForm
            objectName: "createProfileForm"
            visible: fullView.editorMode === "create"
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Save current configuration as")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            PlasmaComponents3.TextField {
                id: profileNameField
                objectName: "profileNameField"
                Layout.fillWidth: true
                enabled: !fullView.busy
                placeholderText: i18n("Profile name")
                Accessible.name: i18n("Profile name")
                onAccepted: {
                    if (saveProfileButton.enabled && !fullView.duplicateName)
                        fullView.submitEdit();
                }
            }

            PlasmaComponents3.Label {
                visible: fullView.duplicateName
                text: i18n("A profile named “%1” already exists. Replace it with the current configuration?", profileNameField.text.trim())
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                PlasmaComponents3.Button {
                    objectName: "cancelCreateButton"
                    text: i18n("Cancel")
                    enabled: !fullView.busy
                    onClicked: fullView.cancelEdit()
                }
                PlasmaComponents3.Button {
                    id: saveProfileButton
                    objectName: "saveProfileButton"
                    text: fullView.duplicateName ? i18n("Update existing") : i18n("Save")
                    icon.name: "document-save"
                    enabled: profileNameField.text.trim().length > 0 && !fullView.busy
                    onClicked: fullView.submitEdit()
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: profileState.error.length > 0
            type: Kirigami.MessageType.Error
            text: profileState.error
            actions: [
                Kirigami.Action {
                    text: i18n("Retry")
                    icon.name: "view-refresh"
                    enabled: !profileState.busy && !profileApplication.busy
                    onTriggered: profileState.retry()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: profileApplication.error.length > 0
            type: Kirigami.MessageType.Error
            text: profileApplication.error
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: profileList
                objectName: "profileList"

                model: profileState.profiles
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

                    required property var modelData
                    required property int index
                    readonly property bool confirming: fullView.targetName === profileDelegate.modelData.name
                        && (fullView.editorMode === "update" || fullView.editorMode === "delete")

                    width: profileList.width

                    function revealConfirmation() {
                        if (!profileDelegate.confirming)
                            return;
                        profileList.forceLayout();
                        profileList.positionViewAtIndex(profileDelegate.index,
                            profileDelegate.height > profileList.height ? ListView.End : ListView.Contain);
                    }

                    // Wait for the inline controls to resize the row before
                    // scrolling. Height changes also cover wrapped text.
                    onConfirmingChanged: {
                        if (profileDelegate.confirming)
                            Qt.callLater(profileDelegate.revealConfirmation);
                    }
                    onHeightChanged: {
                        if (profileDelegate.confirming)
                            Qt.callLater(profileDelegate.revealConfirmation);
                    }

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents3.Label {
                                    text: profileDelegate.modelData.name
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents3.Label {
                                    visible: !profileDelegate.confirming
                                    text: {
                                        var parts = [];
                                        for (var i = 0; i < profileDelegate.modelData.outputs.length; i++) {
                                            var out = profileDelegate.modelData.outputs[i];
                                            if (Application.isEnabled(out)) {
                                                var modeName = Application.modeLabel(out);
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
                                visible: !profileDelegate.confirming
                                enabled: !profileApplication.busy && !profileState.busy

                                text: i18n("Apply this profile")
                                icon.name: "media-playback-start"
                                display: PlasmaComponents3.AbstractButton.IconOnly

                                onClicked: profileApplication.apply(profileDelegate.modelData)

                                PlasmaComponents3.ToolTip {
                                    text: applyButton.text
                                }
                            }

                            PlasmaComponents3.ToolButton {
                                id: overwriteButton
                                visible: !profileDelegate.confirming
                                objectName: "overwriteProfileButton"
                                enabled: !profileState.busy && !profileApplication.busy

                                text: i18n("Overwrite with current configuration")
                                icon.name: "document-save"
                                display: PlasmaComponents3.AbstractButton.IconOnly

                                onClicked: fullView.confirmEdit(profileDelegate.modelData.name, false)

                                PlasmaComponents3.ToolTip {
                                    text: overwriteButton.text
                                }
                            }

                            PlasmaComponents3.ToolButton {
                                id: deleteButton
                                visible: !profileDelegate.confirming
                                objectName: "deleteProfileButton"
                                enabled: !profileState.busy && !profileApplication.busy

                                text: i18n("Delete this profile")
                                icon.name: "edit-delete"
                                display: PlasmaComponents3.AbstractButton.IconOnly

                                onClicked: fullView.confirmEdit(profileDelegate.modelData.name, true)

                                PlasmaComponents3.ToolTip {
                                    text: deleteButton.text
                                }
                            }
                        }

                        PlasmaComponents3.Label {
                            objectName: "profileConfirmationText"
                            visible: profileDelegate.confirming
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: fullView.editorMode === "delete"
                                ? i18n("Delete this profile?")
                                : i18n("Replace with the current display configuration?")
                        }

                        RowLayout {
                            visible: profileDelegate.confirming
                            Layout.alignment: Qt.AlignRight
                            PlasmaComponents3.Button {
                                id: cancelEditButton
                                objectName: "cancelProfileEditButton"
                                text: i18n("Cancel")
                                enabled: !fullView.busy
                                onClicked: fullView.cancelEdit()
                                onVisibleChanged: {
                                    if (visible)
                                        cancelEditButton.forceActiveFocus();
                                }
                            }
                            PlasmaComponents3.Button {
                                objectName: "confirmProfileEditButton"
                                text: fullView.editorMode === "delete" ? i18n("Delete") : i18n("Update")
                                icon.name: fullView.editorMode === "delete" ? "edit-delete" : "document-save"
                                enabled: !fullView.busy
                                onClicked: fullView.submitEdit()
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        profileState.initialize(Plasmoid.configuration.profiles);
        Qt.callLater(profileState.refresh);
    }
}
