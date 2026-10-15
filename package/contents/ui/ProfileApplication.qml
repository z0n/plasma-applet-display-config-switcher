import QtQuick
import "../code/profile-application.mjs" as Application
import "../code/display-query.mjs" as DisplayQuery

QtObject {
    id: application

    property bool busy: false
    property string error: ""
    property var _controller: null
    property CommandRunner _runner: CommandRunner {}

    function apply(profile) {
        if (!application._controller) {
            application._controller = Application.createProfileApplication({
                capture: function(complete) {
                    DisplayQuery.capture(application._runner, complete);
                },
                apply: function(args, complete) {
                    application._runner.run(Application.applicationCommand(args), function(data) {
                        complete({status: data["exit code"] === 0 ? "ok" : "error",
                            stdout: data.stdout, stderr: data.stderr});
                    });
                }
            }, {
                busy: function(busy) { application.busy = busy; },
                error: function(code, details) {
                    switch (code) {
                    case "query":
                        application.error = i18n("Could not read the current display configuration. Check kscreen-doctor and try applying again.");
                        break;
                    case "preflight":
                        application.error = i18n("The profile needs unavailable displays, modes or settings: %1. No changes were applied.", details);
                        break;
                    case "empty":
                        application.error = i18n("This profile has no connected displays to configure.");
                        break;
                    case "apply":
                        application.error = i18n("Could not apply the display profile. Check the current display configuration before trying again. %1", details);
                        break;
                    case "verifyQuery":
                        application.error = i18n("The display command finished, but its result could not be verified. Check the current display configuration.");
                        break;
                    case "verify":
                        application.error = i18n("Some display settings were not restored: %1. Check the current display configuration.", details);
                        break;
                    default:
                        application.error = "";
                    }
                }
            });
        }
        // ListView modelData wraps nested arrays as QML sequences. Restore the
        // JSON snapshot before passing it to the JavaScript validation layer.
        application._controller.apply(profile ? JSON.parse(JSON.stringify(profile)) : profile);
    }
}
