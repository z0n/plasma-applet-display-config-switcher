import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/profile-storage.mjs" as Commands

QtObject {
    id: storage

    property string _command: ""
    property var _complete: null
    readonly property string _instance: Date.now().toString(36) + Math.random().toString(36).slice(2)
    property int _sequence: 0
    property QtObject _executable: Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            if (source !== storage._command)
                return;
            executable.disconnectSource(source);
            const complete = storage._complete;
            storage._command = "";
            storage._complete = null;
            // Leave the source's completion handler before starting more work.
            Qt.callLater(function() { complete(data); });
        }
    }

    function _run(command, complete) {
        storage._complete = complete;
        // Executable sources are keyed by command text, including across
        // instances. A fresh key prevents sharing an in-flight operation.
        storage._command = command + " # profiles-" + storage._instance + "-" + (++storage._sequence);
        executable.connectSource(storage._command);
    }

    function read(complete) {
        storage._run(Commands.readCommand(), function(data) {
            const code = data["exit code"];
            complete({status: code === 0 ? "ok" : code === 44 ? "missing" : "error", text: data.stdout});
        });
    }

    function write(profiles, complete) {
        storage._run(Commands.writeCommand(profiles), function(data) {
            complete({status: data["exit code"] === 0 ? "ok" : "error"});
        });
    }

    function capture(complete) {
        storage._run("kscreen-doctor -j", function(data) {
            complete({status: data["exit code"] === 0 ? "ok" : "error", text: data.stdout});
        });
    }
}
