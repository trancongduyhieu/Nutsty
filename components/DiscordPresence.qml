import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Discord Rich Presence: shows "Listening to Nutsty" with the song, artist, artwork and time on
// the user's Discord profile. The local Discord app is reached by bin/nutsty-discord (Rust), which
// stays up while the switch is on and takes one JSON line per change on stdin; it skips updates
// that change nothing visible, keeps under Discord's rate limit and retries while Discord is closed.
Item {
    id: root

    property bool active: false
    property string appDir: ""
    property var track: null
    property string coverUrl: ""
    property bool playing: false
    property real position: 0
    property real duration: 0

    // "off" | "idle" | "waiting" (Discord not open) | "live" (through the Discord app)
    // | "live_web" (through the signed-in account, no Discord app needed)
    property string status: "off"

    // "Sign in with Discord": the account used when the Discord app is not on this computer
    property string accountName: ""
    property string accountAvatar: ""
    property bool signedIn: false
    property bool signingIn: false
    // "" | "port" | "denied" | "timeout" | "network"
    property string loginError: ""

    signal openUrlRequested(string url)

    function login() {
        if (!root.active || !helper.running) return;
        root.loginError = "";
        root.signingIn = true;
        helper.write(JSON.stringify({ login: true, lang: I18n.locale === "en" ? "en" : "vi" }) + "\n");
    }

    function cancelLogin() {
        if (helper.running) helper.write("{\"login_cancel\":true}\n");
        root.signingIn = false;
    }

    function logout() {
        if (helper.running) helper.write("{\"logout\":true}\n");
        root.signedIn = false;
        root.accountName = "";
        root.accountAvatar = "";
    }

    // after the switch goes off, the helper stays a moment to take the status down itself
    property bool draining: false

    function videoIdOf(trk) {
        if (!trk) return "";
        var raw = trk.videoId || (trk.path && String(trk.path).indexOf("ytdl://") === 0 ? String(trk.path).substring(7) : "");
        var id = String(raw || "").replace(/^yt_/, "").trim();
        return /^[A-Za-z0-9_-]{11}$/.test(id) ? id : "";
    }

    function report() {
        var t = root.track;
        if (!t) return { clear: true };
        var title = t.title || t.name || "";
        var artist = t.artist || t.author || "";
        if (Array.isArray(artist)) artist = artist.map(function(a) { return a && a.name ? a.name : a; }).join(", ");
        var vid = root.videoIdOf(t);
        return {
            details: String(title),
            state: String(artist || ""),
            large_text: String(t.album && typeof t.album === "object" ? (t.album.name || "") : (t.album || title)),
            small_text: root.playing ? "Nutsty" : I18n.tr("Đang tạm dừng", "Paused"),
            cover: root.coverUrl || "",
            button_label: vid ? I18n.tr("Nghe trên YouTube Music", "Listen on YouTube Music") : "",
            button_url: vid ? "https://music.youtube.com/watch?v=" + vid : "",
            position: root.position,
            duration: root.duration,
            playing: root.playing
        };
    }

    // the helper runs while the switch is on, plus the short drain after it goes off
    function syncHelper() {
        var want = (root.active || root.draining) && root.appDir !== "";
        if (helper.running !== want) helper.running = want;
    }

    function push() {
        if (!root.active || !helper.running) return;
        helper.write(JSON.stringify(root.report()) + "\n");
    }

    onActiveChanged: {
        if (root.active) {
            root.draining = false;
            drainTimer.stop();
            root.status = "idle";
            root.syncHelper();
            Qt.callLater(root.push);
        } else if (helper.running) {
            helper.write("{\"clear\":true}\n");
            root.draining = true;
            drainTimer.restart();
            root.status = "off";
            root.signingIn = false;
        }
    }
    onDrainingChanged: root.syncHelper()
    onAppDirChanged: root.syncHelper()
    onTrackChanged: root.push()
    onPlayingChanged: root.push()
    onCoverUrlChanged: root.push()

    Process {
        id: helper
        command: [root.appDir + "/bin/nutsty-discord"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    var msg = JSON.parse(data);
                    if (!msg) return;
                    if (msg.status && root.active) root.status = msg.status;
                    if (msg.hasOwnProperty("account")) {
                        root.signedIn = msg.account !== null;
                        root.accountName = msg.account && msg.account.name ? String(msg.account.name) : "";
                        root.accountAvatar = msg.account && msg.account.avatar ? String(msg.account.avatar) : "";
                        if (root.signedIn) { root.signingIn = false; root.loginError = ""; }
                    }
                    if (msg.open_url) root.openUrlRequested(String(msg.open_url));
                    if (msg.login === "failed") {
                        root.signingIn = false;
                        root.loginError = String(msg.reason || "network");
                    }
                } catch (e) {}
            }
        }
        onRunningChanged: if (running) firstPush.restart()
        onExited: (code, status) => {
            root.signingIn = false;
            if (root.active) {
                root.status = "waiting";
                restartTimer.restart();
            }
        }
    }

    // a fresh helper needs a moment before its stdin is open
    Timer { id: firstPush; interval: 300; onTriggered: root.push() }

    // seeks and slow drift: the helper only passes on what changed by more than a couple of seconds
    Timer {
        interval: 2000
        repeat: true
        running: root.active && helper.running && root.track !== null
        onTriggered: root.push()
    }

    Timer {
        id: drainTimer
        interval: 1500
        onTriggered: root.draining = false
    }

    // the helper died on its own (crash, killed): bring it back, but not in a tight loop
    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: root.syncHelper()
    }
}
