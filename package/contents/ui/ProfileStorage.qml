import QtQuick
import "../code/profile-storage.mjs" as Commands
import "../code/display-query.mjs" as DisplayQuery

QtObject {
    id: storage

    property CommandRunner _runner: CommandRunner {}

    function read(complete) {
        storage._runner.run(Commands.readCommand(), function(data) {
            const code = data["exit code"];
            complete({status: code === 0 ? "ok" : code === 44 ? "missing" : "error", text: data.stdout});
        });
    }

    function write(profiles, complete) {
        storage._runner.run(Commands.writeCommand(profiles), function(data) {
            complete({status: data["exit code"] === 0 ? "ok" : "error"});
        });
    }

    function capture(complete) {
        DisplayQuery.capture(storage._runner, complete);
    }
}
