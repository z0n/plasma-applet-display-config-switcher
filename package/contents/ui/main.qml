pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
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
                    enabled: !profileState.busy && !profileApplication.busy

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
                            enabled: !profileState.busy && !profileApplication.busy

                            text: i18n("Overwrite with current configuration")
                            icon.name: "document-save"
                            display: PlasmaComponents3.AbstractButton.IconOnly

                            onClicked: profileState.save(profileDelegate.modelData.name)

                            PlasmaComponents3.ToolTip {
                                text: overwriteButton.text
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            id: deleteButton
                            enabled: !profileState.busy && !profileApplication.busy

                            text: i18n("Delete this profile")
                            icon.name: "edit-delete"
                            display: PlasmaComponents3.AbstractButton.IconOnly

                            onClicked: profileState.remove(profileDelegate.modelData.name)

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
                    profileState.save(profileNameField.text.trim());
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
        profileState.initialize(Plasmoid.configuration.profiles);
        Qt.callLater(profileState.refresh);
    }
}
