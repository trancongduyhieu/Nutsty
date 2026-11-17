import QtQuick
import QtCore
import Quickshell

// History behind the bell: events worth finding again later (updates, listen-along, friends,
// import/export). Transient confirmations ("added to queue") stay toast-only.
// Saved with QtCore Settings to an .ini file, so it survives restarts on Linux and Windows; one file per profile.
QtObject {
    id: store

    property var items: []          // newest first: { id, kind, text, ts, read }
    readonly property int unread: {
        var n = 0;
        for (var i = 0; i < items.length; i++) if (!items[i].read) n++;
        return n;
    }
    readonly property int maxItems: 60

    // ~/.config/noctalia like the app's other config. StandardPaths gives a proper file URL
    // on Linux (file:///home/x) and Windows (file:///C:/Users/x) without reading env vars.
    readonly property string profile: Quickshell.env("NUTSTY_PROFILE") || ""
    readonly property string fileUrl: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString()
        + "/.config/noctalia/nutsty_notifications" + (profile ? "_" + profile : "") + ".ini"
    property Settings saved: Settings {
        location: store.fileUrl
        category: "notifications"
        property string history: "[]"
    }

    Component.onCompleted: {
        try {
            var parsed = JSON.parse(saved.history || "[]");
            if (Array.isArray(parsed)) store.items = parsed;
        } catch (e) {}
    }

    function _commit(list) {
        store.items = list.slice(0, store.maxItems);
        saved.history = JSON.stringify(store.items);
    }

    function add(kind, text) {
        if (!text) return;
        var now = Date.now();
        var list = store.items.slice();
        // The same event repeating within 12h (e.g. the update check) moves to the top, no duplicate
        for (var i = 0; i < list.length; i++) {
            if (list[i].kind === kind && list[i].text === text && now - list[i].ts < 12 * 3600 * 1000) {
                var again = list.splice(i, 1)[0];
                again.ts = now;
                again.read = false;
                list.unshift(again);
                store._commit(list);
                return;
            }
        }
        list.unshift({ id: now + "-" + Math.floor(Math.random() * 1e6), kind: kind || "info", text: text, ts: now, read: false });
        store._commit(list);
    }

    function markAllRead() {
        if (store.unread === 0) return;
        store._commit(store.items.map(function (it) { return { id: it.id, kind: it.kind, text: it.text, ts: it.ts, read: true }; }));
    }

    function remove(id) {
        store._commit(store.items.filter(function (it) { return it.id !== id; }));
    }

    function clear() { store._commit([]); }
}
