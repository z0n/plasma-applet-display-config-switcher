import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ProfileConfirmation"
    width: 300
    height: 300
    visible: true
    when: windowShown

    property var applet
    property var view
    property var state
    property var edits
    property bool failSave: false

    Component {
        id: memoryStorage
        QtObject {
            property var profiles: [{name: "Desk", outputs: []}]
            property bool failWrite: false
            function read(done) {
                Qt.callLater(function() { done({status: "ok", text: JSON.stringify(profiles)}); });
            }
            function capture(done) {
                Qt.callLater(function() { done({status: "ok", text: '{"outputs":[{"name":"NEW"}]}'}); });
            }
            function write(next, done) {
                Qt.callLater(function() {
                    if (!failWrite)
                        profiles = next;
                    done({status: failWrite ? "error" : "ok"});
                });
            }
        }
    }

    function useRealController() {
        const storage = createTemporaryObject(memoryStorage, testCase);
        testCase.state._storage = storage;
        // The representation has no Plasma host; publication to the attached
        // configuration is the only unavailable part of the real state adapter.
        ignoreWarning(/.*main.qml:.*Value is undefined and could not be converted to an object/);
        testCase.state.initialize(JSON.stringify(storage.profiles));
        wait(0); // Let the applet's deferred startup refresh run as well.
        tryCompare(testCase.state, "busy", false);
        return storage;
    }

    function i18n(message, value) {
        return message.replace("%1", value === undefined ? "" : value);
    }

    function visualChild(item, name) {
        if (item.objectName === name && item.visible)
            return item;
        for (const child of item.children || []) {
            const match = visualChild(child, name);
            if (match)
                return match;
        }
        return null;
    }

    function control(name) {
        let item = null;
        tryVerify(function() {
            item = visualChild(testCase.view, name);
            return item !== null;
        });
        return item;
    }

    function recordEdit(action, name) {
        testCase.edits.push(action + ":" + name);
        testCase.state.busy = true;
        Qt.callLater(function() {
            testCase.state.error = testCase.failSave ? "Save failed" : "";
            testCase.state.busy = false;
        });
    }

    function init() {
        // Exercise the real representation without a plasmashell host. Only
        // persistence is replaced; these tests never change real profiles.
        const component = Qt.createComponent("../../package/contents/ui/main.qml");
        compare(component.status, Component.Ready, component.errorString());
        ignoreWarning(/.*main.qml:.*Cannot read property 'profiles' of undefined/);
        testCase.applet = createTemporaryObject(component, testCase);
        verify(testCase.applet !== null);
        testCase.state = findChild(testCase.applet, "profileState");
        verify(testCase.state !== null);
        testCase.edits = [];
        testCase.failSave = false;
        testCase.state._controller = {
            save: function(name) { testCase.recordEdit("save", name); },
            remove: function(name) { testCase.recordEdit("remove", name); },
            refresh: function() {},
            retry: function() { testCase.recordEdit("retry", ""); },
            cancelEdit: function() {}
        };
        testCase.state.profiles = [{name: "Desk", outputs: []}];
        testCase.view = createTemporaryObject(testCase.applet.fullRepresentation, testCase, {width: 300, height: 300});
        verify(testCase.view !== null);
    }

    function test_rowConfirmation_data() {
        return [{tag: "update", button: "overwrite", operation: "save"},
                {tag: "delete", button: "delete", operation: "remove"}];
    }

    function test_rowConfirmation(data) {
        mouseClick(control(data.button + "ProfileButton"));
        const question = control("profileConfirmationText");
        waitForPolish(testCase.view);
        verify(question.height >= question.implicitHeight);
        const position = question.mapToItem(testCase.view, 0, 0);
        verify(position.x >= 0 && position.x + question.width <= testCase.view.width);
        compare(testCase.edits.length, 0);
        mouseClick(control("cancelProfileEditButton"));
        compare(testCase.view.editorMode, "");
        compare(testCase.edits.length, 0);

        mouseClick(control(data.button + "ProfileButton"));
        keyClick(Qt.Key_Return); // Cancel is focused, never destructive confirmation.
        compare(testCase.edits.length, 0);
        testCase.view.cancelEdit();
        mouseClick(control(data.button + "ProfileButton"));
        keyClick(Qt.Key_Escape);
        compare(testCase.view.editorMode, "");

        mouseClick(control(data.button + "ProfileButton"));
        mouseClick(control("confirmProfileEditButton"));
        tryCompare(testCase.view, "editorMode", "");
        compare(testCase.edits.join(","), data.operation + ":Desk");
    }

    function test_createAndDuplicate() {
        mouseClick(control("addProfileButton"));
        const field = control("profileNameField");
        verify(field.activeFocus);
        verify(!control("saveProfileButton").enabled);
        field.text = "   ";
        verify(!control("saveProfileButton").enabled);
        field.text = " Desk ";
        verify(testCase.view.duplicateName);
        waitForPolish(testCase.view);
        keyClick(Qt.Key_Return);
        compare(testCase.edits.length, 0);
        compare(testCase.view.editorMode, "create");
        mouseClick(control("saveProfileButton"));
        tryCompare(testCase.view, "editorMode", "");
        compare(testCase.edits.join(","), "save:Desk");

        mouseClick(control("addProfileButton"));
        field.text = " New profile ";
        keyClick(Qt.Key_Return);
        tryCompare(testCase.view, "editorMode", "");
        compare(testCase.edits.join(","), "save:Desk,save:New profile");
    }

    function test_failedSaveRetainsName() {
        testCase.failSave = true;
        mouseClick(control("addProfileButton"));
        const field = control("profileNameField");
        field.text = "New profile";
        waitForPolish(testCase.view);
        mouseClick(control("saveProfileButton"));
        compare(testCase.edits.join(","), "save:New profile");
        tryCompare(testCase.state, "busy", false);
        compare(testCase.view.editorMode, "create");
        compare(field.text, "New profile");
        testCase.failSave = false;
        testCase.state.retry();
        tryCompare(testCase.view, "editorMode", "");
    }

    function test_refreshAndClose() {
        mouseClick(control("deleteProfileButton"));
        testCase.state.profiles = [{name: "Other", outputs: []}, {name: "Desk", outputs: []}];
        compare(testCase.view.targetName, "Desk");
        mouseClick(control("confirmProfileEditButton"));
        tryCompare(testCase.view, "editorMode", "");
        compare(testCase.edits.join(","), "remove:Desk");

        testCase.view.confirmEdit("Desk", false);
        testCase.state.profiles = [{name: "Other", outputs: []}];
        compare(testCase.view.editorMode, "");

        testCase.applet.expanded = true;
        mouseClick(control("addProfileButton"));
        testCase.applet.expanded = false;
        compare(testCase.view.editorMode, "");
    }

    function test_cancelFailedDeletionDiscardsRetry() {
        const storage = useRealController();
        storage.failWrite = true;
        mouseClick(control("deleteProfileButton"));
        mouseClick(control("confirmProfileEditButton"));
        tryCompare(testCase.state, "busy", false);
        verify(testCase.state.error.length > 0);
        mouseClick(control("cancelProfileEditButton"));
        compare(testCase.view.editorMode, "");
        compare(testCase.state.error, "");
        storage.failWrite = false;
        testCase.state.retry();
        wait(20);
        compare(storage.profiles.length, 1);
    }

    function test_popupClosePreservesFailedEditRetry() {
        const storage = useRealController();
        storage.failWrite = true;
        testCase.applet.expanded = true;
        tryCompare(testCase.state, "busy", false);
        mouseClick(control("deleteProfileButton"));
        mouseClick(control("confirmProfileEditButton"));
        tryCompare(testCase.state, "busy", false);
        const error = testCase.state.error;
        verify(error.length > 0);
        testCase.applet.expanded = false;
        compare(testCase.view.editorMode, "");
        compare(testCase.state.error, error);
        testCase.applet.expanded = true;
        tryCompare(testCase.state, "busy", false);
        compare(testCase.state.error, error);
        storage.failWrite = false;
        ignoreWarning(/.*main.qml:.*Value is undefined and could not be converted to an object/);
        testCase.state.retry();
        tryCompare(testCase.state, "busy", false);
        compare(storage.profiles.length, 0);
        compare(testCase.state.error, "");
    }

    function test_staleCreateRequiresReplacementConfirmation() {
        const storage = useRealController();
        mouseClick(control("addProfileButton"));
        const field = control("profileNameField");
        field.text = "Other";
        compare(testCase.view.duplicateName, false);
        storage.profiles = [{name: "Other", outputs: [{name: "KEEP"}]}];
        waitForPolish(testCase.view);
        ignoreWarning(/.*main.qml:.*Value is undefined and could not be converted to an object/);
        mouseClick(control("saveProfileButton"));
        verify(testCase.state.busy);
        tryCompare(testCase.state, "busy", false);
        compare(storage.profiles[0].outputs[0].name, "KEEP");
        compare(testCase.view.editorMode, "create");
        compare(field.text, "Other");
        compare(testCase.view.duplicateName, true);
        compare(control("saveProfileButton").text, "Update existing");
        verify(testCase.state.error.length > 0);
        compare(testCase.state.retryAvailable, false);
        waitForPolish(testCase.view);
        ignoreWarning(/.*main.qml:.*Value is undefined and could not be converted to an object/);
        mouseClick(control("saveProfileButton"));
        tryCompare(testCase.state, "busy", false);
        compare(storage.profiles[0].outputs[0].name, "NEW");
        compare(testCase.view.editorMode, "");
        compare(testCase.state.error, "");
    }

    function test_lastRowConfirmationStaysInView_data() {
        return [{tag: "delete", button: "delete"}, {tag: "update", button: "overwrite"}];
    }

    function test_lastRowConfirmationStaysInView(data) {
        const profiles = [];
        for (let i = 0; i < 30; ++i)
            profiles.push({name: "Profile " + i, outputs: []});
        testCase.state.profiles = profiles;
        const list = control("profileList");
        waitForPolish(testCase.view);
        list.positionViewAtEnd();
        let row = null;
        tryVerify(function() {
            row = list.itemAtIndex(profiles.length - 1);
            return row !== null;
        });
        waitForPolish(testCase.view);
        // The last row is clickable before the list reaches its exact end.
        list.contentY -= 12;
        const collapsedHeight = row.height;
        mouseClick(visualChild(row, data.button + "ProfileButton"));
        const confirm = control("confirmProfileEditButton");
        const cancel = control("cancelProfileEditButton");
        waitForPolish(testCase.view);
        waitForPolish(list);
        tryVerify(function() { return row.height > collapsedHeight; });
        tryVerify(function() {
            return [confirm, cancel].every(function(button) {
                const position = button.mapToItem(list, 0, 0);
                return position.y >= 0 && position.y + button.height <= list.height;
            });
        });
        compare(testCase.edits.length, 0);
    }
}
