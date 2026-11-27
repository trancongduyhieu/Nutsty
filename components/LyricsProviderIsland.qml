import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell.Io
import "."
import "lyrics_offset_logic.js" as LyricsOffset

// Lyrics source + offset controls for the center notch (liner's LyricsProviderIsland):
//   <  Source 1/4 v  >  |  -  (clock) +0.1s  +
// Every source is probed in the background for the playing song (the same --probe the track menu
// uses); only sources that found lyrics are listed. The offset part hides for unsynced lyrics.
RowLayout {
    id: root
    property var track: null
    property string trackVid: ""
    property string appDir: ""
    property real totalDuration: 0
    // the source tag of the lyrics on screen ("LRCLIB", "Apple Music", ...)
    property string currentSourceTag: ""
    property bool synced: false
    property int offsetMs: 0
    property color accentColor: "#ffffff"
    // probing only runs while the island can be seen
    property bool active: false

    signal sourcePicked(string key)
    signal offsetRequested(int ms)

    spacing: 2
    height: 26

    readonly property var sourceOptions: [
        { key: "youlyplus", name: "YouLyPlus", tag: "Apple Music (YouLyPlus)" },
        { key: "simpmusic", name: "SimpMusic", tag: "SimpMusic" },
        { key: "betterlyrics", name: "Apple Music", tag: "Apple Music" },
        { key: "spotify", name: "Spotify", tag: "Spotify" },
        { key: "lrclib", name: "LRCLIB", tag: "LRCLIB" },
        { key: "kugou", name: "KuGou", tag: "KuGou" },
        { key: "netease", name: "NetEase", tag: "NetEase Music" },
        { key: "youtube", name: I18n.tr("Phụ đề YouTube", "YouTube Subtitles"), tag: "YouTube" }
    ]
    property var probeStates: ({})
    property string probeKey: ""
    readonly property var available: {
        var out = [];
        for (var i = 0; i < sourceOptions.length; ++i) {
            var st = probeStates[sourceOptions[i].key];
            if (st && st.status === "ok") out.push(sourceOptions[i]);
        }
        return out;
    }
    readonly property string currentKey: {
        for (var i = 0; i < sourceOptions.length; ++i)
            if (sourceOptions[i].tag === currentSourceTag) return sourceOptions[i].key;
        return "";
    }
    readonly property int currentIndex: {
        for (var i = 0; i < available.length; ++i) if (available[i].key === currentKey) return i;
        return -1;
    }
    readonly property string currentName: {
        for (var i = 0; i < sourceOptions.length; ++i) if (sourceOptions[i].key === currentKey) return sourceOptions[i].name;
        return currentSourceTag;
    }
    readonly property bool hasMultiple: available.length > 1
    // eases in as the notch widens around it
    // shown: whether the owner wants it. It fades in while the notch widens around it, and on the
    // way out fades first, staying in the row until gone, so the notch closes after it
    property bool shown: false
    visible: shown || opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 340 : 170; easing.type: Easing.OutCubic } }

    function step(delta) {
        if (!hasMultiple) return;
        var i = currentIndex < 0 ? 0 : (currentIndex + delta + available.length) % available.length;
        root.sourcePicked(available[i].key);
    }

    function startProbe() {
        var t = root.track;
        var title = t ? (t.title || t.name || "") : "";
        if (!root.active || title === "") return;
        var key = title + "|" + (t.artist || "");
        if (key === root.probeKey) return;
        root.probeKey = key;
        var st = {};
        for (var i = 0; i < sourceOptions.length; ++i) st[sourceOptions[i].key] = { status: "checking" };
        root.probeStates = st;
        probeProc.running = false;
        probeProc.command = ["python3", "-u", root.appDir + "/backend/lyrics_helper.py", "--probe", title, t.artist || "",
                             root.trackVid, root.totalDuration > 1 ? String(Math.round(root.totalDuration)) : ""];
        probeProc.running = true;
    }
    onActiveChanged: if (active) Qt.callLater(startProbe)
    onTrackChanged: { providerMenu.close(); offsetMenu.close(); Qt.callLater(startProbe); }

    Process {
        id: probeProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var obj;
                try { obj = JSON.parse(data); } catch (e) { return; }
                if (!obj || !obj.key) return;
                var st = Object.assign({}, root.probeStates);
                st[obj.key] = { status: obj.status === "ok" ? "ok" : "none" };
                root.probeStates = st;
            }
        }
    }

    component NotchIconButton: Rectangle {
        id: nb
        property string icon: ""
        property real iconRotation: 0
        property int iconSize: 14
        property string tip: ""
        signal clicked()
        Layout.preferredWidth: 26; Layout.preferredHeight: 26
        radius: 8
        color: nbH.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: nbH }
        ToolTip.visible: nbH.hovered && nb.tip !== ""
        ToolTip.text: nb.tip
        ToolTip.delay: 400
        AppIcon {
            anchors.centerIn: parent
            source: nb.icon
            iconSize: nb.iconSize
            rotation: nb.iconRotation
            color: "#ffffff"
            opacity: nbH.hovered ? 1.0 : 0.7
            scale: nbM.pressed ? 0.9 : 1.0
        }
        MouseArea { id: nbM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nb.clicked() }
    }

    NotchIconButton {
        visible: root.hasMultiple
        icon: "../assets/icons/material/ms-expand_more.svg"
        iconRotation: 90
        tip: I18n.tr("Nguồn trước", "Previous source")
        onClicked: root.step(-1)
    }

    // Source name, n/total and a caret: opens the list
    Rectangle {
        id: nameBtn
        Layout.preferredHeight: 26
        Layout.preferredWidth: nameRow.implicitWidth + 16
        radius: 8
        color: (nameH.hovered && root.hasMultiple) || providerMenu.opened
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: nameH }
        Row {
            id: nameRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentName !== "" ? root.currentName : I18n.tr("Đang tìm lời...", "Finding lyrics...")
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 120)
            }
            Text {
                visible: root.hasMultiple && root.currentIndex >= 0
                anchors.verticalCenter: parent.verticalCenter
                text: (root.currentIndex + 1) + "/" + root.available.length
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: "monospace"
                font.pixelSize: 10
            }
            AppIcon {
                visible: root.hasMultiple
                anchors.verticalCenter: parent.verticalCenter
                source: "../assets/icons/material/ms-expand_more.svg"
                iconSize: 13
                color: "#ffffff"
                opacity: 0.55
                rotation: providerMenu.opened ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 150 } }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: root.hasMultiple ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.hasMultiple) { offsetMenu.close(); providerMenu.opened ? providerMenu.close() : providerMenu.open(); }
        }

        Popup {
            id: providerMenu
            y: parent.height + 10
            x: 0
            padding: 4
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            enter: Transition { ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 120; easing.type: Easing.OutCubic } } }
            exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }
            background: Rectangle {
                radius: 12
                color: Qt.rgba(0.04, 0.04, 0.05, 0.92)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
            }
            contentItem: Column {
                spacing: 2
                Repeater {
                    model: root.available
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool current: modelData.key === root.currentKey
                        width: Math.max(160, optRow.implicitWidth + 20)
                        height: 34
                        radius: 8
                        color: current ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                             : (optH.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                        HoverHandler { id: optH }
                        RowLayout {
                            id: optRow
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 12
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: current || optH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.72)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: current ? Font.DemiBold : Font.Normal
                            }
                            AppIcon {
                                visible: current
                                source: "../assets/icons/material/ms-check.svg"
                                iconSize: 15
                                color: "#ffffff"
                            }
                            Text {
                                visible: !current
                                text: String(index + 1)
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { providerMenu.close(); if (!current) root.sourcePicked(modelData.key); }
                        }
                    }
                }
            }
        }
    }

    NotchIconButton {
        visible: root.hasMultiple
        icon: "../assets/icons/material/ms-expand_more.svg"
        iconRotation: -90
        tip: I18n.tr("Nguồn tiếp theo", "Next source")
        onClicked: root.step(1)
    }

    Rectangle {
        visible: root.synced
        Layout.preferredWidth: 1; Layout.preferredHeight: 14
        Layout.leftMargin: 2; Layout.rightMargin: 2
        color: Qt.rgba(1, 1, 1, 0.15)
    }

    NotchIconButton {
        visible: root.synced
        icon: "../assets/icons/material/ms-remove.svg"
        iconSize: 13
        tip: I18n.tr("Lời sớm hơn (-0,1 giây)", "Earlier (-0.1s)")
        onClicked: root.offsetRequested(root.offsetMs - 100)
    }

    // Offset badge: opens the fine-tune panel
    Rectangle {
        visible: root.synced
        Layout.preferredHeight: 26
        Layout.preferredWidth: badgeRow.implicitWidth + 12
        radius: 8
        color: badgeH.hovered || offsetMenu.opened ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: badgeH }
        ToolTip.visible: badgeH.hovered && !offsetMenu.opened
        ToolTip.text: I18n.tr("Lệch thời gian lời", "Lyrics offset")
        ToolTip.delay: 400
        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 4
            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                source: "../assets/icons/material/ms-schedule.svg"
                iconSize: 13
                color: "#ffffff"
                opacity: root.offsetMs !== 0 ? 1.0 : 0.5
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: LyricsOffset.formatBadge(root.offsetMs)
                color: root.offsetMs !== 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
                font.family: "monospace"
                font.pixelSize: 12
                font.weight: root.offsetMs !== 0 ? Font.DemiBold : Font.Medium
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { providerMenu.close(); offsetMenu.opened ? offsetMenu.close() : offsetMenu.open(); }
        }

        LyricsOffsetPanel {
            id: offsetMenu
            y: parent.height + 10
            x: parent.width - width
            offsetMs: root.offsetMs
            accentColor: root.accentColor
            onOffsetRequested: ms => root.offsetRequested(ms)
        }
    }

    NotchIconButton {
        visible: root.synced
        icon: "../assets/icons/material/ms-add.svg"
        iconSize: 13
        tip: I18n.tr("Lời muộn hơn (+0,1 giây)", "Later (+0.1s)")
        onClicked: root.offsetRequested(root.offsetMs + 100)
    }
}
