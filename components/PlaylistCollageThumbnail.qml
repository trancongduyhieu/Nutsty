import QtQuick
import "."

Item {
    id: root

    property string playlistCover: ""
    property string customCover: ""
    property var tracks: []
    property string playlistTitle: ""
    property real radius: 12
    property color accentColor: Theme.accent

    implicitWidth: 160
    implicitHeight: 160

    function cleanUrl(s) {
        if (!s || typeof s !== "string") return "";
        var str = s.trim();
        if (str.startsWith("/") && !str.startsWith("file://")) return "file://" + str;
        return str;
    }

    readonly property string effectiveCover: cleanUrl(customCover) || cleanUrl(playlistCover)
    readonly property bool hasEffectiveCover: effectiveCover !== ""

    readonly property var validTracks: {
        if (!tracks) return [];
        var res = [];
        var len = tracks.length || 0;
        for (var i = 0; i < len; i++) {
            var t = tracks[i];
            if (t && (t.image || t.cover || t.thumbnail)) {
                res.push(t);
            }
        }
        return res;
    }

    readonly property var collageTracks: {
        if (hasEffectiveCover) return [];
        return validTracks.slice(0, 4);
    }

    readonly property bool isCollage: !hasEffectiveCover && validTracks.length >= 4
    readonly property bool isSingleTrackCover: !hasEffectiveCover && validTracks.length >= 1 && validTracks.length < 4
    readonly property bool isEmptyPlaylist: !hasEffectiveCover && validTracks.length === 0

    // Deterministic Gradient Palette based on title hash (SimpMusic Skill #68)
    readonly property var gradientColors: {
        var str = root.playlistTitle || "Nutsty";
        var hash = 0;
        for (var i = 0; i < str.length; i++) {
            hash = str.charCodeAt(i) + ((hash << 5) - hash);
        }
        var palettes = [
            { c1: "#312e81", c2: "#4338ca" }, // Indigo
            { c1: "#4c1d95", c2: "#6d28d9" }, // Purple
            { c1: "#701a75", c2: "#a21caf" }, // Fuchsia
            { c1: "#831843", c2: "#be185d" }, // Pink
            { c1: "#14532d", c2: "#15803d" }, // Emerald
            { c1: "#134e4a", c2: "#0f766e" }, // Teal
            { c1: "#1e3a8a", c2: "#1d4ed8" }, // Blue
            { c1: "#7c2d12", c2: "#c2410c" }  // Orange Amber
        ];
        return palettes[Math.abs(hash) % palettes.length];
    }

    Item {
        id: container
        anchors.fill: parent

        // Base foundation
        Rectangle {
            anchors.fill: parent
            color: "#181920"
        }

        // 1. Direct Cover (customCover or playlistCover)
        Image {
            id: directCoverImg
            anchors.fill: parent
            source: root.hasEffectiveCover ? root.effectiveCover : ""
            fillMode: Image.PreserveAspectCrop
            visible: root.hasEffectiveCover
            asynchronous: true
            cache: true
            sourceSize: Qt.size(400, 400)
        }

        // 2. 2x2 Collage Grid (Reactive to collageTracks model)
        Grid {
            id: collageGrid
            anchors.fill: parent
            columns: 2
            rows: 2
            spacing: 0
            visible: root.isCollage

            Repeater {
                model: root.collageTracks
                delegate: Image {
                    width: root.width / 2
                    height: root.height / 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(200, 200)
                    source: modelData ? root.cleanUrl(modelData.image || modelData.cover || modelData.thumbnail || "") : ""
                }
            }
        }

        // 3. Single Track Cover (1-3 tracks)
        Image {
            id: singleTrackImg
            anchors.fill: parent
            source: root.isSingleTrackCover && root.validTracks.length > 0 ? root.cleanUrl(root.validTracks[0].image || root.validTracks[0].cover || root.validTracks[0].thumbnail || "") : ""
            fillMode: Image.PreserveAspectCrop
            visible: root.isSingleTrackCover
            asynchronous: true
            cache: true
            sourceSize: Qt.size(400, 400)
        }

        // 4. Fallback Generative Gradient + Monogram (When empty or images not ready)
        Rectangle {
            anchors.fill: parent
            visible: root.isEmptyPlaylist || (root.hasEffectiveCover && directCoverImg.status !== Image.Ready && directCoverImg.status !== Image.Loading)
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.gradientColors.c1 }
                GradientStop { position: 1.0; color: root.gradientColors.c2 }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6

                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "../assets/icons/folder-music-symbolic.svg"
                    iconSize: Math.max(22, root.width * 0.22)
                    color: Qt.rgba(255, 255, 255, 0.85)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        var t = (root.playlistTitle || "N").trim();
                        return t.length > 0 ? t.charAt(0).toUpperCase() : "N";
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(16, root.width * 0.16)
                    font.weight: Font.DemiBold
                    color: Qt.rgba(255, 255, 255, 0.75)
                }
            }
        }
    }

    RoundedClip {
        anchors.fill: parent
        target: container
        radius: root.radius
    }

    // 1px Hairline border overlay
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.color: Qt.rgba(255, 255, 255, 0.12)
        border.width: 1
        z: 2
    }
}
