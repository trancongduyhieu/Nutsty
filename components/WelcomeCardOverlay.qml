import QtQuick
import QtQuick.Effects

// One-time welcome: the gold listener card flies in with a burst of confetti and a big hello,
// stays until the user clicks, then flies into the header avatar where the profile page lives.
// Fresh installs and returning users get different lines.
Item {
    id: root
    anchors.fill: parent
    visible: opacity > 0.001
    opacity: 0

    property bool returning: false
    property string userName: ""
    property string userTag: ""
    property string avatarUrl: ""
    property double joinedAt: 0
    property string cardNumber: "NTY-0000-0000"
    property Item flyTarget: null
    property bool liteMode: false

    property int lineIndex: 0
    property bool leaving: false
    property real time: 0

    signal finished()
    // the card starts to leave: the home underneath should be there to land on
    signal departing()
    // the card reached the avatar (not emitted when it had nowhere to fly and shrank in place)
    signal landing()
    property bool landed: false

    readonly property var returningLines: [
        I18n.tr("vẫn ở đây à? thẻ của bạn nè", "still here? here's your card"),
        I18n.tr("khách quen thì phải có thẻ chứ", "regulars get a card"),
        I18n.tr("thẻ của bạn chờ ở quầy lâu lắm rồi", "your card has been waiting at the counter"),
        I18n.tr("lại là bạn à? mời vào, mời vào", "you again? come in, come in"),
        I18n.tr("khách ruột quay lại, bá khí ngút trời", "a regular returns, aura intact"),
        I18n.tr("bản mới đây, khum cần cảm ơn đâu", "new update dropped, no cap")
    ]
    readonly property var freshLines: [
        I18n.tr("chào mừng đến với Nutsty!", "welcome to nutsty!"),
        I18n.tr("thẻ mới tinh, còn thơm mùi mực", "a brand new card, ink still wet"),
        I18n.tr("từ giờ bạn là người của Nutsty", "you belong to nutsty now"),
        I18n.tr("vào đây, nhạc đang chờ bạn đó", "come in, the music is waiting"),
        I18n.tr("nhận thẻ thành công, bá khí cộng một ngàn", "card unlocked, plus a thousand aura"),
        I18n.tr("trùng sinh vào Nutsty thành công", "your nutsty era starts now")
    ]
    // The big word; add more and one is picked each time
    readonly property var helloLines: [
        I18n.tr("Chao xìn!", "Hello!"),
        I18n.tr("Oi oi oi!", "Oi oi oi!"),
        I18n.tr("Ủa alo!", "Yo!"),
        I18n.tr("Hé lô!", "Howdy!"),
        I18n.tr("Gét gô!", "Lock in!")
    ]
    property int helloIndex: 0
    readonly property string subline: returning ? returningLines[lineIndex % returningLines.length]
                                                : freshLines[lineIndex % freshLines.length]

    readonly property real cardWidth: Math.min(width * 0.86, 420)
    readonly property real centerY: height * 0.42
    readonly property real far: Math.sqrt(width * width + height * height)

    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
    function easeOut(t) { var u = 1 - t; return 1 - u * u * u; }
    function easeOutBack(t) { var c1 = 1.4, c3 = c1 + 1, x = t - 1; return 1 + c3 * x * x * x + c1 * x * x; }

    function open(isReturning) {
        root.returning = isReturning;
        root.lineIndex = Math.floor(Math.random() * 1000);
        root.helloIndex = Math.floor(Math.random() * root.helloLines.length);
        root.leaving = false;
        root.time = 0;
        flyer.flyX = 0; flyer.flyY = 0; flyer.flyScale = 1; flyer.opacity = 1;
        backdrop.opacity = 1;
        card.flipped = false;
        confetti.seed();
        root.opacity = 1;
    }

    function skip() { root.flyAway(); }

    function flyAway() {
        if (root.leaving || root.opacity < 0.5) return;
        root.leaving = true;
        root.departing();
        var tx = 0, ty = 0, ts = 0.12;
        root.landed = false;
        if (root.flyTarget && root.flyTarget.visible && root.flyTarget.width > 0) {
            var p = root.flyTarget.mapToItem(root, root.flyTarget.width / 2, root.flyTarget.height / 2);
            tx = p.x - root.width / 2;
            ty = p.y - root.centerY;
            // shrink to the avatar's own size (22 px inside its 32 px button)
            ts = Math.max(0.03, Math.min(22, root.flyTarget.width) / Math.max(1, root.cardWidth));
            root.landed = true;
        }
        flyXAnim.to = tx; flyYAnim.to = ty; flySAnim.to = ts;
        flyAnim.restart();
    }

    function close() {
        flyAnim.stop();
        root.opacity = 0;
        root.leaving = false;
        root.finished();
    }

    FrameAnimation {
        running: root.visible
        onTriggered: root.time += frameTime
    }

    // The card stays until the user clicks; it never leaves on its own
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.flyAway()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: backdrop
        anchors.fill: parent

        // Warm radial backdrop, painted once per size
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var g = ctx.createRadialGradient(width / 2, root.centerY, 0, width / 2, root.centerY, Math.max(width, height) * 0.75);
                g.addColorStop(0, "#2E2416");
                g.addColorStop(1, "#0E0B08");
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
        }

        // Gold glow: four drifting circles, blurred
        Item {
            id: glowSource
            anchors.fill: parent
            visible: false
            Repeater {
                model: 4
                Rectangle {
                    readonly property real a: root.time * (0.6 + index * 0.17) + index * 1.7
                    readonly property real r: root.width * (0.28 + 0.05 * index)
                    width: r * 2; height: r * 2; radius: r
                    x: root.width / 2 + Math.cos(a) * root.width * 0.12 - r
                    y: root.centerY + Math.sin(a * 1.3) * root.width * 0.10 - r
                    color: Qt.rgba(0.87, 0.69, 0.42, 0.20 - index * 0.04)
                }
            }
        }
        MultiEffect {
            anchors.fill: parent
            visible: !root.liteMode
            source: glowSource
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            opacity: root.clamp(root.time / 0.5, 0, 1)
        }

        // Light sweep and ring leaving the card
        Rectangle {
            readonly property real p: root.easeOut(root.clamp(root.time / 0.9, 0, 1))
            visible: p < 1
            width: root.far * p * 2; height: width; radius: width / 2
            x: root.width / 2 - width / 2; y: root.centerY - height / 2
            color: Qt.rgba(1, 0.95, 0.85, 0.10 * (1 - p))
        }
        Rectangle {
            readonly property real ring: root.easeOut(root.clamp((root.time - 0.12) / 1.1, 0, 1))
            visible: ring > 0.001 && ring < 0.999
            width: root.far * 0.75 * ring * 2; height: width; radius: width / 2
            x: root.width / 2 - width / 2; y: root.centerY - height / 2
            color: "transparent"
            border.width: 3 * (1 - ring) + 1
            border.color: Qt.rgba(1, 0.92, 0.78, 0.35 * (1 - ring))
        }

        // Confetti: one burst of gold leaf from the card
        Canvas {
            id: confetti
            anchors.fill: parent
            property var pieces: []
            function seed() {
                var palette = ["#FFF4DC", "#F3D79F", "#DEB06C", "#C9974F", "#A47232", "#FFFFFF"];
                var count = root.liteMode ? 36 : 90;
                var out = [];
                for (var i = 0; i < count; i++) {
                    var angle = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 1.25;
                    var speed = 260 + Math.random() * 420;
                    out.push({ vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed, spin: (Math.random() - 0.5) * 720,
                               flutter: 4 + Math.random() * 8, w: 5 + Math.random() * 6, h: 3 + Math.random() * 4,
                               round: Math.random() < 0.25, color: palette[Math.floor(Math.random() * palette.length)] });
                }
                pieces = out;
            }
            Connections {
                target: root
                function onTimeChanged() { if (root.time < 3.2) confetti.requestPaint(); }
            }
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var t = root.time - 0.15;
                if (t <= 0 || t > 2.8) return;
                var unit = Math.min(width, height) / 400;
                var gravity = 900 * unit;
                var fade = root.clamp(1 - (t - 1.9) / 0.9, 0, 1);
                ctx.globalAlpha = fade;
                for (var i = 0; i < pieces.length; i++) {
                    var p = pieces[i];
                    var x = width / 2 + p.vx * unit * t + Math.sin(t * p.flutter) * 10 * unit;
                    var y = root.centerY + p.vy * unit * t + 0.5 * gravity * t * t;
                    if (y > height + 20) continue;
                    var pw = p.w * unit;
                    var ph = p.h * unit * (0.35 + 0.65 * Math.abs(Math.cos(t * p.flutter)));
                    ctx.save();
                    ctx.fillStyle = p.color;
                    ctx.translate(x, y);
                    ctx.rotate(p.spin * t * Math.PI / 180);
                    if (p.round) { ctx.beginPath(); ctx.arc(0, 0, pw / 2, 0, Math.PI * 2); ctx.fill(); }
                    else ctx.fillRect(-pw / 2, -ph / 2, pw, ph);
                    ctx.restore();
                }
            }
        }

        // The big hello, bottom left
        Column {
            id: hello
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 28; bottomMargin: 40 }
            readonly property real p: root.easeOut(root.clamp((root.time - 0.35) / 0.6, 0, 1))
            opacity: p
            transform: Translate { y: (1 - hello.p) * 40 }
            Text {
                text: root.helloLines[root.helloIndex % root.helloLines.length]
                color: "#FFFFFF"
                font.family: Theme.fontFamily
                font.pixelSize: 64
                font.weight: Font.Bold
                font.letterSpacing: -2
            }
            Text {
                text: root.subline
                color: "#FFFFFF"
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.Bold
            }
        }

        // Once the hello has settled, a quiet nudge that a click moves on
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            text: I18n.tr("BẤM ĐỂ TIẾP TỤC", "CLICK TO CONTINUE")
            color: "#FFFFFF"
            font.family: "monospace"
            font.pixelSize: 11
            font.letterSpacing: 2
            readonly property real p: root.clamp((root.time - 2.4) / 0.6, 0, 1)
            opacity: root.leaving ? 0 : p * (0.4 + 0.25 * Math.sin(root.time * 2.4))
        }
    }

    // The card: springs in turning from the side, then flies to the avatar
    Item {
        id: flyer
        width: root.cardWidth
        height: width / 1.89
        x: root.width / 2 - width / 2 + flyX
        y: root.centerY - height / 2 + flyY

        property real flyX: 0
        property real flyY: 0
        property real flyScale: 1
        readonly property real enter: root.easeOutBack(root.clamp(root.time / 0.75, 0, 1))

        scale: (0.6 + 0.4 * enter) * flyScale
        rotation: -8 * enter * flyScale
        transform: Rotation {
            origin.x: flyer.width / 2; origin.y: flyer.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: (1 - flyer.enter) * -55
        }

        ListenerCard {
            id: card
            anchors.fill: parent
            opacity: root.clamp(root.time / 0.25, 0, 1)
            userName: root.userName
            userTag: root.userTag
            avatarUrl: root.avatarUrl
            joinedAt: root.joinedAt
            cardNumber: root.cardNumber
            liteMode: root.liteMode
            interactive: false
            swayAmount: root.leaving ? 0 : 1
        }
    }

    SequentialAnimation {
        id: flyAnim
        ParallelAnimation {
            // x leads and y lags, so the card swings up and left along an arc instead of a straight line
            NumberAnimation { id: flyXAnim; target: flyer; property: "flyX"; duration: 760; easing.type: Easing.InOutCubic }
            NumberAnimation { id: flyYAnim; target: flyer; property: "flyY"; duration: 760; easing.type: Easing.InQuart }
            NumberAnimation { id: flySAnim; target: flyer; property: "flyScale"; duration: 760; easing.type: Easing.InOutQuart }
            NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
            SequentialAnimation {
                PauseAnimation { duration: 640 }
                NumberAnimation { target: flyer; property: "opacity"; to: 0; duration: 120 }
            }
        }
        ScriptAction { script: if (root.landed) root.landing(); }
        ScriptAction { script: root.close() }
    }
}
