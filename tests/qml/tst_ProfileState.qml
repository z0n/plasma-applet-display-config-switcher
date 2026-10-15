import QtQuick
import QtTest
import "../../package/contents/ui" as Applet

TestCase {
    id: testCase
    name: "ProfileStateRuntime"

    Applet.ProfileState { id: first }
    Applet.ProfileState { id: second }
    Applet.ProfileApplication {
        id: application
        function i18n(message, value) {
            return message.replace("%1", value === undefined ? "" : value);
        }
    }
    ListView {
        id: profiles
        width: 300
        height: 300
        model: first.profiles
        delegate: Item {
            required property var modelData
            width: 300
            height: 40
            function apply() { application.apply(modelData); }
        }
    }
    SignalSpy { id: publication; target: first; signalName: "published" }

    function initTestCase() {
        if (Qt.application.arguments.indexOf("isolated-profile-tests") === -1)
            skip("Run via tests/run-qml-tests.sh to isolate display profiles.");
    }

    function settle(state) {
        tryCompare(state, "busy", false, 5000);
        compare(state.error, "");
    }

    // Run through run-qml-tests.sh: it isolates XDG_CONFIG_HOME and supplies a
    // fake kscreen-doctor. This exercises the actual Plasma executable adapter.
    function test_sharedLifecycle() {
        const cache = JSON.stringify([{name: "Desk", outputs: [], timestamp: "old"}]);
        first.initialize(cache);
        second.initialize(cache);
        first.refresh();
        settle(first);
        first.save("TV");
        settle(first);
        compare(first.profiles.length, 2);
        compare(first.profiles[1].outputs[0].name, "TEST-1");

        // Apply the fresh capture through the same modelData boundary as the UI.
        tryVerify(function() { return profiles.itemAtIndex(1) !== null; });
        profiles.itemAtIndex(1).apply();
        tryCompare(application, "busy", false, 5000);
        compare(application.error, "");

        second.refresh();
        settle(second);
        compare(second.profiles.length, 2);
        first.remove("Desk");
        settle(first);
        first.remove("TV");
        settle(first);
        compare(first.profiles.length, 0);
        second.refresh();
        settle(second);
        compare(second.profiles.length, 0);
        compare(publication.signalArguments[publication.count - 1][0], "[]");

        const count = publication.count;
        first.refresh();
        settle(first);
        compare(publication.count, count);
    }
}
