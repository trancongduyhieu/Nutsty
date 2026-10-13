import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root

    // Core Properties
    property url source: ""
    property real radius: 8
    property int fillMode: Image.PreserveAspectCrop
    property bool asynchronous: true
    property bool cache: true

    // Fallback & Placeholder Properties
    property string initialsText: ""
    property bool useInitialsFallback: true
    property string fallbackIcon: ""
    property color fallbackIconColor: Theme.accent
    property int fallbackIconSize: 18
    property color placeholderColor: "#202024"

    // Optional Border Properties
    property color borderColor: "transparent"
    property real borderWidth: 0

    // Readonly status & dimensions aliases
    readonly property int status: img.status
    readonly property real paintedWidth: img.paintedWidth
    readonly property real paintedHeight: img.paintedHeight

    implicitWidth: 44
    implicitHeight: 44

    function getGoogleColor(str) {
        if (!str) return "#1a73e8";
        var s = str.trim().toLowerCase();
        if (s.indexOf("hieu") !== -1 || s.indexOf("thieu") !== -1 || s.indexOf("hiutrn") !== -1) {
            return "#0288d1";
        }
        var hash = 0;
        for (var i = 0; i < s.length; i++) {
            hash = s.charCodeAt(i) + ((hash << 5) - hash);
        }
        var palette = [
            "#1a73e8", "#0097a7", "#1e8e3e", "#e37400",
            "#8430ce", "#d93025", "#3949ab", "#f29900",
            "#0f9d58", "#e91e63"
        ];
        return palette[Math.abs(hash) % palette.length];
    }

    function getInitialLetter(str) {
        if (!str) return "";
        var clean = str.trim();
        if (clean.startsWith("@") || clean.startsWith("#")) {
            clean = clean.substring(1).trim();
        }
        if (clean.toLowerCase().startsWith("thieu") || clean.toLowerCase().startsWith("hiu")) {
            return "H";
        }
        return clean.length > 0 ? clean.charAt(0).toUpperCase() : "";
    }

    readonly property bool hasInitials: root.useInitialsFallback && root.initialsText !== "" && getInitialLetter(root.initialsText) !== ""

    // 1. Placeholder Background (Active when image is not ready or failed)
    Rectangle {
        id: placeholder
        anchors.fill: parent
        radius: root.radius
        color: root.hasInitials ? root.getGoogleColor(root.initialsText) : root.placeholderColor
        visible: img.status !== Image.Ready
    }

    // 2. Google Material Initials Text (Centered in placeholder when no image)
    Text {
        id: initialsLabel
        anchors.centerIn: parent
        text: root.getInitialLetter(root.initialsText)
        color: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(10, Math.round(Math.min(root.width > 0 ? root.width : root.implicitWidth, root.height > 0 ? root.height : root.implicitHeight) * 0.48))
        font.bold: true
        visible: img.status !== Image.Ready && root.hasInitials
        z: 1
    }

    // 3. Fallback AppIcon (Centered in placeholder when no image and no initials)
    AppIcon {
        id: fallback
        anchors.centerIn: parent
        source: root.fallbackIcon
        iconSize: root.fallbackIconSize
        color: root.fallbackIconColor
        visible: img.status !== Image.Ready && !root.hasInitials && root.fallbackIcon !== ""
    }

    // 4. Main Image Container with clean clipping (0 FBO overhead, zero GPU leak)
    Rectangle {
        id: imgContainer
        anchors.fill: parent
        anchors.margins: root.borderWidth > 0 ? 0.5 : 0
        visible: img.status === Image.Ready
        radius: Math.max(0, root.radius - (root.borderWidth > 0 ? 0.5 : 0))
        color: "transparent"
        clip: root.radius > 0

        Image {
            id: img
            anchors.fill: parent
            source: root.source
            fillMode: root.fillMode
            sourceSize: {
                var w = root.width > 0 ? root.width : root.implicitWidth;
                var h = root.height > 0 ? root.height : root.implicitHeight;
                return Qt.size(Math.max(16, Math.round(w * 2)), Math.max(16, Math.round(h * 2)));
            }
            asynchronous: root.asynchronous
            cache: root.cache
            smooth: true

            onStatusChanged: {
                if (status === Image.Error) {
                    var srcStr = String(source);
                    if (srcStr.indexOf("maxresdefault.jpg") !== -1) {
                        source = srcStr.replace("maxresdefault.jpg", "hqdefault.jpg");
                    }
                }
            }
        }
    }

    // 5. Hairline Border Overlay
    Rectangle {
        id: borderRect
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.color: root.borderColor
        border.width: root.borderWidth
        visible: root.borderWidth > 0 && root.borderColor.a > 0
        z: 2
    }
}
