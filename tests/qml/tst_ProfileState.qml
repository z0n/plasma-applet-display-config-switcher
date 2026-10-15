import QtQuick
import QtTest
import "../../package/contents/ui" as Applet

TestCase {
    id: testCase
    name: "ProfileStateRuntime"

    Applet.ProfileState { id: first }
    Applet.ProfileState { id: second }
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
