import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

QtObject {
    id: runner

    property string _command: ""
    property var _complete: null
    readonly property string _instance: Date.now().toString(36) + Math.random().toString(36).slice(2)
    property int _sequence: 0
    property QtObject _executable: Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            if (source !== runner._command)
                return;
            executable.disconnectSource(source);
            const complete = runner._complete;
            runner._command = "";
            runner._complete = null;
            Qt.callLater(function() { complete(data); });
        }
    }

    // Each owner serializes its requests. Unique keys avoid sharing executable
    // sources across widget instances or successive invocations.
    function run(command, complete) {
        runner._complete = complete;
        runner._command = command + " # profiles-" + runner._instance + "-" + (++runner._sequence);
        executable.connectSource(runner._command);
    }
}
