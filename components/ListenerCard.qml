import QtQuick
import QtQuick.Effects
import QtQuick.Window
import QtMultimedia
import QtQml
import "code128.js" as Code128

// Listener card: a brushed-gold identity card. It tilts toward the pointer, can be dragged
// (springs back), flips on click to a Code 128 barcode, and carries a side strip with the
// owner's name sliding past. The light band follows the tilt so the metal reads as metal.
Item {
    id: root

    property string userName: ""
    property string userTag: ""
    property string avatarUrl: ""
    property double joinedAt: 0          // epoch ms; 0 = unknown
    property string cardNumber: "NTY-0000-0000"
    property bool interactive: true
    property bool flipped: false
    property bool liteMode: false
    // 0..1: how much the card drifts on its own (the welcome moment uses 1)
    property real swayAmount: 0
    // On the profile page a click opens the profile instead of flipping the card
    property bool opensProfile: false
    // Hides the photo, name and number while flying copies of them are in the air
    property bool partsHidden: false
    signal openRequested()

    // --- Recap: pull, scratch, scan --------------------------------------------------------
    // pullable: a vertical drag also reports itself, so the profile header can stretch with it
    property bool pullable: false
    signal pullMoved(real dy)
    signal pullReleased(real dy, real velocityY)
    // scratchMode: the back shows a silver coating over the barcode; rubbing it off reports scratched()
    property bool coated: false          // the back's barcode sits under a scratch-off coating
    property bool scratchMode: false
    property real scanProgress: 0        // 0..1, the scanner line sweeping the bars
    property bool scanFailed: false      // the sweep ends in rose instead of green
    property real coating: 1             // the coating's opacity; the owner fades it once scratched
    signal scratched()
    // 0..1: the "verified" stamp after a good scan; the card dips as it lands
    property real stampProgress: 0
    readonly property real stampKick: {
        var k = (stampProgress - 0.3) / 0.1;
        return k <= 0 || k >= 1 ? 0 : Math.sin(Math.PI * k);
    }
    property bool stampThudPlayed: false
    onStampProgressChanged: {
        if (stampProgress <= 0) { stampThudPlayed = false; return; }
        if (!stampThudPlayed && stampProgress >= 0.31) { stampThudPlayed = true; stampThud.play(); }
    }
    SoundEffect { id: stampThud; source: Qt.resolvedUrl("../assets/sounds/stamp.wav"); volume: 0.5 }
    readonly property real revealed: scratchGrid.cleared / scratchGrid.total
    // Scratch feedback. Sound is grains, not a loop: every few px of coin travel fires one short
    // friction burst, louder with speed, so it stops the instant the coin does (the usual approach
    // for friction sounds: grain density and level follow the drag).
    property real rubEnergy: 0
    readonly property bool scratching: scratchArea.pressed
    property real rubShakeX: 0
    property real rubShakeY: 0
    property real rubTravel: 0
    property real press: scratchArea.pressed ? 1 : 0
    Behavior on press { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.005 } }
    property double rubLastAt: 0
    property int grainNext: 0
    function rubbed(dist) {
        var now = Date.now();
        var dt = Math.max(8, Math.min(120, now - root.rubLastAt));
        root.rubLastAt = now;
        var speed = dist / root.unit / dt;          // card px per ms
        root.rubEnergy = Math.min(1, root.rubEnergy * 0.6 + speed * 0.5);
        if (!root.liteMode) {
            root.rubShakeX = (Math.random() - 0.5) * 0.7 * root.unit * root.rubEnergy;
            root.rubShakeY = (Math.random() - 0.5) * 0.45 * root.unit * root.rubEnergy;
        }
        root.rubTravel += dist;
        var step = 9 * root.unit;
        if (root.rubTravel < step) return;
        root.rubTravel = root.rubTravel % step;
        var g = grains.objectAt(root.grainNext);
        root.grainNext = (root.grainNext + 1 + Math.floor(Math.random() * 2)) % grains.count;
        if (!g) return;
        g.volume = Math.min(0.26, 0.07 + root.rubEnergy * 0.2) * (0.8 + Math.random() * 0.2);
        g.play();
    }
    FrameAnimation {
        running: root.rubEnergy > 0
        onTriggered: {
            root.rubEnergy = Math.max(0, root.rubEnergy - frameTime * 3.2);
            root.rubShakeX *= 0.6;
            root.rubShakeY *= 0.6;
            if (root.rubEnergy === 0) { root.rubShakeX = 0; root.rubShakeY = 0; }
        }
    }
    Instantiator {
        id: grains
        model: 6
        SoundEffect { source: Qt.resolvedUrl("../assets/sounds/scratch_" + (index + 1) + ".wav") }
    }
    function resetScratch() {
        scratchGrid.cells = [];
        scratchGrid.cleared = 0;
        scratchGrid.reported = false;
        coatingCanvas.fresh = true;
        coatingCanvas.requestPaint();
        root.coating = 1;
    }

    // The parts the profile page flies out of the card
    readonly property Item photoItem: photo
    readonly property Item nameItem: nameText
    readonly property Item numberItem: numberText

    readonly property real unit: width / 332
    readonly property real cardRadius: 22 * unit
    readonly property real stripWidth: 40 * unit
    readonly property bool showingBack: Math.cos((flipAngle + angleY) * Math.PI / 180) < 0

    implicitWidth: 332
    implicitHeight: 176

    // Clock for the drift and the side strip; stops when the card is off screen
    property real time: 0
    FrameAnimation {
        running: root.visible && !root.liteMode
        onTriggered: root.time += frameTime
    }

    // --- Motion state ---------------------------------------------------------------
    // Tilt follows a target through a damped spring, the way Mochy does it: the card never
    // moves, only its angle eases toward where the pointer is. Following uses a stiff spring
    // with no bounce; letting go uses a softer one that wobbles once and settles.
    property real tiltX: 0
    property real tiltY: 0
    property real tiltTargetX: 0
    property real tiltTargetY: 0
    property bool tiltReleased: true
    property real _vX: 0
    property real _vY: 0
    function aimTilt(tx, ty, released) {
        root.tiltReleased = released;
        root.tiltTargetX = tx;
        root.tiltTargetY = ty;
    }
    FrameAnimation {
        running: root.visible && (Math.abs(root.tiltTargetX - root.tiltX) > 0.01
                                  || Math.abs(root.tiltTargetY - root.tiltY) > 0.01
                                  || Math.abs(root._vX) > 0.01 || Math.abs(root._vY) > 0.01)
        onTriggered: {
            var k = root.tiltReleased ? 200 : 400;
            var c = 2 * (root.tiltReleased ? 0.42 : 1.0) * Math.sqrt(k);
            var left = Math.min(frameTime, 0.05);
            var x = root.tiltX, y = root.tiltY, vx = root._vX, vy = root._vY;
            while (left > 0) {
                var dt = Math.min(left, 1 / 240);
                vx += (-k * (x - root.tiltTargetX) - c * vx) * dt;
                vy += (-k * (y - root.tiltTargetY) - c * vy) * dt;
                x += vx * dt; y += vy * dt;
                left -= dt;
            }
            if (Math.abs(x - root.tiltTargetX) < 0.01 && Math.abs(vx) < 0.01) { x = root.tiltTargetX; vx = 0; }
            if (Math.abs(y - root.tiltTargetY) < 0.01 && Math.abs(vy) < 0.01) { y = root.tiltTargetY; vy = 0; }
            root._vX = vx; root._vY = vy;
            root.tiltX = x; root.tiltY = y;
        }
    }
    property real flipAngle: flipped ? 180 : 0

    readonly property real angleY: tiltY + Math.cos(time * 1.4) * 7 * swayAmount
    readonly property real angleX: tiltX + Math.sin(time * 1.1) * 4 * swayAmount
    readonly property real sheen: 0.5 + angleY / 45

    Behavior on flipAngle { NumberAnimation { duration: 620; easing.type: Easing.OutCubic } }

    function joinedText(ms) {
        if (!ms || ms <= 0) return "";
        var d = new Date(ms);
        return I18n.tr("tham gia ngày " + Qt.formatDate(d, "dd/MM/yyyy"), "joined " + Qt.formatDate(d, "MMM d, yyyy"));
    }

    // Ink colours printed on the gold
    readonly property color inkStrong: "#24180A"
    readonly property color inkSoft: "#5A4220"

    // --- Input ------------------------------------------------------------------------
    HoverHandler {
        id: hover
        enabled: root.interactive && !root.scratchMode
        onPointChanged: {
            if (dragHandler.active || !hovered) return;
            var nx = (point.position.x / Math.max(1, root.width)) - 0.5;
            var ny = (point.position.y / Math.max(1, root.height)) - 0.5;
            root.aimTilt(-ny * 18, nx * 22, false);
        }
        onHoveredChanged: {
            if (!hovered && !dragHandler.active) root.aimTilt(0, 0, true);
        }
    }

    // A drag only tilts the card and, once it is clearly a downward pull, pulls the header.
    // The card itself stays where it is, so nothing jumps under the pointer.
    DragHandler {
        id: dragHandler
        enabled: root.interactive && !root.scratchMode
        target: null
        property real lastDy: 0
        property bool pulling: false
        onActiveTranslationChanged: {
            if (!active) return;
            var dx = activeTranslation.x, dy = activeTranslation.y;
            if (!pulling && root.pullable && dy > 10 && Math.abs(dy) > Math.abs(dx) * 1.2)
                pulling = true;
            if (pulling) {
                lastDy = dy;
                root.pullMoved(dy);
            }
            var lean = root.showingBack ? 0.5 : 1;
            root.aimTilt(Math.max(-18, Math.min(18, -dy * 0.07)) * lean,
                         Math.max(-26, Math.min(26, dx * 0.09)) * lean, false);
        }
        onActiveChanged: {
            if (!active) {
                if (pulling) root.pullReleased(lastDy, centroid.velocity.y);
                pulling = false;
                lastDy = 0;
                root.aimTilt(0, 0, true);
            }
        }
    }

    TapHandler {
        enabled: root.interactive && !root.scratchMode
        cursorShape: Qt.PointingHandCursor
        onTapped: {
            if (root.opensProfile && !root.showingBack) root.openRequested();
            else root.flipped = !root.flipped;
        }
    }

    // --- Card body --------------------------------------------------------------------
    // The card face renders into one layer with a transparent margin and 2x supersampling,
    // so its straight edges stay antialiased while the 3D rotation turns them. Corners are cut
    // by a mask on the GPU; the light band is a moving item, so nothing repaints on tilt.
    readonly property real edgePad: 3
    readonly property real superSample: 2 * Screen.devicePixelRatio

    Item {
        id: body
        width: root.width + root.edgePad * 2
        height: root.height + root.edgePad * 2
        x: -root.edgePad
        y: -root.edgePad

        transform: [
            Rotation {
                origin.x: body.width / 2; origin.y: body.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.flipAngle + root.angleY
            },
            Rotation {
                origin.x: body.width / 2; origin.y: body.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: root.angleX
            },
            // a coin rubbing foil: the card gives a little under it and shivers
            Scale { origin.x: body.width / 2; origin.y: body.height / 2; xScale: 1 - 0.018 * root.press - 0.035 * root.stampKick; yScale: xScale },
            Translate { x: root.rubShakeX; y: root.rubShakeY }
        ]

        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(Math.ceil(body.width * root.superSample), Math.ceil(body.height * root.superSample))
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Item {
            id: cardMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: body.layer.textureSize
            Rectangle {
                x: root.edgePad; y: root.edgePad
                width: root.width; height: root.height
                radius: root.cardRadius
                antialiasing: true
                color: "black"
            }
        }

        Item {
            id: face
            x: root.edgePad
            y: root.edgePad
            width: root.width
            height: root.height

            // Brushed gold, grain lines and the darker side strip. Static: repaints on resize or flip only.
            Canvas {
                id: surface
                anchors.fill: parent
                property bool back: root.showingBack
                onBackChanged: requestPaint()
                // a paint asked for while hidden is dropped: a card sized before it shows came up bare
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    if (width <= 0 || height <= 0) return;
                    var g = ctx.createLinearGradient(0, 0, width, height);
                    g.addColorStop(0.00, "#C9974F");
                    g.addColorStop(0.35, "#F3D79F");
                    g.addColorStop(0.55, "#B7853E");
                    g.addColorStop(0.80, "#E7C27F");
                    g.addColorStop(1.00, "#A47232");
                    ctx.fillStyle = g;
                    ctx.fillRect(0, 0, width, height);
                    var lines = Math.floor(height / 3);
                    for (var i = 0; i < lines; i++) {
                        ctx.fillStyle = i % 2 === 0 ? "rgba(255,248,230,0.06)" : "rgba(255,248,230,0.03)";
                        ctx.fillRect(0, i * 3, width, 1);
                    }
                    if (!back) {
                        ctx.fillStyle = "rgba(60,36,8,0.16)";
                        ctx.fillRect(width - root.stripWidth, 0, root.stripWidth, height);
                    }
                }
            }

            // Light band that slides with the tilt; mirrored on the back
            Rectangle {
                readonly property real s: root.showingBack ? 1 - root.sheen : root.sheen
                width: face.width * 0.55
                height: face.height * 3
                x: Math.max(-0.2, Math.min(1.2, s)) * face.width - width / 2
                y: (face.height - height) / 2
                rotation: 24
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 0.98, 0.92, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 0.98, 0.92, 0.42) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 0.98, 0.92, 0) }
                }
            }
            // ===== Front =====
            Item {
                id: front
                anchors.fill: parent
                visible: !root.showingBack

                Text {
                    id: numberText
                    x: 22 * root.unit
                    y: 20 * root.unit
                    opacity: root.partsHidden ? 0 : 1
                    text: "NUTSTY  " + root.cardNumber
                    color: root.inkSoft
                    font.family: "monospace"
                    font.pixelSize: 11 * root.unit
                    font.letterSpacing: 0.5
                }

                Row {
                    x: 22 * root.unit
                    width: root.width - root.stripWidth - 34 * root.unit
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 8 * root.unit
                    spacing: 18 * root.unit

                    RoundedImage {
                        id: photo
                        width: 92 * root.unit
                        height: width
                        opacity: root.partsHidden ? 0 : 1
                        radius: width / 2
                        source: root.avatarUrl
                        initialsText: root.userName
                        fallbackIconColor: "#8A6127"
                        borderColor: Qt.rgba(0.14, 0.09, 0.03, 0.35)
                        borderWidth: 1
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - photo.width - parent.spacing
                        spacing: 1 * root.unit
                        Text {
                            text: I18n.tr("THẺ NGƯỜI NGHE CỦA", "LISTENER CARD OF")
                            color: root.inkSoft
                            font.family: "monospace"
                            font.pixelSize: 10 * root.unit
                        }
                        Text {
                            id: nameText
                            width: parent.width
                            elide: Text.ElideRight
                            opacity: root.partsHidden ? 0 : 1
                            text: root.userName
                            color: root.inkStrong
                            font.family: Theme.fontFamily
                            font.pixelSize: 21 * root.unit
                            font.weight: Font.Bold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            visible: text.length > 0
                            text: root.joinedText(root.joinedAt)
                            color: Qt.rgba(0.14, 0.09, 0.04, 0.85)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10.5 * root.unit
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Side strip: the owner's name turned a quarter, sliding down one length every 5.2s
                Item {
                    x: root.width - root.stripWidth
                    width: root.stripWidth
                    height: root.height
                    clip: true

                    TextMetrics { id: stripMetrics; font: stripText.font; text: stripText.unitText }
                    Text {
                        id: stripText
                        readonly property string unitText: I18n.tr("THẺ CỦA " + root.userName.toUpperCase(), root.userName + "'s CARD") + "   ·   "
                        readonly property real progress: (root.time / 5.2) % 1
                        rotation: 90
                        transformOrigin: Item.TopLeft
                        x: parent.width / 2 + height / 2
                        y: -stripMetrics.advanceWidth + progress * stripMetrics.advanceWidth
                        text: unitText.repeat(Math.ceil(root.height / Math.max(1, stripMetrics.advanceWidth)) + 2)
                        color: Qt.rgba(0.17, 0.11, 0.04, 0.72)
                        font.family: Theme.fontFamily
                        font.pixelSize: 17 * root.unit
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                    }
                }
            }

            // ===== Back =====
            Item {
                id: back
                anchors.fill: parent
                visible: root.showingBack
                // Mirror so the back reads correctly once the card has turned 180 degrees
                transform: Rotation { origin.x: back.width / 2; axis { x: 0; y: 1; z: 0 } angle: 180 }

                Rectangle {
                    id: magStrip
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 20 * root.unit }
                    height: 32 * root.unit
                    color: Qt.rgba(0.12, 0.08, 0.03, 0.82)
                }

                Rectangle {
                    id: barcodePlate
                    anchors {
                        left: parent.left; right: parent.right; top: magStrip.bottom
                        leftMargin: 22 * root.unit; rightMargin: 22 * root.unit; topMargin: 14 * root.unit
                    }
                    height: 62 * root.unit
                    radius: 6 * root.unit
                    color: "#FBF3E2"

                    readonly property var code: Code128.runs(root.cardNumber)
                    readonly property real moduleW: (width - 24 * root.unit) / Math.max(1, code.modules)

                    Repeater {
                        model: barcodePlate.code.runs
                        Rectangle {
                            x: 12 * root.unit + modelData[0] * barcodePlate.moduleW
                            y: 9 * root.unit
                            width: modelData[1] * barcodePlate.moduleW
                            height: barcodePlate.height - 18 * root.unit
                            color: root.inkStrong
                        }
                    }

                    // The scanner: a thin line sweeping the bars, green, or rose when the code says no
                    Item {
                        id: scanner
                        anchors.fill: parent
                        visible: root.scanProgress > 0 && root.scanProgress < 1
                        readonly property color tint: root.scanFailed && root.scanProgress > 0.74
                                                      ? Qt.rgba(0.96, 0.25, 0.37, 1) : Qt.rgba(0.2, 0.86, 0.5, 1)
                        // there and back once
                        readonly property real pos: root.scanProgress < 0.5 ? root.scanProgress * 2 : 2 - root.scanProgress * 2
                        Rectangle {
                            x: scanner.pos * (scanner.width - width)
                            y: -6 * root.unit
                            width: 3 * root.unit
                            height: scanner.height + 12 * root.unit
                            radius: width / 2
                            color: scanner.tint
                        }
                        Rectangle {
                            x: scanner.pos * (scanner.width - 3 * root.unit) - width / 2
                            width: 34 * root.unit
                            height: parent.height
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(scanner.tint.r, scanner.tint.g, scanner.tint.b, 0.28) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                    }

                    // Silver scratch-off coating, after Mochy's IdCardBack: a foil gradient printed
                    // with a repeated micro line like a lottery ticket, a highlight that keeps
                    // drifting across, and flakes that fall off under the pointer. Strokes are cut
                    // out of the canvas as they come in; it swells a little as it dissolves.
                    Item {
                        id: coatingHost
                        anchors.fill: parent
                        anchors.margins: -2 * root.unit
                        visible: root.coated && root.coating > 0.001
                        opacity: root.coating
                        scale: 1 + (1 - root.coating) * 0.06

                        Canvas {
                            id: coatingCanvas
                            anchors.fill: parent
                            property bool fresh: true
                            property var pending: []
                            readonly property string micro: I18n.tr("CÀO · NUTSTY · ", "SCRATCH · NUTSTY · ")
                            onMicroChanged: { fresh = true; requestPaint(); }
                            onWidthChanged: { fresh = true; requestPaint(); }
                            onHeightChanged: { fresh = true; requestPaint(); }
                            onPaint: {
                                var ctx = getContext("2d");
                                var m = 2 * root.unit;
                                if (fresh) {
                                    fresh = false;
                                    pending = [];
                                    ctx.reset();
                                    var g = ctx.createLinearGradient(0, 0, width, height);
                                    g.addColorStop(0.00, "#B9BBC1");
                                    g.addColorStop(0.35, "#E6E7EB");
                                    g.addColorStop(0.55, "#A6A8AF");
                                    g.addColorStop(0.80, "#D5D7DC");
                                    g.addColorStop(1.00, "#9A9CA3");
                                    ctx.fillStyle = g;
                                    ctx.beginPath();
                                    ctx.roundedRect(0, 0, width, height, 8 * root.unit, 8 * root.unit);
                                    ctx.fill();
                                    // the micro line, letter by letter so it can be spaced out
                                    ctx.save();
                                    ctx.beginPath();
                                    ctx.roundedRect(0, 0, width, height, 8 * root.unit, 8 * root.unit);
                                    ctx.clip();
                                    var px = Math.max(6, 7.4 * root.unit);
                                    ctx.font = "bold " + Math.round(px) + "px monospace";
                                    ctx.fillStyle = "rgba(142, 144, 150, 0.55)";
                                    ctx.textBaseline = "middle";
                                    var gap = 1.6 * root.unit, chars = micro.split(""), widths = [], run = 0;
                                    for (var i = 0; i < chars.length; i++) { widths.push(ctx.measureText(chars[i]).width + gap); run += widths[i]; }
                                    var row = 0;
                                    for (var y = height * 0.18; y < height; y += height * 0.32) {
                                        var x = -((row * 37 * root.unit) % run);
                                        while (x < width) {
                                            for (var j = 0; j < chars.length; j++) { ctx.fillText(chars[j], x, y); x += widths[j]; }
                                        }
                                        row++;
                                    }
                                    ctx.restore();
                                }
                                if (pending.length === 0) return;
                                ctx.save();
                                ctx.globalCompositeOperation = "destination-out";
                                ctx.fillStyle = "black";
                                // a coin's edge, not a round eraser: a core plus a few ragged bites
                                // around it, some only half through, so the foil tears unevenly
                                var r = 10 * root.unit;
                                for (var k = 0; k < pending.length; k++) {
                                    var px = pending[k].x + m, py = pending[k].y + m;
                                    ctx.globalAlpha = 1;
                                    ctx.beginPath();
                                    ctx.arc(px, py, r * 0.72, 0, Math.PI * 2);
                                    ctx.fill();
                                    for (var q = 0; q < 4; q++) {
                                        var ang = Math.random() * Math.PI * 2, d = r * (0.45 + Math.random() * 0.45);
                                        ctx.globalAlpha = 0.55 + Math.random() * 0.45;
                                        ctx.beginPath();
                                        ctx.arc(px + Math.cos(ang) * d, py + Math.sin(ang) * d, r * (0.22 + Math.random() * 0.26), 0, Math.PI * 2);
                                        ctx.fill();
                                    }
                                }
                                ctx.restore();
                                pending = [];
                            }
                        }

                        // The drifting highlight, kept to what is left of the foil
                        Item {
                            anchors.fill: parent
                            visible: !root.liteMode
                            layer.enabled: visible
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: coatingCanvas
                                maskThresholdMin: 0.1
                                maskSpreadAtMin: 0.2
                            }
                            Rectangle {
                                readonly property real sweep: ((root.time * 0.45) % 1.6 - 0.3)
                                width: parent.width * 0.35
                                height: parent.height * 2.4
                                x: sweep * parent.width - width / 2
                                y: (parent.height - height) / 2
                                rotation: 22
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.45) }
                                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                                }
                            }
                        }
                    }

                    // Bits of foil flicked off by the pointer: x, y, vx, vy, age, size
                    Canvas {
                        id: flakeCanvas
                        anchors.fill: parent
                        anchors.margins: -2 * root.unit
                        anchors.bottomMargin: -60 * root.unit
                        visible: root.coated && !root.liteMode
                        property var flakes: []
                        function spawn(p, count) {
                            // a fresh array every time: re-assigning the same one sends no change, so
                            // with nothing falling the animation below would stay asleep and the
                            // new flakes would never be drawn
                            var list = flakes.slice();
                            for (var i = 0; i < count; i++)
                                list.push([p.x + 2 * root.unit + (Math.random() - 0.5) * 10 * root.unit,
                                           p.y + 2 * root.unit + (Math.random() - 0.5) * 6 * root.unit,
                                           (Math.random() - 0.5) * 36 * root.unit, Math.random() * 50 * root.unit,
                                           0, (1.6 + Math.random() * 3) * root.unit, 0.72 + Math.random() * 0.28]);
                            if (list.length > 90) list.splice(0, list.length - 90);
                            flakes = list;
                        }
                        FrameAnimation {
                            running: flakeCanvas.visible && flakeCanvas.flakes.length > 0
                            onTriggered: {
                                var kept = [];
                                for (var i = 0; i < flakeCanvas.flakes.length; i++) {
                                    var f = flakeCanvas.flakes[i];
                                    f[4] += frameTime;
                                    if (f[4] < 0.95) kept.push(f);
                                }
                                flakeCanvas.flakes = kept;
                                flakeCanvas.requestPaint();
                            }
                        }
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            for (var i = 0; i < flakes.length; i++) {
                                var f = flakes[i], age = f[4];
                                // foil dust drops off where the coin went, falling under gravity
                                ctx.globalAlpha = Math.max(0, 1 - age / 0.95) * 0.95;
                                ctx.fillStyle = Qt.rgba(0.79 * f[6], 0.80 * f[6], 0.82 * f[6], 1);
                                ctx.fillRect(f[0] + f[2] * age, f[1] + f[3] * age + 0.5 * 900 * root.unit * age * age, f[5], f[5] * 0.75);
                            }
                        }
                    }
                }

                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; top: barcodePlate.bottom; topMargin: 8 * root.unit }
                    text: root.cardNumber.split("").join(" ")
                    font.family: "monospace"
                    font.pixelSize: 11 * root.unit
                    color: root.inkSoft
                }

                // Lands once the barcode scans
                VerifiedStamp {
                    anchors.fill: parent
                    unit: root.unit
                    progress: root.stampProgress
                }
            }
        }
    }

    // Scratching. The back is turned twice (the card's 180 and the back's own mirror), so it reads
    // the right way round and a pointer maps straight across to it.
    MouseArea {
        id: scratchArea
        anchors.fill: parent
        enabled: root.scratchMode && root.coating > 0.99
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.BlankCursor : Qt.ArrowCursor
        // the header's drag-to-fold must not take a scratch stroke that drifts upward
        preventStealing: true
        property point last: Qt.point(-1, 0)
        function toStrip(mx, my) {
            return Qt.point(mx - barcodePlate.x, my - barcodePlate.y);
        }
        function rub(p) {
            var brush = 16 * root.unit;
            var first = last.x < 0;
            var from = first ? p : last;
            root.rubbed(Math.hypot(p.x - from.x, p.y - from.y));
            var steps = Math.max(1, Math.min(40, Math.ceil(Math.hypot(p.x - from.x, p.y - from.y) / (brush * 0.35))));
            var pts = [];
            for (var s = 1; s <= steps; s++)
                pts.push(Qt.point(from.x + (p.x - from.x) * s / steps, from.y + (p.y - from.y) * s / steps));
            if (last.x < 0) pts.unshift(p);
            last = p;
            coatingCanvas.pending = coatingCanvas.pending.concat(pts);
            coatingCanvas.requestPaint();
            // a press always knocks a little burst loose, a stroke sheds as it goes
            flakeCanvas.spawn(p, first ? 6 + Math.floor(Math.random() * 3) : 1 + Math.floor(Math.random() * 3));
            scratchGrid.mark(pts, brush);
        }
        property real coinAngle: 0
        function lean(mx, my) {
            // the card leans under the coin; on the back, left and right are mirrored
            var nx = mx / width * 2 - 1, ny = my / height * 2 - 1;
            root.aimTilt(-ny * 5, -nx * 6, false);
        }
        onPressed: mouse => { last = Qt.point(-1, 0); root.rubLastAt = Date.now(); lean(mouse.x, mouse.y); rub(toStrip(mouse.x, mouse.y)); }
        onPositionChanged: mouse => {
            if (!pressed) return;
            var p = toStrip(mouse.x, mouse.y);
            if (last.x >= 0 && Math.hypot(p.x - last.x, p.y - last.y) > 0.5)
                coinAngle = Math.atan2(p.y - last.y, p.x - last.x) * 180 / Math.PI;
            lean(mouse.x, mouse.y);
            rub(p);
        }
        onReleased: { last = Qt.point(-1, 0); root.aimTilt(0, 0, true); }
        onExited: if (!pressed) root.aimTilt(0, 0, true)
    }

    // The coin in hand: it follows the pointer over the coating, its edge turned along the stroke
    Item {
        id: coin
        visible: scratchArea.enabled && scratchArea.containsMouse
        readonly property real d: 22 * root.unit
        x: scratchArea.mouseX - d / 2
        y: scratchArea.mouseY - d / 2
        width: d; height: d
        z: 10
        rotation: scratchArea.coinAngle
        scale: 1 - 0.12 * root.press
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#8E9097" }
                GradientStop { position: 0.45; color: "#F1F2F4" }
                GradientStop { position: 1.0; color: "#7C7E85" }
            }
            border.width: Math.max(1, 1.4 * root.unit)
            border.color: Qt.rgba(0.32, 0.33, 0.36, 0.9)
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.62; height: width; radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.3, 0.31, 0.34, 0.5)
        }
    }

    QtObject {
        id: scratchGrid
        readonly property int cols: 24
        readonly property int rows: 6
        readonly property int total: cols * rows
        property var cells: []
        property int cleared: 0
        property bool reported: false
        function mark(pts, brush) {
            var w = barcodePlate.width, h = barcodePlate.height, r = brush / 2, n = cleared;
            for (var k = 0; k < pts.length; k++) {
                var c0 = Math.max(0, Math.floor((pts[k].x - r) / w * cols)), c1 = Math.min(cols - 1, Math.floor((pts[k].x + r) / w * cols));
                var r0 = Math.max(0, Math.floor((pts[k].y - r) / h * rows)), r1 = Math.min(rows - 1, Math.floor((pts[k].y + r) / h * rows));
                for (var row = r0; row <= r1; row++)
                    for (var col = c0; col <= c1; col++)
                        if (!cells[row * cols + col]) { cells[row * cols + col] = true; n++; }
            }
            cleared = n;
            if (!reported && cleared / total >= 0.8) { reported = true; root.scratched(); }
        }
    }
}
