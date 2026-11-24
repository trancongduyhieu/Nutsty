import QtQuick
import QtQuick.Layouts
import "."

// "Continue from another device": the song another device of this account stopped at, and where.
// Filled by AccountSync.resumeOffered; Continue plays it and seeks, Later / close / timeout dismiss it.
Item {
    id: root
    width: 390
    height: 118
    visible: opacity > 0
    opacity: isShown ? 1 : 0
    z: 9999

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    property bool isShown: false
    property var progress: null
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    readonly property var track: progress && progress.track ? progress.track : null

    signal continueRequested(var progress)
    signal dismissed(var progress)

    function clock(sec) {
        var s = Math.max(0, Math.floor(Number(sec) || 0));
        var m = Math.floor(s / 60);
        s = s % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        id: autoDismissTimer
        interval: 30000
        repeat: false
        running: root.isShown && !cardHover.hovered
        onTriggered: root.dismiss()
    }

    function showProgress(p) {
        root.progress = p;
        root.isShown = true;
        autoDismissTimer.restart();
    }

    function dismiss() {
        if (!root.isShown) return;
        root.isShown = false;
        autoDismissTimer.stop();
        root.dismissed(root.progress);
    }

    function accept() {
        var p = root.progress;
        root.isShown = false;
        autoDismissTimer.stop();
        if (p) root.continueRequested(p);
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.tint(Qt.rgba(0.07, 0.07, 0.09, 0.94), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16))
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
        border.width: 1

        HoverHandler { id: cardHover }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            RoundedImage {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                radius: 10
                source: root.track ? (root.track.cover || root.track.image || root.track.artUrl || root.track.thumbnail || "") : ""
                fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                fallbackIconColor: root.accentColor
                placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Nghe tiếp từ máy khác", "Continue from another device")
                        color: root.accentColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: closeHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent"
                        HoverHandler { id: closeHover }
                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 9
                            color: closeHover.hovered ? "#ffffff" : "#a1a1aa"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismiss()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.track ? (root.track.title || root.track.name || I18n.tr("Bài hát", "Track")) : I18n.tr("Bài hát", "Track")
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    readonly property string who: root.track ? (root.track.artist || root.track.author || "") : ""
                    readonly property string at: root.clock(root.progress ? root.progress.position : 0)
                    text: who !== ""
                          ? I18n.tr(who + " · dừng ở " + at, who + " · stopped at " + at)
                          : I18n.tr("Dừng ở " + at, "Stopped at " + at)
                    color: "#a1a1aa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 28
                        radius: 8
                        color: goHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: goHover }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            AppIcon {
                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 11
                                color: "#ffffff"
                            }
                            Text {
                                text: I18n.tr("Nghe tiếp", "Continue")
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.accept()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 28
                        radius: 8
                        color: laterHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: laterHover }

                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Để sau", "Later")
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismiss()
                        }
                    }
                }
            }
        }
    }
}
