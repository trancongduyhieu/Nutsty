import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

// Transport block for the Now Playing view (the playerbar is unrendered while it is open).
// SimpMusic-like and deliberately monochrome: everything is white, the play button never takes the accent.
//   seek bar
//   0:42 ........ OPUS • 160 kbps ........ 3:15
//   shuffle  prev  (play)  next  repeat
//   [vol-] ------------------------ [vol+]  (same width as the transport row)
ColumnLayout {
    id: ctl

    property real currentTime: 0
    property real totalDuration: 1
    property bool isPlaying: false
    property bool isLoadingAudio: false
    property bool isShuffle: false
    property bool isRepeat: false
    property real volume: 100
    property string qualityText: ""
    property bool mixing: false   // AutoMix is blending: "Cooking" with a light sweep replaces the specs

    signal seekRequested(real seconds)
    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal shuffleClicked()
    signal repeatClicked()
    signal volumeChangeRequested(real newVol)

    readonly property string iconDir: "../assets/icons/material/"
    spacing: 8

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0;
        var m = Math.floor(sec / 60), s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }
    readonly property real safeTotal: totalDuration > 0 ? totalDuration : 1

    // ---------------------------------------------------------------- seek bar
    Item {
        id: seekArea
        Layout.fillWidth: true
        Layout.preferredHeight: 16
        property real dragFrac: -1
        readonly property real frac: dragFrac >= 0 ? dragFrac : Math.max(0, Math.min(1, ctl.currentTime / ctl.safeTotal))
        readonly property bool active: seekMouse.containsMouse || seekMouse.pressed

        Rectangle {
            id: seekTrack
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: seekArea.active ? 6 : 4
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.18)
            Behavior on height { NumberAnimation { duration: 120 } }
            Rectangle {
                width: parent.width * seekArea.frac
                height: parent.height
                radius: parent.radius
                color: "#ffffff"
            }
        }
        Rectangle {
            width: 14; height: 14; radius: 7
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: seekTrack.width * seekArea.frac - width / 2
            scale: seekArea.active ? 1.0 : 0.0
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        }
        MouseArea {
            id: seekMouse
            anchors.fill: parent
            anchors.topMargin: -6; anchors.bottomMargin: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function fracAt(x) { return Math.max(0, Math.min(1, x / width)); }
            onPressed: mouse => seekArea.dragFrac = fracAt(mouse.x)
            onPositionChanged: mouse => { if (pressed) seekArea.dragFrac = fracAt(mouse.x); }
            onReleased: mouse => {
                ctl.seekRequested(fracAt(mouse.x) * ctl.safeTotal);
                seekArea.dragFrac = -1;
            }
            onCanceled: seekArea.dragFrac = -1
        }
    }

    // Times on the edges, audio quality / tech specs in the middle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 16
        Text {
            id: elapsedText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ctl.fmt(seekArea.frac * ctl.safeTotal)
            font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Qt.rgba(1, 1, 1, 0.6)
        }
        Text {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 2 * Math.max(elapsedText.width, totalText.width) - 24)
            horizontalAlignment: Text.AlignHCenter
            text: ctl.qualityText
            opacity: ctl.mixing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            visible: text.length > 0 && opacity > 0.01
            elide: Text.ElideRight
            font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold
            font.letterSpacing: 0.4
            color: Qt.rgba(1, 1, 1, 0.5)
        }
        // "Cooking" (AutoMix is blending): the word rests dim and a soft band of light sweeps across it left to right
        // (text_shimmer.frag), so each letter lights up and dims again on every pass
        ShimmerText {
            id: mixLabel
            anchors.centerIn: parent
            text: I18n.tr("Cooking", "Cooking")
            running: ctl.mixing
            opacity: ctl.mixing ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        Text {
            id: totalText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: ctl.fmt(ctl.totalDuration)
            font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Qt.rgba(1, 1, 1, 0.6)
        }
    }

    // ------------------------------------------------------------- transport
    RowLayout {
        id: transportRow
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 2
        spacing: 16

        NowPlayingCtlButton {
            icon: ctl.iconDir + "ms-shuffle.svg"
            toggle: true
            on: ctl.isShuffle
            size: 40
            onClicked: ctl.shuffleClicked()
        }
        NowPlayingCtlButton {
            icon: ctl.iconDir + "ms-skip_previous-fill.svg"
            size: 48
            iconScale: 0.7
            onClicked: ctl.prevClicked()
        }
        Rectangle {
            id: playBtn
            width: 64; height: 64; radius: 32
            color: "#ffffff"
            scale: playMouse.pressed ? 0.94 : (playH.hovered ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            HoverHandler { id: playH }
            CircularSpinner {
                anchors.centerIn: parent
                visible: ctl.isLoadingAudio
                running: ctl.isLoadingAudio
                size: 28
                strokeWidth: 2.5
                color: "#111111"
            }
            AppIcon {
                anchors.centerIn: parent
                visible: !ctl.isLoadingAudio
                source: ctl.iconDir + (ctl.isPlaying ? "ms-pause-fill.svg" : "ms-play_arrow-fill.svg")
                iconSize: 38
                color: "#111111"
            }
            MouseArea { id: playMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ctl.playPauseClicked() }
        }
        NowPlayingCtlButton {
            icon: ctl.iconDir + "ms-skip_next-fill.svg"
            size: 48
            iconScale: 0.7
            onClicked: ctl.nextClicked()
        }
        NowPlayingCtlButton {
            icon: ctl.iconDir + (ctl.isRepeat ? "ms-repeat_one.svg" : "ms-repeat.svg")
            toggle: true
            on: ctl.isRepeat
            size: 40
            onClicked: ctl.repeatClicked()
        }
    }

    // ---------------------------------------------------------------- volume
    // Same width as the transport row, mirrored so it reads centred: a quiet speaker under shuffle
    // (mute toggle), a loud speaker under repeat (+10). The bar runs between the two glyph edges.
    Item {
        id: volRow
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: transportRow.implicitWidth
        Layout.preferredHeight: 30
        Layout.topMargin: 2
        // shuffle/repeat: 40px buttons with a 24px glyph (iconScale 0.6) -> glyph inset 8px
        readonly property real glyphInset: 8
        readonly property real glyphEnd: 40 - glyphInset

        NowPlayingCtlButton {
            size: 30
            iconScale: 0.62
            x: 20 - width / 2
            anchors.verticalCenter: parent.verticalCenter
            icon: ctl.iconDir + (ctl.volume <= 0.5 ? "ms-volume_off-fill.svg" : "ms-volume_down-fill.svg")
            property real lastVol: 60
            onClicked: {
                if (ctl.volume > 0.5) { lastVol = ctl.volume; ctl.volumeChangeRequested(0); }
                else ctl.volumeChangeRequested(lastVol > 0.5 ? lastVol : 60);
            }
        }
        NowPlayingCtlButton {
            size: 30
            iconScale: 0.62
            x: volRow.width - 20 - width / 2
            anchors.verticalCenter: parent.verticalCenter
            icon: ctl.iconDir + "ms-volume_up-fill.svg"
            onClicked: ctl.volumeChangeRequested(Math.min(100, ctl.volume + 10))
        }
        Item {
            id: volArea
            x: volRow.glyphEnd
            width: volRow.width - 2 * volRow.glyphEnd
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            property real dragFrac: -1
            readonly property real frac: dragFrac >= 0 ? dragFrac : Math.max(0, Math.min(1, ctl.volume / 100))
            readonly property bool active: volMouse.containsMouse || volMouse.pressed
            Rectangle {
                id: volTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: volArea.active ? 6 : 4
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.18)
                Behavior on height { NumberAnimation { duration: 120 } }
                Rectangle {
                    width: parent.width * volArea.frac; height: parent.height; radius: parent.radius
                    color: Qt.rgba(1, 1, 1, volArea.active ? 1.0 : 0.85)
                }
            }
            MouseArea {
                id: volMouse
                anchors.fill: parent
                anchors.topMargin: -6; anchors.bottomMargin: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function fracAt(x) { return Math.max(0, Math.min(1, x / width)); }
                onPressed: mouse => { volArea.dragFrac = fracAt(mouse.x); ctl.volumeChangeRequested(volArea.dragFrac * 100); }
                onPositionChanged: mouse => { if (pressed) { volArea.dragFrac = fracAt(mouse.x); ctl.volumeChangeRequested(volArea.dragFrac * 100); } }
                onReleased: volArea.dragFrac = -1
                onCanceled: volArea.dragFrac = -1
                onWheel: wheel => ctl.volumeChangeRequested(Math.max(0, Math.min(100, ctl.volume + (wheel.angleDelta.y > 0 ? 5 : -5))))
            }
        }
    }
}
