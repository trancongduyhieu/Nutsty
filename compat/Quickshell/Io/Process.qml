import QtQuick

Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    property var stderr: null
    property var _activeCallback: null

    signal exited(int code, int status)

    onRunningChanged: {
        if (running) {
            if (typeof __NutstyBridge !== "undefined" && __NutstyBridge.runProcess) {
                var cmdCopy = root.command;
                root._activeCallback = function(outData, errData, exitCode) {
                    root._activeCallback = null;
                    if (outData && root.stdout) {
                        if (typeof root.stdout.feed === "function") {
                            root.stdout.feed(outData);
                            if (typeof root.stdout.flush === "function") {
                                root.stdout.flush();
                            }
                        } else if (typeof root.stdout.read === "function") {
                            root.stdout.read(outData);
                        }
                    }
                    root.running = false;
                    root.exited(exitCode || 0, 0);
                };
                __NutstyBridge.runProcess(cmdCopy, root._activeCallback);
            } else {
                root.running = false;
            }
        }
    }

    function write(data) {
        // Can bridge to stdin if needed
    }
}
