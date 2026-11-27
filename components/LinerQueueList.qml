pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."
import "queue_reorder_logic.js" as Reorder

// The whole queue as liner's drawer shows it: 68 px rows, the song playing now on a soft fill,
// and drag-to-reorder with the left button (the rows step aside, a placeholder marks the slot,
// a card follows the pointer and the list scrolls itself near its edges).
// One MouseArea over the list owns the gesture, so a row scrolled out of view mid-drag is fine.
Item {
    id: root

    property var tracks: []
    property var currentTrack: null
    property var sameTrack: function (a, b) { return a === b; }
    // Gate for scroll-to-current and the edge fade while the tab is hidden
    property bool active: true
    // The panel's frosted glass, so the dragged card can show it blurred behind the rows
    property Item backdrop: null

    signal playRequested(var track, int index)
    signal menuRequested(var track, real gx, real gy)
    signal moveRequested(int from, int to)

    readonly property int rowH: 68
    readonly property int padX: 10
    readonly property int padTop: 6
    readonly property int padBottom: 16
    readonly property int menuZone: 44

    readonly property int currentIndex: {
        if (!root.currentTrack || !root.tracks) return -1;
        for (var i = 0; i < root.tracks.length; ++i)
            if (root.sameTrack(root.tracks[i], root.currentTrack)) return i;
        return -1;
    }

    property int dragIndex: -1
    property int dropIndex: -1
    property real pointerY: 0
    property real grabOffsetY: 0
    readonly property bool dragging: dragIndex >= 0
    readonly property real rowsTop: list.originY + root.padTop

    function coverFor(trk) {
        if (!trk) return "";
        var s = trk.image || trk.artUrl || trk.cover || trk.thumbnail || "";
        if (!s && trk.videoId) s = "https://i.ytimg.com/vi/" + trk.videoId + "/hqdefault.jpg";
        if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
        return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
    }
    function rowAt(y) {
        var i = Math.floor((y + list.contentY - root.rowsTop) / root.rowH);
        return (i >= 0 && root.tracks && i < root.tracks.length) ? i : -1;
    }
    function maxContentY() { return Math.max(list.originY, list.originY + list.contentHeight - list.height); }
    function updateDrop() {
        root.dropIndex = Reorder.dropIndexFor(root.pointerY + list.contentY - root.rowsTop,
                                              root.tracks.length, root.rowH, root.dropIndex);
    }
    function positionToCurrent(animated) {
        if (root.dragging || root.currentIndex < 0 || list.height <= 0) return;
        var target = Math.min(root.maxContentY(),
            list.originY + Reorder.scrollTargetFor(root.currentIndex, root.rowH, root.padTop, list.height));
        scrollAnim.stop();
        if (!animated) { list.contentY = target; return; }
        scrollAnim.to = target;
        scrollAnim.start();
    }
    function commitDrag() {
        var from = root.dragIndex, to = root.dropIndex;
        var keepY = list.contentY;
        // Reset first: the model swap below rebuilds the rows, and they must come up unshifted
        root.dragIndex = -1;
        root.dropIndex = -1;
        if (from >= 0 && to >= 0 && from !== to) {
            root.moveRequested(from, to);
            list.contentY = Math.min(keepY, root.maxContentY());
        }
    }

    onCurrentIndexChanged: Qt.callLater(root.positionToCurrent, true)
    onActiveChanged: if (active) Qt.callLater(root.positionToCurrent, false)

    // One row's face, shared by the list rows and the card that follows the pointer
    component RowFace: Item {
        id: face
        property var track: null
        property bool current: false
        property bool hovered: false
        property bool menuHovered: false

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 16

            RoundedImage {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 8
                source: root.coverFor(face.track)
                fillMode: Image.PreserveAspectCrop
                fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                fallbackIconSize: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: face.track ? (face.track.title || face.track.name || I18n.tr("Bài hát", "Track")) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: 400
                    color: "#ffffff"
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: face.track ? (face.track.artist || face.track.artists || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: 350
                    color: Qt.rgba(1, 1, 1, 0.7)
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 8
                color: face.menuHovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/material/ms-more_vert.svg"
                    iconSize: 22
                    color: "#ffffff"
                }
            }
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.tracks
        cacheBuffer: 320
        header: Item { width: list.width; height: root.padTop }
        footer: Item { width: list.width; height: root.padBottom }

        NumberAnimation on contentY {
            id: scrollAnim
            running: false
            duration: 420
            easing.type: Easing.OutCubic
        }

        // Where the dragged song will land
        Rectangle {
            parent: list.contentItem
            z: -1
            visible: root.dragging
            x: root.padX
            y: root.rowsTop + root.dropIndex * root.rowH + 2
            width: list.width - root.padX * 2
            height: root.rowH - 4
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        delegate: Item {
            id: row
            required property int index
            required property var modelData
            width: list.width
            height: root.rowH
            opacity: root.dragIndex === row.index ? 0 : 1

            transform: Translate {
                y: Reorder.shiftFor(row.index, root.dragIndex, root.dropIndex, root.rowH)
                Behavior on y {
                    enabled: root.dragging
                    NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
                }
            }

            HoverHandler { id: rowHover; enabled: !root.dragging }

            Rectangle {
                id: rowCard
                anchors.fill: parent
                anchors.leftMargin: root.padX
                anchors.rightMargin: root.padX
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                radius: 12
                readonly property bool current: row.index === root.currentIndex
                color: current ? Qt.rgba(1, 1, 1, 0.07) : (rowHover.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                Behavior on color { ColorAnimation { duration: 160 } }

                RowFace {
                    anchors.fill: parent
                    track: row.modelData
                    current: rowCard.current
                    hovered: rowHover.hovered
                    menuHovered: rowHover.hovered && rowHover.point.position.x > row.width - root.padX - root.menuZone
                }
            }
        }

        // Owns press, click, menu and drag for every row (declared on the list, not its content)
        MouseArea {
            id: gesture
            parent: list
            anchors.fill: parent
            z: 10
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            property int pressIndex: -1
            property bool onMenu: false
            property bool dragged: false
            property real pressX: 0
            property real pressY: 0

            onPressed: mouse => {
                pressIndex = root.rowAt(mouse.y);
                onMenu = mouse.x > width - root.padX - root.menuZone;
                dragged = false;
                pressX = mouse.x;
                pressY = mouse.y;
                if (pressIndex >= 0)
                    root.grabOffsetY = mouse.y - (root.rowsTop + pressIndex * root.rowH - list.contentY);
            }
            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton) || pressIndex < 0 || onMenu) return;
                if (!root.dragging) {
                    if (!Reorder.dragStarted(pressX, pressY, mouse.x, mouse.y)) return;
                    scrollAnim.stop();
                    dragged = true;
                    root.dropIndex = pressIndex;
                    root.dragIndex = pressIndex;
                }
                root.pointerY = mouse.y;
                root.updateDrop();
            }
            onReleased: mouse => {
                if (root.dragging) root.commitDrag();
            }
            onCanceled: {
                root.dragIndex = -1;
                root.dropIndex = -1;
            }
            onClicked: mouse => {
                // The click that ends a drag does not play the song
                if (dragged || pressIndex < 0 || !root.tracks || pressIndex >= root.tracks.length) return;
                var trk = root.tracks[pressIndex];
                if (mouse.button === Qt.RightButton || onMenu) {
                    var pt = mapToItem(null, mouse.x, mouse.y);
                    root.menuRequested(trk, pt.x, pt.y);
                } else {
                    root.playRequested(trk, pressIndex);
                }
            }
        }
    }

    // Edge auto-scroll while dragging: faster the closer the pointer is to the edge
    Timer {
        interval: 16
        repeat: true
        running: root.dragging
        onTriggered: {
            var d = Reorder.autoScrollDelta(root.pointerY, 0, list.height, root.rowH, 18);
            if (d === 0) return;
            var next = Math.max(list.originY, Math.min(root.maxContentY(), list.contentY + d));
            if (next === list.contentY) return;
            list.contentY = next;
            root.updateDrop();
        }
    }

    // The song being moved, lifted off the list and following the pointer: frosted glass that
    // blurs the rows passing under it. The blur exists only while a drag is on and samples just
    // the card's own patch of the list, so idle rows cost nothing.
    Item {
        id: dragCard
        z: 100
        visible: root.dragging
        x: root.padX
        y: Math.max(-root.rowH / 2, Math.min(root.height - root.rowH / 2, root.pointerY - root.grabOffsetY + 2))
        width: list.width - root.padX * 2
        height: root.rowH - 4

        Loader {
            anchors.fill: parent
            active: root.dragging
            sourceComponent: Item {
                // What sits under the card: the panel's frosted backdrop (opaque, so the sharp rows
                // behind the card are hidden) with the list's rows on top. Both are cut to the card.
                Item {
                    id: underCard
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        visible: root.backdrop === null
                        color: Qt.rgba(0.07, 0.07, 0.08, 0.94)
                    }
                    ShaderEffectSource {
                        anchors.fill: parent
                        visible: root.backdrop !== null
                        sourceItem: root.backdrop
                        live: true
                        recursive: false
                        sourceRect: {
                            if (!root.backdrop) return Qt.rect(0, 0, 0, 0);
                            var p = dragCard.parent.mapToItem(root.backdrop, dragCard.x, dragCard.y);
                            return Qt.rect(p.x, p.y, dragCard.width, dragCard.height);
                        }
                    }
                    ShaderEffectSource {
                        anchors.fill: parent
                        sourceItem: list
                        live: true
                        recursive: false
                        sourceRect: Qt.rect(dragCard.x - list.x, dragCard.y - list.y, dragCard.width, dragCard.height)
                    }
                }
                Rectangle {
                    id: cardMask
                    anchors.fill: parent
                    radius: 12
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: underCard
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 40
                    blurMultiplier: 0.6
                    maskEnabled: true
                    maskSource: cardMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }
        }
        // Tint and hairline: liner's glass tokens, a touch lighter so the lifted card reads on top
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(70 / 255, 70 / 255, 70 / 255, 0.22)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
        }
        RowFace {
            anchors.fill: parent
            track: root.dragging && root.tracks ? root.tracks[root.dragIndex] : null
        }
    }

    ScrollEdgeFade {
        flickable: list
        when: root.active
    }
}
