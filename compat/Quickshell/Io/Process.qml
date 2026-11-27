import QtQuick

Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    property var stderr: null
    // Quickshell's Process keeps a stdin pipe open while running when this is set. Here that
    // becomes a long-lived helper started through the launcher (startStream), fed by write().
    property bool stdinEnabled: false
    property var _activeCallback: null
    property int _streamId: -1

    signal exited(int code, int status)

    readonly property bool _canStream: typeof __NutstyBridge !== "undefined" && __NutstyBridge
                                       && typeof __NutstyBridge.startStream === "function"

    function _feed(target, data) {
        if (!data || !target) return;
        if (typeof target.feed === "function") {
            target.feed(data);
            if (typeof target.flush === "function") target.flush();
        } else if (typeof target.read === "function") {
            target.read(data);
        }
    }

    function _stopStream() {
        if (root._streamId < 0) return;
        var sid = root._streamId;
        root._streamId = -1;
        __NutstyBridge.stopStream(sid);
    }

    onRunningChanged: {
        if (running && root.stdinEnabled && root._canStream) {
            root._streamId = __NutstyBridge.startStream(root.command);
            if (root._streamId < 0) root.running = false;
            return;
        }
        if (!running) {
            if (root._streamId >= 0 && root._canStream) root._stopStream();
            return;
        }
        if (typeof __NutstyBridge !== "undefined" && __NutstyBridge.runProcess) {
            var cmdCopy = root.command;
            root._activeCallback = function(outData, errData, exitCode) {
                root._activeCallback = null;
                root._feed(root.stdout, outData);
                root.running = false;
                root.exited(exitCode || 0, 0);
            };
            __NutstyBridge.runProcess(cmdCopy, root._activeCallback);
        } else {
            root.running = false;
        }
    }

    Connections {
        target: root._canStream ? __NutstyBridge : null
        ignoreUnknownSignals: true
        function onStreamLine(sid, line) {
            if (sid === root._streamId) root._feed(root.stdout, line + "\n");
        }
        function onStreamExited(sid, code) {
            if (sid !== root._streamId) return;
            root._streamId = -1;
            root.running = false;
            root.exited(code, 0);
        }
    }

    Component.onDestruction: if (root._streamId >= 0 && root._canStream) root._stopStream()

    function write(data) {
        if (root._streamId >= 0 && root._canStream) __NutstyBridge.writeStream(root._streamId, String(data));
    }
}
