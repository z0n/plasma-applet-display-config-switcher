export function capture(runner, complete) {
    runner.run("kscreen-doctor -j", function(data) {
        complete({status: data["exit code"] === 0 ? "ok" : "error", text: data.stdout});
    });
}
