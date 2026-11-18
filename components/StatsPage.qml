import QtQuick
import QtQuick.Layouts

// Stats: everything the play history says about one month or one year, after Mochy's Stats screen.
// A ruler of months (a tick a day, each as tall as that day's listening) picks the period;
// "Re'cap >" opens the month / year picker. Cards open into the detail behind them: a line of
// every day, the top ten, the genre split, the week and the clock. Genres are looked up by artist
// name only; nothing else leaves the computer.
Item {
    id: root

    property string apiUrl: "http://127.0.0.1:17890"
    property color accentColor: Theme.accent
    property bool liteMode: false
    property bool active: false

    signal backRequested()
    signal artistRequested(string name)
    signal trackRequested(var row)

    // ---- period -------------------------------------------------------------------------------
    readonly property date today: new Date()
    property string kind: "month"                  // "month" | "year"
    property int year: today.getFullYear()
    property int month: today.getMonth() + 1
    property var stats: null
    property var genres: null                      // null = loading, [] = none could be named
    property int genreTries: 0
    property var expanded: ({})
    readonly property var cardKeys: ["total", "genre", "artist", "song", "weekday", "hour"]
    readonly property bool allOpen: cardKeys.every(k => root.expanded[k] === true)
    // bumped on every new period, so figures roll and charts grow in again
    property int generation: 0

    readonly property date firstDay: {
        var f = root.stats && root.stats.first_day ? root.stats.first_day : "";
        return f ? new Date(f + "T00:00:00") : root.today;
    }

    // ---- colour and type ----------------------------------------------------------------------
    // The one accent marks peaks: the wallpaper or song hue, lifted so it reads on the dark cards
    readonly property color ink: Theme.textPrimary
    readonly property color inkSecondary: Qt.rgba(1, 1, 1, 0.72)
    readonly property color inkMuted: Qt.rgba(1, 1, 1, 0.48)
    readonly property color mark: Qt.hsla(root.accentColor.hslHue < 0 ? 0.33 : root.accentColor.hslHue,
                                          Math.max(0.55, root.accentColor.hslSaturation), 0.70, 1)
    readonly property color cardFill: Qt.rgba(0.03 + root.accentColor.r * 0.06, 0.03 + root.accentColor.g * 0.06,
                                              0.04 + root.accentColor.b * 0.08, 0.62)
    readonly property color chipFill: Qt.rgba(root.accentColor.r * 0.35, root.accentColor.g * 0.35, root.accentColor.b * 0.35, 0.55)
    readonly property color grid: Qt.rgba(1, 1, 1, 0.09)
    // categorical order for genres on the dark card, taken from Mochy (validated for colour blindness)
    readonly property var genreColors: ["#3987E5", "#D95926", "#199E70", "#C98500", "#D55181"]
    readonly property color genreOther: "#5A5A5A"

    // Canvas takes one family name, not the CSS-style list Theme carries
    readonly property string canvasFamily: Theme.fontFamily.split(",")[0].trim()
    readonly property var numberLocale: Qt.locale(I18n.locale === "vi" ? "vi_VN" : "en_US")
    function fmt(n) { return Number(n || 0).toLocaleString(root.numberLocale, "f", 0); }
    function shortDuration(min) {
        var m = Math.max(0, Math.round(min || 0));
        var u = I18n.tr("p", "m");
        return m >= 60 ? Math.floor(m / 60) + I18n.tr("g ", "h ") + String(m % 60).padStart(2, "0") + u : m + u;
    }
    function hoursDecimal(min) { return (Math.round((min || 0) / 6) / 10).toLocaleString(root.numberLocale, "f", 1); }
    function monthName(m) {
        return I18n.tr("Tháng " + m, Qt.locale("en_US").standaloneMonthName(m - 1, Locale.LongFormat));
    }
    function monthShort(m) {
        return I18n.tr("Th" + m, Qt.locale("en_US").standaloneMonthName(m - 1, Locale.ShortFormat));
    }
    readonly property var weekdayNames: I18n.locale === "vi"
        ? ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"]
        : ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    readonly property var weekdayLetters: I18n.locale === "vi" ? ["T2", "T3", "T4", "T5", "T6", "T7", "CN"] : ["M", "T", "W", "T", "F", "S", "S"]
    function hourLabel(h) { return String(h).padStart(2, "0") + ":00"; }
    function timeOfDay(h) {
        if (h < 5) return I18n.tr("đêm khuya", "late night");
        if (h < 11) return I18n.tr("buổi sáng", "morning");
        if (h < 14) return I18n.tr("buổi trưa", "midday");
        if (h < 18) return I18n.tr("buổi chiều", "afternoon");
        if (h < 22) return I18n.tr("buổi tối", "evening");
        return I18n.tr("đêm khuya", "late night");
    }
    function argmax(a) {
        var best = 0;
        for (var i = 1; i < (a || []).length; i++) if (a[i] > a[best]) best = i;
        return best;
    }
    function periodLabel() {
        return root.kind === "month" ? I18n.tr("Tháng này", "This month") : I18n.tr("Năm nay", "This year");
    }

    // ---- loading ------------------------------------------------------------------------------
    function load() {
        var m = root.kind === "month" ? root.month : 0;
        var q = "?year=" + root.year + "&month=" + m;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.apiUrl + "/api/listening/stats" + q);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try {
                var res = JSON.parse(xhr.responseText);
                if (res && res.success) { root.stats = res.stats; root.generation++; }
            } catch (e) {}
        };
        xhr.send();
        root.genres = null;
        root.genreTries = 0;
        root.loadGenres();
    }
    function loadGenres() {
        var m = root.kind === "month" ? root.month : 0;
        var q = "?year=" + root.year + "&month=" + m;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.apiUrl + "/api/listening/genres" + q);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try {
                var res = JSON.parse(xhr.responseText);
                if (res && res.success) {
                    root.genres = res.genres || [];
                    // a few artists are asked per call; come back for the rest
                    if (res.pending && root.genreTries < 3) { root.genreTries++; genreRetry.restart(); }
                } else if (root.genres === null) root.genres = [];
            } catch (e) { if (root.genres === null) root.genres = []; }
        };
        xhr.send();
    }
    Timer { id: genreRetry; interval: 3500; onTriggered: root.loadGenres() }

    function select(k, y, m) {
        if (k === root.kind && y === root.year && (k === "year" || m === root.month)) return;
        root.kind = k; root.year = y; root.month = m;
        root.load();
    }
    onActiveChanged: if (active) { root.load(); ruler.snap(); root.reveal = 0; revealAnim.restart(); }

    function toggle(key) {
        var e = Object.assign({}, root.expanded);
        e[key] = !e[key];
        root.expanded = e;
    }
    function setAll(open) {
        var e = {};
        root.cardKeys.forEach(k => e[k] = open);
        root.expanded = e;
    }

    // 0..1 rise of the rows, one after another, when the page opens
    property real reveal: 1
    NumberAnimation {
        id: revealAnim
        target: root; property: "reveal"; from: 0; to: 1
        duration: root.liteMode ? 1 : 1100
    }
    function rowProgress(i) {
        var t = Math.max(0, Math.min(1, root.reveal * 1.6 - i * 0.07));
        return 1 - Math.pow(1 - t, 3);
    }

    Keys.onEscapePressed: root.backRequested()

    // ---- building blocks ----------------------------------------------------------------------

    // Odometer: each digit rolls up through 0..9 to its value, the higher places a touch later
    component Odometer: Row {
        id: odo
        property string text: "0"
        property int pixelSize: 52
        property int gen: 0
        property real roll: 1
        onGenChanged: { roll = 0; rollAnim.restart(); }
        Component.onCompleted: { roll = 0; rollAnim.restart(); }
        NumberAnimation {
            id: rollAnim
            target: odo; property: "roll"; from: 0; to: 1
            duration: root.liteMode ? 1 : 1400
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
        Repeater {
            model: odo.text.split("")
            delegate: Item {
                id: digit
                required property string modelData
                required property int index
                readonly property bool isDigit: /[0-9]/.test(modelData)
                readonly property real lag: (odo.text.length - 1 - index) * 0.08
                readonly property real t: Math.max(0, Math.min(1, (odo.roll - lag) / (1 - lag)))
                width: probe.implicitWidth
                height: probe.implicitHeight
                clip: true
                Text {
                    id: probe
                    visible: !digit.isDigit
                    text: digit.isDigit ? "0" : digit.modelData
                    color: root.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: odo.pixelSize
                    font.weight: Font.Bold
                    font.letterSpacing: -odo.pixelSize * 0.045
                    font.features: { "tnum": 1 }
                }
                Column {
                    visible: digit.isDigit
                    // one full lap plus the digit, so even a 0 rolls
                    y: -(digit.isDigit ? (10 + parseInt(digit.modelData)) * digit.t : 0) * digit.height
                    Repeater {
                        model: 20
                        Text {
                            required property int index
                            height: digit.height
                            text: index % 10
                            color: root.ink
                            font: probe.font
                        }
                    }
                }
            }
        }
    }

    component Chevron: Item {
        property bool open: false
        width: 18; height: 18
        AppIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/icons/go-next-symbolic.svg")
            iconSize: 14
            color: root.ink
            rotation: parent.open ? -90 : 90
            Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
        }
    }

    // A card; clicking it opens the detail under its summary
    component StatsCard: Rectangle {
        id: sc
        property string key: ""
        property int order: 0
        property Component detail: null
        default property alias content: summary.data
        readonly property bool open: key !== "" && root.expanded[key] === true
        readonly property real p: root.rowProgress(3 + order)
        Layout.fillWidth: true
        Layout.topMargin: 7
        Layout.bottomMargin: 7
        implicitHeight: summary.implicitHeight + 32 + detailBox.height
        radius: 22
        color: root.cardFill
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, hover.hovered && sc.detail ? 0.14 : 0.07)
        opacity: p
        transform: Translate { y: (1 - sc.p) * 26 }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        HoverHandler { id: hover; enabled: sc.detail !== null; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: sc.detail !== null; onTapped: root.toggle(sc.key) }

        ColumnLayout {
            id: summary
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors { leftMargin: 22; rightMargin: sc.detail ? 52 : 18; topMargin: 18 }
            spacing: 0
        }
        Rectangle {
            visible: sc.detail !== null
            anchors { right: parent.right; rightMargin: 16; top: summary.bottom; topMargin: -26 }
            width: 26; height: 26; radius: 7
            color: root.chipFill
            Chevron { anchors.centerIn: parent; open: sc.open }
        }
        // The detail opens and closes with a height animation; it is only built while open
        Item {
            id: detailBox
            anchors { left: parent.left; right: parent.right; top: summary.bottom }
            anchors { leftMargin: 22; rightMargin: 20 }
            clip: true
            height: sc.open ? detailLoader.implicitHeight + 22 : 0
            opacity: sc.open ? 1 : 0
            Behavior on height { NumberAnimation { duration: root.liteMode ? 1 : 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Loader {
                id: detailLoader
                y: 18
                width: parent.width
                active: sc.open || detailBox.height > 0
                sourceComponent: sc.detail
            }
        }
    }

    component Label: Text {
        property real size: 15
        property bool strong: true
        color: root.ink
        font.family: Theme.fontFamily
        font.pixelSize: size
        font.weight: strong ? Font.Bold : Font.DemiBold
        font.letterSpacing: -0.02 * size
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    // Listening over time: a line with a soft area under it, the peak marked; hover reads any point
    component LineChart: Canvas {
        id: lc
        property var values: []
        property var labelAt: function(i) { return null; }
        property var nameOf: function(i) { return ""; }
        property real grow: 0
        property int hovered: -1
        implicitHeight: 150
        Layout.fillWidth: true
        Component.onCompleted: growAnim.restart()
        NumberAnimation { id: growAnim; target: lc; property: "grow"; from: 0; to: 1; duration: root.liteMode ? 1 : 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        onGrowChanged: requestPaint()
        onHoveredChanged: requestPaint()
        onValuesChanged: { growAnim.restart(); }
        onWidthChanged: requestPaint()
        HoverHandler {
            id: lh
            onPointChanged: {
                var n = lc.values.length;
                lc.hovered = (hovered && n > 1) ? Math.max(0, Math.min(n - 1, Math.round(point.position.x / (lc.width / (n - 1))))) : -1;
            }
            onHoveredChanged: if (!hovered) lc.hovered = -1
        }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var v = values || [], n = v.length;
            if (n === 0) return;
            var top = 26, bottom = height - 20;
            var maxV = Math.max(1, Math.max.apply(null, v));
            var step = n > 1 ? width / (n - 1) : width;
            function px(i) { return i * step; }
            function py(i) { return bottom - (v[i] / maxV) * (bottom - top); }
            ctx.strokeStyle = root.grid; ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(0, bottom); ctx.lineTo(width, bottom); ctx.stroke();
            ctx.setLineDash([6, 6]);
            ctx.beginPath(); ctx.moveTo(0, (top + bottom) / 2); ctx.lineTo(width, (top + bottom) / 2); ctx.stroke();
            ctx.setLineDash([]);
            ctx.fillStyle = root.inkMuted;
            ctx.font = "11px '" + root.canvasFamily + "'";
            ctx.fillText(root.shortDuration(maxV), 0, top - 10);
            ctx.save();
            ctx.beginPath(); ctx.rect(0, 0, width * grow, height); ctx.clip();
            var path = function() {
                ctx.moveTo(px(0), py(0));
                for (var i = 1; i < n; i++) {
                    var mid = (px(i - 1) + px(i)) / 2;
                    ctx.bezierCurveTo(mid, py(i - 1), mid, py(i), px(i), py(i));
                }
            };
            var g = ctx.createLinearGradient(0, top, 0, bottom);
            g.addColorStop(0, Qt.rgba(root.mark.r, root.mark.g, root.mark.b, 0.24));
            g.addColorStop(1, Qt.rgba(root.mark.r, root.mark.g, root.mark.b, 0));
            ctx.beginPath(); ctx.moveTo(px(0), bottom); ctx.lineTo(px(0), py(0)); path(); ctx.lineTo(px(n - 1), bottom); ctx.closePath();
            ctx.fillStyle = g; ctx.fill();
            ctx.beginPath(); path();
            ctx.strokeStyle = root.mark; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.stroke();
            ctx.restore();
            ctx.fillStyle = root.inkMuted;
            for (var k = 0; k < n; k++) {
                var lab = labelAt(k);
                if (lab === null || lab === undefined) continue;
                var w = ctx.measureText(lab).width;
                ctx.fillText(lab, Math.max(0, Math.min(width - w, px(k) - w / 2)), bottom + 15);
            }
            var shown = hovered >= 0 ? hovered : root.argmax(v);
            if (grow > 0.98 && (v[shown] > 0 || hovered >= 0)) {
                var x = px(shown), y = py(shown);
                if (hovered >= 0) {
                    ctx.strokeStyle = root.inkMuted; ctx.lineWidth = 1;
                    ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
                }
                ctx.fillStyle = "#0F0F0F"; ctx.beginPath(); ctx.arc(x, y, 6, 0, Math.PI * 2); ctx.fill();
                ctx.fillStyle = root.mark; ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
                root.tooltip(ctx, nameOf(shown) + " · " + root.shortDuration(v[shown]), x, y, width);
            }
        }
    }
    function tooltip(ctx, text, ax, ay, w) {
        ctx.font = "600 12px '" + root.canvasFamily + "'";
        var tw = ctx.measureText(text).width, bw = tw + 16, bh = 22;
        var x = Math.max(0, Math.min(w - bw, ax - bw / 2)), y = Math.max(0, ay - bh - 8);
        ctx.fillStyle = Qt.rgba(root.accentColor.r * 0.25 + 0.1, root.accentColor.g * 0.25 + 0.1, root.accentColor.b * 0.25 + 0.1, 0.96);
        ctx.beginPath(); ctx.roundedRect(x, y, bw, bh, bh / 2, bh / 2); ctx.fill();
        ctx.fillStyle = root.ink;
        ctx.fillText(text, x + 8, y + 15);
    }

    // Seven bars, Monday first; the busiest day in the accent, the rest neutral
    component WeekBars: Canvas {
        id: wb
        property var values: []
        property real grow: 0
        property int hovered: -1
        implicitHeight: 150
        Layout.fillWidth: true
        Component.onCompleted: wbGrow.restart()
        NumberAnimation { id: wbGrow; target: wb; property: "grow"; from: 0; to: 1; duration: root.liteMode ? 1 : 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        onGrowChanged: requestPaint()
        onHoveredChanged: requestPaint()
        onWidthChanged: requestPaint()
        HoverHandler {
            onPointChanged: wb.hovered = hovered ? Math.max(0, Math.min(6, Math.floor(point.position.x / (wb.width / 7)))) : -1
            onHoveredChanged: if (!hovered) wb.hovered = -1
        }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var v = values || [];
            if (v.length !== 7) return;
            var top = 28, bottom = height - 20, slot = width / 7;
            var barW = Math.min(slot * 0.46, 26), r = 5;
            var maxV = Math.max(1, Math.max.apply(null, v)), peak = root.argmax(v);
            ctx.strokeStyle = root.grid; ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(0, bottom); ctx.lineTo(width, bottom); ctx.stroke();
            ctx.font = "11px '" + root.canvasFamily + "'";
            for (var i = 0; i < 7; i++) {
                var h = (v[i] / maxV) * (bottom - top) * grow;
                var x = slot * i + (slot - barW) / 2;
                ctx.fillStyle = i === peak ? root.mark : Qt.rgba(1, 1, 1, i === hovered ? 0.34 : 0.2);
                if (h > 0.5) {
                    // rounded only at the data end; the base sits square on the baseline
                    var rr = Math.min(r, h);
                    ctx.beginPath();
                    ctx.moveTo(x, bottom); ctx.lineTo(x, bottom - h + rr);
                    ctx.quadraticCurveTo(x, bottom - h, x + rr, bottom - h);
                    ctx.lineTo(x + barW - rr, bottom - h);
                    ctx.quadraticCurveTo(x + barW, bottom - h, x + barW, bottom - h + rr);
                    ctx.lineTo(x + barW, bottom); ctx.closePath(); ctx.fill();
                }
                ctx.fillStyle = root.inkMuted;
                var lab = root.weekdayLetters[i], lw = ctx.measureText(lab).width;
                ctx.fillText(lab, slot * i + slot / 2 - lw / 2, bottom + 15);
            }
            var shown = hovered >= 0 ? hovered : peak;
            if (grow > 0.98 && v[shown] > 0) {
                var hh = (v[shown] / maxV) * (bottom - top);
                root.tooltip(ctx, root.shortDuration(v[shown]), slot * shown + slot / 2, bottom - hh, width);
            }
        }
    }

    // The genre ring: the top five in categorical order, the rest folded into one grey slice
    component Donut: Canvas {
        id: dn
        property var shares: []
        property real grow: 0
        width: 96; height: 96
        Component.onCompleted: dnGrow.restart()
        NumberAnimation { id: dnGrow; target: dn; property: "grow"; from: 0; to: 1; duration: root.liteMode ? 1 : 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        onGrowChanged: requestPaint()
        onSharesChanged: dnGrow.restart()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var stroke = 13, rad = width / 2 - stroke / 2, gap = 2 / rad;
            var a = -Math.PI / 2, total = Math.PI * 2 * grow;
            var slices = root.slices(shares);
            ctx.lineWidth = stroke; ctx.lineCap = "butt";
            for (var i = 0; i < slices.length; i++) {
                var sweep = slices[i].fraction * total;
                if (sweep > gap) {
                    ctx.strokeStyle = slices[i].color;
                    ctx.beginPath(); ctx.arc(width / 2, height / 2, rad, a + gap / 2, a + sweep - gap / 2); ctx.stroke();
                }
                a += sweep;
            }
        }
    }
    function slices(shares) {
        var out = [], rest = 0;
        (shares || []).forEach((g, i) => {
            if (i < root.genreColors.length) out.push({ fraction: g.fraction, color: root.genreColors[i] });
            else rest += g.fraction;
        });
        if (rest > 0.001) out.push({ fraction: rest, color: root.genreOther });
        return out;
    }

    // Ranked rows: number, picture, name, detail, and a share bar against the #1
    component RankList: ColumnLayout {
        id: rl
        property var rows: []          // { title, detail, value, image, swatch, circle, onTap }
        Layout.fillWidth: true
        spacing: 12
        readonly property real best: Math.max(1, ...(rows.length ? rows.map(r => r.value || 0) : [1]))
        Repeater {
            model: rl.rows
            delegate: RowLayout {
                id: row
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.preferredWidth: 22
                    text: String(row.index + 1).padStart(2, "0")
                    color: root.inkMuted
                    font.family: "monospace"
                    font.pixelSize: 13
                }
                RoundedImage {
                    visible: !row.modelData.swatch
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: row.modelData.circle ? 20 : 8
                    sourceSize: Qt.size(96, 96)
                    source: row.modelData.image || ""
                    initialsText: row.modelData.title || ""
                    fallbackIconColor: root.accentColor
                }
                Rectangle {
                    visible: !!row.modelData.swatch
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    radius: 6
                    color: row.modelData.swatch || "transparent"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title || ""
                        elide: Text.ElideRight
                        color: root.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.detail || ""
                        elide: Text.ElideRight
                        color: root.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 5
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: root.grid
                        Rectangle {
                            height: parent.height
                            radius: 1.5
                            width: parent.width * Math.max(0.02, Math.min(1, (row.modelData.value || 0) / rl.best))
                            color: row.index === 0 ? root.mark : Qt.rgba(1, 1, 1, 0.4)
                        }
                    }
                }
                HoverHandler { enabled: !!row.modelData.onTap; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !!row.modelData.onTap; onTapped: row.modelData.onTap() }
            }
        }
    }

    // ---- the page -----------------------------------------------------------------------------
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 64 + 150   // clears the floating player bar
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: Math.min(parent.width - 48, 760)
            anchors.horizontalCenter: parent.horizontalCenter
            y: 64
            spacing: 0

            // "Stats  2026 Re'cap >"
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: root.rowProgress(0)
                Text {
                    text: I18n.tr("Thống kê", "Stats")
                    color: root.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    font.letterSpacing: -1.6
                }
                Text {
                    id: recapLink
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 7
                    text: I18n.tr("Tổng kết " + root.year, root.year + " recap") + "  >"
                    color: recapHover.hovered ? root.inkSecondary : root.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.6
                    HoverHandler { id: recapHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: picker.open = !picker.open }
                }
                Item { Layout.fillWidth: true }
            }

            StatsRuler {
                id: ruler
                Layout.fillWidth: true
                Layout.topMargin: 6
                opacity: root.rowProgress(1)
            }

            // "Expand all"
            Rectangle {
                Layout.topMargin: 4
                Layout.bottomMargin: 10
                implicitWidth: expandRow.implicitWidth + 24
                implicitHeight: 32
                radius: 16
                color: expandHover.hovered ? Qt.lighter(root.chipFill, 1.3) : root.chipFill
                opacity: root.rowProgress(2)
                Behavior on color { ColorAnimation { duration: 150 } }
                Row {
                    id: expandRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.allOpen ? I18n.tr("Thu gọn tất cả", "Collapse all") : I18n.tr("Mở rộng tất cả", "Expand all")
                        color: root.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Chevron { anchors.verticalCenter: parent.verticalCenter; open: root.allOpen }
                }
                HoverHandler { id: expandHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.setAll(!root.allOpen) }
            }

            // Loading or nothing played
            StatsCard {
                visible: !root.stats || (root.stats.plays || 0) === 0
                order: 0
                Label {
                    text: !root.stats ? I18n.tr("Đang đếm lại từng phút...", "Counting every minute...")
                        : (root.kind === "month"
                           ? I18n.tr("Chưa nghe bài nào trong " + root.monthName(root.month).toLowerCase() + " " + root.year + ".",
                                     "Nothing played in " + root.monthName(root.month) + " " + root.year + " yet.")
                           : I18n.tr("Chưa nghe bài nào trong năm " + root.year + ".", "Nothing played in " + root.year + " yet."))
                    size: 17
                }
                Label {
                    visible: !!root.stats
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    text: I18n.tr("Nghe vài bài là chỗ này tự đầy lên.", "Play a few songs and this fills itself in.")
                    size: 13; strong: false; color: root.inkMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: !!root.stats && (root.stats.plays || 0) > 0
                readonly property var s: root.stats || {}

                // ---- total ----
                StatsCard {
                    key: "total"; order: 0
                    detail: Component {
                        ColumnLayout {
                            spacing: 8
                            Label {
                                text: root.kind === "month"
                                    ? I18n.tr("Từng ngày trong " + root.monthName(root.month).toLowerCase(), "Every day of " + root.monthName(root.month))
                                    : I18n.tr("Từng tháng trong năm " + root.year, "Every month of " + root.year)
                                size: 13; strong: false; color: root.inkMuted
                            }
                            LineChart {
                                values: (root.stats && root.stats.day_minutes) || []
                                labelAt: root.kind === "month" ? (i => (i === 0 || (i + 1) % 7 === 0) ? String(i + 1) : null)
                                                               : (i => i % 3 === 0 ? root.monthShort(i + 1) : null)
                                nameOf: root.kind === "month" ? (i => (i + 1) + "/" + root.month) : (i => root.monthName(i + 1))
                            }
                        }
                    }
                    Label { text: I18n.pick("stats.hours", [root.periodLabel() + ", bạn đã nghe nhạc suốt", root.periodLabel() + ", tai bạn đã làm việc suốt", root.periodLabel() + ", bạn đã ôm tai nghe suốt", root.periodLabel() + ", nhạc đã ở bên bạn suốt", root.periodLabel() + ", bạn đã quẩy suốt", root.periodLabel() + ", bạn đã chữa lành bằng nhạc suốt", root.periodLabel() + ", bạn nghiện nhạc tới mức nghe suốt"], [root.periodLabel() + ", you've been listening for", root.periodLabel() + ", your ears worked for", root.periodLabel() + ", your headphones stayed on for", root.periodLabel() + ", music kept you company for", root.periodLabel() + ", you've been vibing for", root.periodLabel() + ", you've been healing with music for", root.periodLabel() + ", you were hooked for"]) }
                    Row {
                        Layout.topMargin: 2
                        readonly property int minutes: (root.stats && root.stats.total_minutes) || 0
                        Odometer { text: String(Math.floor(parent.minutes / 60)); gen: root.generation }
                        Label { anchors.bottom: parent.bottom; anchors.bottomMargin: 10; text: I18n.tr("g", "h"); size: 22; Layout.fillWidth: false }
                        Item { width: 14; height: 1 }
                        Odometer { text: String(parent.minutes % 60).padStart(2, "0"); gen: root.generation }
                        Label { anchors.bottom: parent.bottom; anchors.bottomMargin: 10; text: I18n.tr("p", "m"); size: 22; Layout.fillWidth: false }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: root.grid }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        spacing: 14
                        Repeater {
                            model: {
                                var s = root.stats || {};
                                return [
                                    I18n.tr(root.fmt(s.song_count) + " bài hát", root.fmt(s.song_count) + (s.song_count === 1 ? " song" : " songs")),
                                    I18n.tr(root.fmt(s.artist_count) + " nghệ sĩ", root.fmt(s.artist_count) + (s.artist_count === 1 ? " artist" : " artists")),
                                    // many streamed songs carry no album; a zero would only read as broken
                                    (s.album_count || 0) > 0 ? I18n.tr(root.fmt(s.album_count) + " album", root.fmt(s.album_count) + (s.album_count === 1 ? " album" : " albums")) : null,
                                    I18n.tr(root.fmt(s.plays) + " lượt phát", root.fmt(s.plays) + (s.plays === 1 ? " play" : " plays"))
                                ].filter(x => x !== null);
                            }
                            delegate: Row {
                                required property string modelData
                                spacing: 6
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 11; height: 11; radius: 3; color: Qt.rgba(1, 1, 1, 0.85) }
                                Text {
                                    text: parent.modelData
                                    color: root.inkSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                // ---- genre ----
                StatsCard {
                    id: genreCard
                    key: "genre"; order: 1
                    readonly property var shares: root.genres || []
                    detail: shares.length ? genreDetail : null
                    Component {
                        id: genreDetail
                        RankList {
                            rows: (root.genres || []).map((g, i) => ({
                                title: g.name,
                                detail: Math.round(g.fraction * 100) + "% · " + root.shortDuration(g.minutes),
                                value: g.minutes,
                                swatch: i < root.genreColors.length ? root.genreColors[i] : root.genreOther
                            }))
                        }
                    }
                    Label { text: I18n.tr("Thể loại nổi bật", "Dominant genre") }
                    Label {
                        visible: genreCard.shares.length === 0
                        Layout.topMargin: 14; Layout.bottomMargin: 10
                        text: root.genres === null ? I18n.tr("Đang phân loại thể loại của bạn...", "Sorting your genres...")
                            : I18n.tr("Chưa gọi tên được thể loại lúc này. Lần đầu cần có mạng.",
                                      "Couldn't name your genres right now. This needs a connection the first time.")
                        size: 14; strong: false; color: root.inkMuted
                    }
                    Label {
                        visible: genreCard.shares.length > 0
                        text: genreCard.shares.length ? genreCard.shares[0].name : ""
                        size: 24; elide: Text.ElideRight; wrapMode: Text.NoWrap
                    }
                    RowLayout {
                        visible: genreCard.shares.length > 0
                        Layout.topMargin: 14
                        spacing: 14
                        Donut { shares: root.genres || [] }
                        Rectangle { Layout.preferredWidth: 34; Layout.preferredHeight: 1; color: root.inkSecondary }
                        ColumnLayout {
                            spacing: 0
                            Label { text: (genreCard.shares.length ? Math.round(genreCard.shares[0].fraction * 100) : 0) + "%"; size: 22; Layout.fillWidth: false }
                            Label { text: genreCard.shares.length ? genreCard.shares[0].name : ""; size: 12; strong: false; color: root.inkSecondary; Layout.fillWidth: false }
                        }
                    }
                    // identity never by colour alone: the top five are named under the ring
                    Flow {
                        visible: genreCard.shares.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        spacing: 12
                        Repeater {
                            model: (root.genres || []).slice(0, 5)
                            delegate: Row {
                                required property var modelData
                                required property int index
                                spacing: 5
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: root.genreColors[parent.index] }
                                Text { text: parent.modelData.name; color: root.inkMuted; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium }
                            }
                        }
                    }
                }

                // ---- artist ----
                StatsCard {
                    id: artistCard
                    key: "artist"; order: 2
                    readonly property var lead: ((root.stats && root.stats.top_artists) || [])[0] || null
                    visible: !!lead
                    detail: Component {
                        RankList {
                            rows: ((root.stats && root.stats.top_artists) || []).slice(0, 10).map(a => ({
                                title: a.artist,
                                detail: I18n.tr(root.shortDuration(a.minutes) + " · " + root.fmt(a.plays) + " lượt phát",
                                                root.shortDuration(a.minutes) + " · " + root.fmt(a.plays) + (a.plays === 1 ? " play" : " plays")),
                                value: a.minutes, image: a.photo_url || a.cover_url, circle: true,
                                onTap: () => root.artistRequested(a.artist)
                            }))
                        }
                    }
                    Label { text: I18n.tr("Bạn thực sự rất thích nghe nghệ sĩ này", "You really love listening to this artist") }
                    RowLayout {
                        Layout.topMargin: 12
                        spacing: 16
                        RoundedImage {
                            Layout.preferredWidth: 80; Layout.preferredHeight: 80; radius: 40
                            sourceSize: Qt.size(180, 180)
                            source: artistCard.lead ? (artistCard.lead.photo_url || artistCard.lead.cover_url || "") : ""
                            initialsText: artistCard.lead ? artistCard.lead.artist : ""
                            fallbackIconColor: root.accentColor
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            readonly property var a: artistCard.lead || {}
                            Label { text: parent.a.artist || ""; size: 24; maximumLineCount: 2; elide: Text.ElideRight }
                            Label {
                                text: I18n.tr(root.shortDuration(parent.a.minutes) + " thời gian nghe và " + root.fmt(parent.a.plays) + " lượt phát từ " + (parent.a.artist || ""),
                                              root.shortDuration(parent.a.minutes) + " playtime and " + root.fmt(parent.a.plays) + " plays from " + (parent.a.artist || ""))
                                size: 12; strong: false; color: root.inkMuted; maximumLineCount: 2; elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ---- song ----
                StatsCard {
                    id: songCard
                    key: "song"; order: 3
                    readonly property var lead: ((root.stats && root.stats.top_songs) || [])[0] || null
                    readonly property var t: lead || {}
                    visible: !!lead
                    detail: Component {
                        RankList {
                            rows: ((root.stats && root.stats.top_songs) || []).slice(0, 10).map(t => ({
                                title: t.title,
                                detail: I18n.tr((t.artist || "") + " · " + root.fmt(t.plays) + " lượt phát · " + root.shortDuration(t.minutes),
                                                (t.artist || "") + " · " + root.fmt(t.plays) + (t.plays === 1 ? " play · " : " plays · ") + root.shortDuration(t.minutes)),
                                value: t.plays, image: t.cover_url, circle: false,
                                onTap: () => root.trackRequested(t)
                            }))
                        }
                    }
                    Label { text: I18n.tr("Và bạn không hề hay biết, bài này là số 1 của bạn", "And without noticing, this song is your #1") }
                    RowLayout {
                        Layout.topMargin: 12
                        spacing: 16
                        
                        RoundedImage {
                            Layout.preferredWidth: 78; Layout.preferredHeight: 78; radius: 12
                            sourceSize: Qt.size(180, 180)
                            source: songCard.t.cover_url || ""
                            initialsText: songCard.t.title || ""
                            fallbackIconColor: root.accentColor
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: I18n.tr((songCard.t.title || "") + " của " + (songCard.t.artist || ""), (songCard.t.title || "") + " from " + (songCard.t.artist || ""))
                                size: 20; maximumLineCount: 2; elide: Text.ElideRight
                            }
                            Label {
                                text: I18n.tr(root.shortDuration(songCard.t.minutes) + " thời gian nghe và " + root.fmt(songCard.t.plays) + " lượt phát",
                                              root.shortDuration(songCard.t.minutes) + " playtime and " + root.fmt(songCard.t.plays) + " plays")
                                size: 12; strong: false; color: root.inkMuted
                            }
                        }
                    }
                }

                Label {
                    Layout.topMargin: 18
                    Layout.bottomMargin: 10
                    Layout.leftMargin: 4
                    text: I18n.tr("Xem bạn thường nghe nhạc lúc nào nhé", "Let's see when you like to listen to music")
                    size: 16
                    opacity: root.rowProgress(8)
                }

                // ---- weekday ----
                StatsCard {
                    id: weekCard
                    key: "weekday"; order: 4
                    readonly property var w: (root.stats && root.stats.weekday_minutes) || [0, 0, 0, 0, 0, 0, 0]
                    readonly property int best: root.argmax(w)
                    detail: Component { WeekBars { values: (root.stats && root.stats.weekday_minutes) || [] } }
                    Label { text: I18n.pick("stats.weekday", [root.periodLabel() + ", bạn hay nghe nhạc nhất vào", root.periodLabel() + ", tai bạn bận rộn nhất vào", root.periodLabel() + ", bạn quẩy nhiều nhất vào", root.periodLabel() + ", ngày bạn mê nhạc nhất là", root.periodLabel() + ", nhạc cứu rỗi bạn nhiều nhất vào", root.periodLabel() + ", tai nghe làm việc cật lực nhất vào", root.periodLabel() + ", bạn bật nhạc nhiều nhất vào"], [root.periodLabel() + ", you usually listen to music on", root.periodLabel() + ", your ears are busiest on", root.periodLabel() + ", you party the most on", root.periodLabel() + ", the day you love music most is", root.periodLabel() + ", music saves you most on", root.periodLabel() + ", your headphones work hardest on", root.periodLabel() + ", you press play the most on"]); size: 13 }
                    Label { Layout.topMargin: 2; text: root.weekdayNames[weekCard.best]; size: 32 }
                    Label {
                        text: I18n.tr("tổng cộng " + root.hoursDecimal(weekCard.w[weekCard.best]) + " giờ",
                                      "totaling " + root.hoursDecimal(weekCard.w[weekCard.best]) + " hours")
                        size: 12; strong: false; color: root.inkSecondary
                    }
                }

                // ---- hour ----
                StatsCard {
                    id: hourCard
                    key: "hour"; order: 5
                    readonly property var h: (root.stats && root.stats.hour_minutes) || []
                    readonly property int best: root.argmax(h)
                    detail: Component {
                        LineChart {
                            values: (root.stats && root.stats.hour_minutes) || []
                            labelAt: i => i % 6 === 0 ? root.hourLabel(i) : null
                            nameOf: i => root.hourLabel(i)
                        }
                    }
                    Label {
                        text: I18n.tr("Và bạn thích nghe nhạc nhất vào " + root.timeOfDay(hourCard.best) + ", khoảng",
                                      "And you love to listen in the " + root.timeOfDay(hourCard.best) + ", right around")
                        size: 13
                    }
                    Label { Layout.topMargin: 2; text: root.hourLabel(hourCard.best); size: 32 }
                    Label {
                        text: I18n.tr("tổng cộng " + root.hoursDecimal(hourCard.h[hourCard.best] || 0) + " giờ vào khung giờ này!",
                                      "totaling " + root.hoursDecimal(hourCard.h[hourCard.best] || 0) + " hours at this time!")
                        size: 12; strong: false; color: root.inkSecondary
                    }
                }

                Label {
                    Layout.topMargin: 10
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    text: I18n.tr("Mọi dữ liệu ở đây được ghi lại từ việc bạn dùng Nutsty trên máy này và KHÔNG BAO GIỜ được gửi tới máy chủ nào! (Thể loại chỉ được tra theo tên nghệ sĩ.)",
                                  "Everything here comes from how you use Nutsty on this computer and is NEVER sent to any server! (Genres are looked up by artist name only.)")
                    size: 11; strong: false; color: root.inkMuted
                    opacity: root.rowProgress(10)
                }
            }
        }
    }

    ScrollEdgeFade {
        flickable: flick
        fadeLength: 40
    }

    // ---- the ruler ----------------------------------------------------------------------------
    // Every month of the year (or a run of years) on one line, a tick a day. The chosen period sits
    // at the left with its name large; dragging lifts the marker to the middle and slides the ruler
    // under it, letting go settles what is under it back at the left. Periods with nothing to show
    // are grey, and landing on one springs back. Nutsty's own touch: each day's tick is as tall as
    // that day's listening, so the ruler doubles as a small chart of the year.
    component StatsRuler: Canvas {
        id: rc
        implicitHeight: 92
        readonly property real itemW: 160
        readonly property real restAnchor: 44
        property real pos: 0          // fractional index under the marker
        property real lift: 0         // 0 = marker at rest on the left, 1 = in the middle
        property bool dragging: false
        readonly property var items: {
            var out = [];
            if (root.kind === "month") {
                for (var m = 1; m <= 12; m++) out.push({ year: root.year, month: m });
            } else {
                var first = Math.min(root.firstDay.getFullYear(), root.today.getFullYear()) - 2;
                for (var y = first; y <= root.today.getFullYear() + 1; y++) out.push({ year: y, month: 0 });
            }
            return out;
        }
        readonly property int committed: {
            for (var i = 0; i < items.length; i++)
                if (items[i].year === root.year && (root.kind === "year" || items[i].month === root.month)) return i;
            return 0;
        }
        function open(it) {
            var t = root.today, f = root.firstDay;
            if (it.month === 0) return it.year >= f.getFullYear() && it.year <= t.getFullYear();
            var k = it.year * 12 + it.month, lo = f.getFullYear() * 12 + f.getMonth() + 1, hi = t.getFullYear() * 12 + t.getMonth() + 1;
            return k >= lo && k <= hi;
        }
        function snap() { posAnim.stop(); liftAnim.stop(); lift = 0; dragging = false; pos = committed; }
        function labelOf(it) { return it.month === 0 ? String(it.year) : root.monthName(it.month); }
        function settle(velocity) {
            dragging = false;
            var target = Math.max(0, Math.min(items.length - 1, Math.round(pos - velocity * 0.18)));
            if (!open(items[target])) target = committed;
            liftAnim.to = 0; liftAnim.restart();
            posAnim.to = target; posAnim.restart();
            var it = items[target];
            if (target !== committed) root.select(root.kind, it.year, it.month || root.month);
        }
        onCommittedChanged: if (!dragging) { posAnim.to = committed; posAnim.restart(); }
        onItemsChanged: { pos = committed; requestPaint(); }
        Component.onCompleted: pos = committed
        onPosChanged: requestPaint()
        onLiftChanged: requestPaint()
        onWidthChanged: requestPaint()
        Connections { target: root; function onStatsChanged() { rc.requestPaint(); } }

        SpringAnimation { id: posAnim; target: rc; property: "pos"; spring: 4.2; damping: 0.42; epsilon: 0.002 }
        NumberAnimation { id: liftAnim; target: rc; property: "lift"; duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }

        MouseArea {
            anchors.fill: parent
            cursorShape: rc.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            preventStealing: true
            property real lastX: 0
            property real pressX: 0
            property real vel: 0
            property double lastT: 0
            onPressed: mouse => { lastX = mouse.x; pressX = mouse.x; vel = 0; lastT = Date.now(); }
            onPositionChanged: mouse => {
                if (!rc.dragging && Math.abs(mouse.x - pressX) > 4) {
                    rc.dragging = true; posAnim.stop();
                    liftAnim.to = 1; liftAnim.restart();
                }
                if (!rc.dragging) return;
                var dx = mouse.x - lastX, now = Date.now();
                vel = dx / rc.itemW / Math.max(0.008, (now - lastT) / 1000) * 0.5 + vel * 0.5;
                lastX = mouse.x; lastT = now;
                rc.pos = Math.max(-0.45, Math.min(rc.items.length - 0.55, rc.pos - dx / rc.itemW));
            }
            onReleased: mouse => {
                if (rc.dragging) { rc.settle(vel); return; }
                // a click picks the period under it
                var i = Math.round(rc.pos + (mouse.x - rc.restAnchor) / rc.itemW);
                if (i < 0 || i >= rc.items.length || !rc.open(rc.items[i])) return;
                posAnim.to = i; posAnim.restart();
                root.select(root.kind, rc.items[i].year, rc.items[i].month || root.month);
            }
            onWheel: wheel => {
                var d = (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y) > 0 ? -1 : 1;
                var i = rc.committed + d;
                if (i >= 0 && i < rc.items.length && rc.open(rc.items[i]))
                    root.select(root.kind, rc.items[i].year, rc.items[i].month || root.month);
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var anchor = rc.restAnchor + (width / 2 - rc.restAnchor) * lift;
            var fade = 40, cy = 66, labelBottom = 40;
            function smooth(x) { var t = Math.max(0, Math.min(1, x)); return t * t * (3 - 2 * t); }
            function edge(x) { return smooth(x / fade) * smooth((width - x) / fade); }
            var daily = (root.stats && root.stats.daily_minutes) || {};
            var dayMax = 1;
            for (var k in daily) dayMax = Math.max(dayMax, daily[k]);
            for (var i = 0; i < items.length; i++) {
                var x0 = anchor + (i - pos) * itemW;
                if (x0 > width + itemW || x0 + itemW < -itemW) continue;
                var it = items[i], isOpen = open(it);
                var ticks = it.month ? new Date(it.year, it.month, 0).getDate() : 12;
                var step = itemW / ticks;
                for (var t = 0; t < ticks; t++) {
                    var x = x0 + t * step;
                    if (x < -2 || x > width + 2) continue;
                    var major = t === 0;
                    var mins = 0;
                    if (it.month) {
                        var key = it.year + "-" + String(it.month).padStart(2, "0") + "-" + String(t + 1).padStart(2, "0");
                        mins = daily[key] || 0;
                    }
                    // a quiet day keeps the plain tick; a listened one stands taller with how much
                    var h = (major ? 34 : 22) + (mins > 0 ? 16 * Math.sqrt(mins / dayMax) : 0);
                    var a = (isOpen ? (major ? 0.9 : (mins > 0 ? 0.85 : 0.5)) : (major ? 0.3 : 0.16)) * edge(x);
                    if (a <= 0.01) continue;
                    ctx.strokeStyle = mins > 0 && isOpen ? Qt.rgba(root.mark.r, root.mark.g, root.mark.b, a) : Qt.rgba(1, 1, 1, a);
                    ctx.lineWidth = major ? 2 : 1.3;
                    ctx.lineCap = "round";
                    ctx.beginPath(); ctx.moveTo(x, cy - h / 2); ctx.lineTo(x, cy + h / 2); ctx.stroke();
                }
                // its name over its first tick; the one under the marker grows to full size
                var near = Math.max(0, Math.min(1, 1 - Math.abs(i - pos)));
                var size = 30 * (0.48 + 0.52 * near);
                ctx.font = "bold " + Math.round(size) + "px '" + root.canvasFamily + "'";
                var label = labelOf(it), lw = ctx.measureText(label).width;
                var left = Math.max(x0 - lw / 2, 6);
                var al = Math.max(edge(x0), near);
                var lit = isOpen ? 0.48 + 0.52 * near : 0.22 + 0.15 * near;
                ctx.fillStyle = Qt.rgba(1, 1, 1, lit * al);
                ctx.fillText(label, left, labelBottom);
            }
            // the marker itself: grey when there is nothing under it
            var under = Math.max(0, Math.min(items.length - 1, Math.round(pos)));
            var lit2 = open(items[under]);
            ctx.strokeStyle = lit2 ? root.ink : Qt.rgba(1, 1, 1, 0.4);
            ctx.lineWidth = 3; ctx.lineCap = "round";
            ctx.beginPath(); ctx.moveTo(anchor, cy - 22); ctx.lineTo(anchor, cy + 22); ctx.stroke();
        }
    }

    // ---- the picker: show by month or year, then which ------------------------------------------
    Rectangle {
        id: picker
        property bool open: false
        property string k: root.kind
        property int pickYear: root.year
        onOpenChanged: if (open) { k = root.kind; pickYear = root.year; }
        z: 20
        x: Math.min(parent.width - width - 16, column.x + recapLink.x)
        y: column.y + 70 - flick.contentY
        width: 300
        height: pickerBody.implicitHeight + 32
        radius: 22
        color: Qt.rgba(0.06 + root.accentColor.r * 0.10, 0.06 + root.accentColor.g * 0.10, 0.08 + root.accentColor.b * 0.12, 0.97)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        visible: opacity > 0.01
        opacity: open ? 1 : 0
        scale: open ? 1 : 0.96
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: pickerBody
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8
            Label { text: I18n.tr("Xem theo", "Show by"); size: 22 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [{ k: "month", t: I18n.tr("Tháng", "Month") }, { k: "year", t: I18n.tr("Năm", "Year") }]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: picker.k === modelData.k
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 12
                        color: on ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32) : root.chipFill
                        border.width: on ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.4)
                        Text { anchors.centerIn: parent; text: parent.modelData.t; color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: picker.k = parent.modelData.k }
                    }
                }
            }
            Label { Layout.topMargin: 6; text: I18n.tr("Năm nào?", "What year?"); size: 22 }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: {
                        var out = [];
                        for (var y = root.firstDay.getFullYear(); y <= root.today.getFullYear(); y++) out.push(y);
                        return out;
                    }
                    delegate: Rectangle {
                        required property int modelData
                        readonly property bool on: picker.pickYear === modelData
                        width: 62; height: 32; radius: 16
                        color: on ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32) : root.chipFill
                        border.width: on ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.4)
                        Text { anchors.centerIn: parent; text: parent.modelData; color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                picker.pickYear = parent.modelData;
                                if (picker.k === "year") { root.select("year", picker.pickYear, root.month); picker.open = false; }
                            }
                        }
                    }
                }
            }
            Label { visible: picker.k === "month"; Layout.topMargin: 6; text: I18n.tr("Tháng nào?", "What month?"); size: 22 }
            GridLayout {
                visible: picker.k === "month"
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 6
                columnSpacing: 6
                Repeater {
                    model: 12
                    delegate: Rectangle {
                        required property int index
                        readonly property int m: index + 1
                        readonly property bool can: {
                            var k = picker.pickYear * 12 + m, f = root.firstDay, t = root.today;
                            return k >= f.getFullYear() * 12 + f.getMonth() + 1 && k <= t.getFullYear() * 12 + t.getMonth() + 1;
                        }
                        readonly property bool on: root.kind === "month" && root.year === picker.pickYear && root.month === m
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 16
                        opacity: can ? 1 : 0.35
                        color: on ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32) : root.chipFill
                        border.width: on ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.4)
                        Text { anchors.centerIn: parent; text: root.monthShort(parent.m); color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold }
                        HoverHandler { enabled: parent.can; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.can; onTapped: { root.select("month", picker.pickYear, parent.m); picker.open = false; } }
                    }
                }
            }
        }
    }
    // a click outside closes the picker
    MouseArea {
        anchors.fill: parent
        z: 19
        visible: picker.open
        onClicked: picker.open = false
    }

    // Back: pinned top left like the other detail pages
    Rectangle {
        x: 20; y: 16; z: 10
        width: 36; height: 36; radius: 18
        color: Qt.rgba(root.accentColor.r * 0.35, root.accentColor.g * 0.35, root.accentColor.b * 0.35, backHover.hovered ? 0.85 : 0.6)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, backHover.hovered ? 0.5 : 0.28)
        Behavior on color { ColorAnimation { duration: 150 } }
        AppIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/icons/go-previous-symbolic.svg")
            iconSize: 16
            color: Theme.textPrimary
        }
        HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.backRequested() }
    }
}
