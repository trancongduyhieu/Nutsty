import QtQuick

Item {
    id: root
    property string path: ""
    property bool watchChanges: false
    // Real Quickshell loads async unless this is set; this reader is always synchronous, so it is accepted and ignored
    property bool blockLoading: false
    property bool loaded: false
    property string _content: ""

    signal fileChanged()
    // Mirrors Quickshell FileView; this reader is synchronous and reports a missing file as empty
    // text instead, so it never fires (shell.qml checks for empty settings itself).
    signal loadFailed(var error)
    // Mirrors Quickshell FileView: text() is a function, textChanged fires when the content changes.
    signal textChanged()
    on_ContentChanged: root.textChanged()

    function reload() {
        if (!path) return;
        if (typeof __NutstyBridge !== "undefined" && __NutstyBridge && __NutstyBridge.readFile) {
            _content = __NutstyBridge.readFile(path);
            loaded = true;
        } else {
            loaded = false;
        }
    }

    function text() {
        if (!_content && path) {
            reload();
        }
        return _content;
    }

    onPathChanged: {
        reload();
    }

    Component.onCompleted: {
        reload();
    }

    function _norm(p) {
        return String(p || "").replace(/^file:\/\/\/?/, "").replace(/\\/g, "/").toLowerCase();
    }

    // A backend thread wrote a file (wallpaper palette): reload now instead of on the next poll
    Connections {
        target: (root.watchChanges && typeof __NutstyBridge !== "undefined") ? __NutstyBridge : null
        ignoreUnknownSignals: true
        function onFileWritten(written) {
            if (root._norm(written) !== root._norm(root.path)) return;
            mtimePoll.lastMtime = __NutstyBridge.checkFileMtime(root.path);
            root.reload();
            root.fileChanged();
        }
    }

    Timer {
        id: mtimePoll
        interval: 1500
        repeat: true
        running: root.watchChanges && root.path !== ""
        property string lastMtime: ""
        onTriggered: {
            if (typeof __NutstyBridge !== "undefined" && __NutstyBridge && __NutstyBridge.checkFileMtime) {
                var m = __NutstyBridge.checkFileMtime(root.path);
                if (m && m !== lastMtime) {
                    lastMtime = m;
                    root.reload();
                    root.fileChanged();
                }
            }
        }
    }
}
