import QtQuick
import Quickshell
import "."

Item {
    id: root

    // =========================================================================
    // Interface (Clean Seam for Sleep Timer Subsystem)
    // =========================================================================
    property bool isActive: false
    property int remainingSeconds: 0
    property string mode: "" // "duration" | "end_of_track"
    property bool fadeTriggered: false
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    signal timerFinished()

    function startDuration(minutes) {
        if (!minutes || minutes <= 0) {
            cancel();
            return;
        }
        root.mode = "duration";
        root.remainingSeconds = minutes * 60;
        root.fadeTriggered = false;
        root.isActive = true;
    }

    function startEndOfTrack() {
        root.mode = "end_of_track";
        root.remainingSeconds = Math.max(0, Math.round(root.totalDuration - root.currentTime));
        root.fadeTriggered = false;
        root.isActive = true;
    }

    function cancel() {
        root.isActive = false;
        root.remainingSeconds = 0;
        root.mode = "";
        root.fadeTriggered = false;
    }

    // =========================================================================
    // Implementation (1000ms Countdown & 5s Cosine Fade Out)
    // =========================================================================
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: root.isActive
        onTriggered: {
            if (!root.isActive) return;

            if (root.mode === "duration") {
                if (root.remainingSeconds > 0) {
                    root.remainingSeconds--;
                }

                // Trigger 5-second Cosine Fade at 5s remaining
                if (root.remainingSeconds === 5 && !root.fadeTriggered) {
                    root.fadeTriggered = true;
                    Quickshell.execDetached(["python3", root.appDir + "/backend/player_daemon.py", "fade_out_and_pause", "5.0"]);
                } else if (root.remainingSeconds <= 0) {
                    root.cancel();
                    root.timerFinished();
                    Quickshell.execDetached(["python3", root.appDir + "/backend/player_daemon.py", "pause"]);
                }
            } else if (root.mode === "end_of_track") {
                root.remainingSeconds = Math.max(0, Math.round(root.totalDuration - root.currentTime));
                if (root.totalDuration > 5) {
                    var remaining = root.totalDuration - root.currentTime;
                    if (remaining <= 5.0 && remaining > 0.4 && !root.fadeTriggered) {
                        root.fadeTriggered = true;
                        Quickshell.execDetached(["python3", root.appDir + "/backend/player_daemon.py", "fade_out_and_pause", String(Math.max(1.0, remaining))]);
                    }
                }
            }
        }
    }
}
