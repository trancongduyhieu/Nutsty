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
    // Length the running duration timer was started with (drives the countdown ring)
    property int totalSeconds: 0
    property string mode: "" // "duration" | "end_of_track"
    // How the music fades when a duration timer runs out:
    // "none" = just pauses, "final" = fades over the last 10 s, "entire" = fades along the whole timer
    property string fade: "final"
    property bool fadeTriggered: false
    // True while a whole-timer fade owns mpv's volume; the volume controls are ignored meanwhile
    readonly property bool volumeLocked: isActive && mode === "duration" && fade === "entire" && fadeTriggered
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    readonly property int finalFadeSeconds: 10

    signal timerFinished()

    function _daemon(args) {
        Quickshell.execDetached(["python3", root.appDir + "/backend/player_daemon.py"].concat(args));
    }

    function _startFade(seconds) {
        root.fadeTriggered = true;
        root._daemon(["fade_out_and_pause", String(Math.max(1, seconds))]);
    }

    function startDuration(seconds, fadeMode) {
        if (!seconds || seconds <= 0) {
            cancel();
            return;
        }
        if (root.fadeTriggered) root._daemon(["cancel_fade"]);
        if (fadeMode === "none" || fadeMode === "final" || fadeMode === "entire") root.fade = fadeMode;
        root.mode = "duration";
        root.totalSeconds = seconds;
        root.remainingSeconds = seconds;
        root.fadeTriggered = false;
        root.isActive = true;
        if (root.fade === "entire") {
            root._startFade(seconds);
        } else if (root.fade === "final" && seconds <= root.finalFadeSeconds) {
            root._startFade(seconds);
        }
    }

    function startEndOfTrack() {
        if (root.fadeTriggered) root._daemon(["cancel_fade"]);
        root.mode = "end_of_track";
        root.totalSeconds = 0;
        root.remainingSeconds = Math.max(0, Math.round(root.totalDuration - root.currentTime));
        root.fadeTriggered = false;
        root.isActive = true;
    }

    // User cancel: a fade still running in the daemon is aborted and the volume restored
    function cancel() {
        if (root.isActive && root.fadeTriggered) root._daemon(["cancel_fade"]);
        root._reset();
    }

    function _reset() {
        root.isActive = false;
        root.remainingSeconds = 0;
        root.totalSeconds = 0;
        root.mode = "";
        root.fadeTriggered = false;
    }

    // =========================================================================
    // Implementation (1000ms countdown; the daemon runs the cosine volume ramp)
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

                if (root.fade === "final" && !root.fadeTriggered && root.remainingSeconds === root.finalFadeSeconds) {
                    root._startFade(root.finalFadeSeconds);
                } else if (root.remainingSeconds <= 0) {
                    // A fade ends in a pause on its own; pausing here as well covers "none" and a late ramp
                    root._reset();
                    root.timerFinished();
                    root._daemon(["pause"]);
                }
            } else if (root.mode === "end_of_track") {
                root.remainingSeconds = Math.max(0, Math.round(root.totalDuration - root.currentTime));
                if (root.totalDuration > 5) {
                    var remaining = root.totalDuration - root.currentTime;
                    if (remaining <= 5.0 && remaining > 0.4 && !root.fadeTriggered) {
                        root._startFade(remaining);
                    }
                }
            }
        }
    }
}
