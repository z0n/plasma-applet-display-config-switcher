import QtQuick
import QtTest
import "../../package/contents/ui" as Applet

TestCase {
    name: "ProfileApplicationRuntime"

    Applet.ProfileApplication {
        id: application
        // qmltestrunner has no Plasma localization context.
        function i18n(message, value) {
            return message.replace("%1", value === undefined ? "" : value);
        }
    }

    function initTestCase() {
        if (Qt.application.arguments.indexOf("isolated-profile-tests") === -1)
            skip("Run via tests/run-qml-tests.sh to isolate display commands.");
    }

    function test_applyAndVerify() {
        const profile = {name: "Test", outputs: [{name: "TEST-1", connected: true,
            enabled: true, scale: 1, rotation: 16, overscan: 0,
            currentModeId: "old", modes: [{id: "old", name: "", refreshRate: 60,
                size: {width: 1920, height: 1080}}]}]};
        application.apply(profile);
        verify(application.busy);
        tryCompare(application, "busy", false, 5000);
        compare(application.error, "");
        // A second invocation exercises disconnect/reconnect and unique keys.
        application.apply(profile);
        tryCompare(application, "busy", false, 5000);
        compare(application.error, "");
    }

    function test_missingConnector() {
        application.apply({name: "Unplugged", outputs: [{name: "ABSENT", enabled: true}]});
        tryCompare(application, "busy", false, 5000);
        verify(application.error.indexOf("ABSENT: disconnected") !== -1);
    }

    function test_commandFailure() {
        // The fake doctor rejects any command except the expected smoke case.
        application.apply({name: "Rejected", outputs: [{name: "TEST-1", enabled: false}]});
        tryCompare(application, "busy", false, 5000);
        verify(application.error.indexOf("Could not apply") !== -1);
    }
}
