import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string libraryPath: (typeof win !== "undefined" && win.appDir)
        ? (win.appDir + "/library.json")
        : ((Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal")) + "/library.json")

    property var playlists: []
    property var allTracks: []
    signal loaded()

    FileView {
        id: libFileView
        path: root.libraryPath
        onLoadedChanged: {
            if (loaded) root.parseLibrary();
        }
    }

    function reload() {
        libFileView.reload();
        root.parseLibrary();
    }

    function parseLibrary() {
        var raw = libFileView.text();
        if (!raw || raw.trim() === "") return;
        try {
            var parsed = JSON.parse(raw);
            var validTracks = [];
            var rawTracks = [];
            if (Array.isArray(parsed)) {
                rawTracks = parsed;
            } else if (parsed && typeof parsed === "object") {
                if (parsed.playlists) root.playlists = parsed.playlists;
                if (parsed.tracks) rawTracks = parsed.tracks;
            }

            validTracks = rawTracks.filter(function(t) {
                if (!t || !t.path) return false;
                var p = String(t.path);
                if (p.startsWith("ytdl://") || p.startsWith("http:") || p.startsWith("https:")) return true;
                if (Qt.platform.os === "windows" && p.startsWith("/home/")) return false;
                if (Qt.platform.os === "linux" && (p.indexOf(":\\") !== -1 || p.startsWith("C:/") || p.startsWith("c:/"))) return false;
                return true;
            });

            root.allTracks = validTracks;
            console.log("LibraryLoader successfully loaded tracks count:", root.allTracks.length);
            root.loaded();
        } catch(e) {
            console.log("Failed to parse library:", e);
        }
    }

    Component.onCompleted: {
        root.parseLibrary();
    }
}
