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
    property size sourceSize: Qt.size(0, 0)
    property real zoomFactor: 1.0
    property bool autoCropBlackBars: true

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

    // Reactive fallback for maxresdefault -> hqdefault (preserves property binding without mutation)
    property bool highResFallbackActive: false
    property real detectedAspect: 1.0
    onSourceChanged: {
        highResFallbackActive = false;
        detectedAspect = 1.0;
    }

    readonly property url effectiveSource: {
        var s = String(root.source);
        if (root.highResFallbackActive && s.indexOf("maxresdefault.jpg") !== -1) {
            return s.replace("maxresdefault.jpg", "hqdefault.jpg");
        }
        return root.source;
    }

    // Effective zoom scale (automatically zooms 1.34x for 4:3 YouTube thumbnails to crop black bars)
    // Uses event-driven detectedAspect to prevent sourceSize -> implicitSize binding loops
    readonly property real effectiveZoom: {
        if (zoomFactor !== 1.0) return Math.max(0.1, zoomFactor);
        if (autoCropBlackBars && root.detectedAspect > 1.25 && root.detectedAspect < 1.45) {
            return 1.34;
        }
        return 1.0;
    }

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

    // 4. Background Image Loader (Decodes texture in background for scene graph)
    Image {
        id: img
        anchors.fill: parent
        source: root.effectiveSource
        fillMode: root.fillMode
        sourceSize: {
            if (root.sourceSize.width > 0 && root.sourceSize.height > 0) {
                return root.sourceSize;
            }
            var w = root.width > 0 ? root.width : root.implicitWidth;
            var h = root.height > 0 ? root.height : root.implicitHeight;
            if (w <= 0 || h <= 0) return Qt.size(0, 0);
            var zoom = root.effectiveZoom;
            // Quantize to steps of 100px so subpixel resizing animations never thrash Qt Image texture decoding
            var qw = Math.ceil(Math.max(16, w * 2 * zoom) / 100) * 100;
            var qh = Math.ceil(Math.max(16, h * 2 * zoom) / 100) * 100;
            return Qt.size(qw, qh);
        }
        asynchronous: root.asynchronous
        cache: root.cache
        smooth: true
        mipmap: true
        // Only visible directly when radius <= 0; when radius > 0, roundedShader handles single-pass SDF rendering
        visible: root.radius <= 0 && status === Image.Ready

        onStatusChanged: {
            if (status === Image.Ready) {
                if (implicitHeight > 0) {
                    root.detectedAspect = implicitWidth / implicitHeight;
                }
            } else if (status === Image.Error) {
                var srcStr = String(root.source);
                if (srcStr.indexOf("maxresdefault.jpg") !== -1 && !root.highResFallbackActive) {
                    root.highResFallbackActive = true;
                }
            }
        }
    }

    // 5. Hardware-accelerated Single-Pass SDF Rounded Shader (0 FBOs, 0 GPU leak, 0 dark corner fringe)
    ShaderEffect {
        id: roundedShader
        anchors.fill: parent
        anchors.margins: root.borderWidth > 0 ? (root.borderWidth * 0.5) : 0
        visible: root.radius > 0 && img.status === Image.Ready && root.visible && root.opacity > 0.01

        property variant source: img
        property vector2d u_resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
        property vector2d u_sourceSize: Qt.vector2d(Math.max(1, img.implicitWidth), Math.max(1, img.implicitHeight))
        property real u_radius: Math.max(0, root.radius - (root.borderWidth > 0 ? (root.borderWidth * 0.5) : 0))
        property real u_scale: root.effectiveZoom
        property int u_fillMode: root.fillMode === Image.PreserveAspectCrop ? 2 : 0

        fragmentShader: Qt.resolvedUrl("../assets/shaders/rounded_image.frag.qsb")
    }

    // 6. Hairline Border Overlay
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
