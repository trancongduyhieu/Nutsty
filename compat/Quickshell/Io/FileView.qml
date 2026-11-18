import QtQuick

Item {
    id: root
    property string path: ""
    property bool watchChanges: false
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

    Timer {
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
