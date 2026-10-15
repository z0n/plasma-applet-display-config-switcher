import QtQuick
import "../code/profile-state.mjs" as State

QtObject {
    id: state

    property var profiles: []
    property bool busy: false
    property string error: ""
    property var _controller: null
    property QtObject _storage: ProfileStorage {}

    signal published(string json)

    function initialize(cache) {
        state._controller = State.createProfileState(state._storage, cache, {
            publish: function(profiles, json) {
                state.profiles = profiles;
                state.published(json);
            },
            busy: function(busy) { state.busy = busy; },
            error: function(error) {
                switch (error) {
                case "read":
                    state.error = i18n("Could not read shared display profiles. Check access and retry.");
                    break;
                case "invalid":
                    state.error = i18n("Shared display profiles are invalid. Repair the file and retry.");
                    break;
                case "write":
                    state.error = i18n("Could not save shared display profiles. Your changes were not saved. Retry when storage is available.");
                    break;
                case "capture":
                    state.error = i18n("Could not capture the display configuration. Check kscreen-doctor and retry.");
                    break;
                default:
                    state.error = "";
                }
            }
        });
    }

    function refresh() { if (state._controller) state._controller.refresh(); }
    function save(name) { state._controller.save(name); }
    function remove(name) { state._controller.remove(name); }
    function retry() { state._controller.retry(); }
}
