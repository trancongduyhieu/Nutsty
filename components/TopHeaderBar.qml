import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "."
import "window_frame_logic.js" as Frame

Rectangle {
    id: headerRoot
    // Notch mode: the header folds into notches hanging from a thin frame (liner style). The mood
    // sits in the middle of the center notch, which grows down to show the chips (Dynamic Island).
    height: notchMode ? 44 : 64
    color: "transparent"
    z: 100

    property bool notchMode: false
    // full window height: the frame is drawn from this item, which sits at the window's top-left
    property real frameHeight: 0
    readonly property real navBox: notchMode ? 26 : 32
    readonly property bool moodShown: currentView === "home" && !isNowPlayingOpen
    readonly property bool moodOpenInNotch: notchMode && moodShown && isMoodIslandExpanded
    // Island morph, as boring.notch opens its MacBook notch: a spring with a small bounce to open
    // (SwiftUI response 0.42, damping 0.8) and a critically damped one to close (0.45, 1.0). It is
    // stepped per frame so a click mid-flight reverses from the current speed instead of jumping.
    property real moodMorph: 0
    property real moodMorphVel: 0
    readonly property real moodMorphTarget: moodOpenInNotch ? 1 : 0
    FrameAnimation {
        running: Math.abs(headerRoot.moodMorph - headerRoot.moodMorphTarget) > 0.0005 || Math.abs(headerRoot.moodMorphVel) > 0.002
        onTriggered: {
            var open = headerRoot.moodMorphTarget > 0.5;
            var s = Frame.springStep(headerRoot.moodMorph, headerRoot.moodMorphVel, headerRoot.moodMorphTarget,
                                     open ? 0.42 : 0.45, open ? 0.8 : 1.0, frameTime);
            var done = Math.abs(s[0] - headerRoot.moodMorphTarget) <= 0.0005 && Math.abs(s[1]) <= 0.002;
            headerRoot.moodMorphVel = done ? 0 : s[1];
            headerRoot.moodMorph = done ? headerRoot.moodMorphTarget : s[0];
        }
    }
    // the chip row's full height inside the open notch (island pill height)
    readonly property real moodRowH: 38
    // Now Playing in notch mode: the center notch swaps the nav icons for the view's mode switcher
    // (artwork / lyrics / up next / sleep), as liner keeps its lyric controls in its notch. Same
    // spring as the mood island so the notch width morphs between the two rows.
    property real npMorph: 0
    property real npMorphVel: 0
    readonly property real npMorphTarget: notchMode && isNowPlayingOpen ? 1 : 0
    FrameAnimation {
        running: Math.abs(headerRoot.npMorph - headerRoot.npMorphTarget) > 0.0005 || Math.abs(headerRoot.npMorphVel) > 0.002
        onTriggered: {
            var open = headerRoot.npMorphTarget > 0.5;
            var s = Frame.springStep(headerRoot.npMorph, headerRoot.npMorphVel, headerRoot.npMorphTarget,
                                     open ? 0.42 : 0.45, open ? 0.8 : 1.0, frameTime);
            var done = Math.abs(s[0] - headerRoot.npMorphTarget) <= 0.0005 && Math.abs(s[1]) <= 0.002;
            headerRoot.npMorphVel = done ? 0 : s[1];
            headerRoot.npMorph = done ? headerRoot.npMorphTarget : s[0];
        }
    }
    // the switcher row's width, eased when it grows or shrinks in place (lyrics controls come and go)
    // Springs like the notch itself: grows with a small bounce (0.42, 0.8), shrinks a touch slower
    // and without one (0.44, 1.0). The host clips to it, so the new controls are uncovered as the
    // notch widens instead of popping in at full width.
    readonly property real npRowTarget: npNotchHost.childrenRect.width
    property real npRowW: 0
    property real npRowVel: 0
    FrameAnimation {
        running: Math.abs(headerRoot.npRowW - headerRoot.npRowTarget) > 0.25 || Math.abs(headerRoot.npRowVel) > 0.5
        onTriggered: {
            // while the nav icons and the switcher swap, npMorph already carries the width
            if (headerRoot.npMorph < 0.99) { headerRoot.npRowW = headerRoot.npRowTarget; headerRoot.npRowVel = 0; return; }
            var grow = headerRoot.npRowTarget > headerRoot.npRowW;
            var s = Frame.springStep(headerRoot.npRowW, headerRoot.npRowVel, headerRoot.npRowTarget,
                                     grow ? 0.42 : 0.44, grow ? 0.8 : 1.0, frameTime);
            var done = Math.abs(s[0] - headerRoot.npRowTarget) <= 0.25 && Math.abs(s[1]) <= 0.5;
            headerRoot.npRowVel = done ? 0 : s[1];
            headerRoot.npRowW = done ? headerRoot.npRowTarget : s[0];
        }
    }
    // where the Now Playing view parents its mode switcher while in notch mode
    readonly property Item nowPlayingNotchHost: notchMode ? npNotchHost : null
    signal collapseRequested()

    property string currentTab: "all"
    property string currentView: "home"
    property string searchMode: currentView === "library" ? "offline" : "online"
    property var suggestions: []
    property bool isSearching: false
    property bool canGoBack: currentView !== "home"
    property bool isSidebarVisible: false
    property bool isMaximized: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string searchText: ""

    function fillSearchText(val) {
        searchText = val;
    }

    function setSearchText(val) {
        searchText = val;
        suggestions = [];
    }

    signal tabSelected(string tab)
    signal searchRequested(string query, string mode)
    signal searchSubmitted(string query, string mode)
    signal searchClicked()
    signal backRequested()
    signal forwardRequested()
    signal downloadPopoverRequested()
    signal toggleSidebarRequested()
    signal minimizeWindowRequested()
    signal maximizeWindowRequested()
    signal closeWindowRequested()
    signal homeClicked()
    signal libraryClicked()
    signal settingsClicked()
    signal profileClicked()
    readonly property Item profileButton: profileBtn
    // the welcome card has just landed in the avatar
    function pulseProfile() { landAnim.restart(); }
    property string userAvatar: ""
    property string userName: ""
    // Now Playing covers the feed, so the mood island has nothing to filter there
    property bool isNowPlayingOpen: false
    signal notificationsClicked(real xPos, real yPos)
    property int unreadNotificationsCount: 0

    // Mood Bar Integration in Top Header
    property var moods: []
    property string selectedMood: "All"
    property bool isMoodIslandExpanded: false
    signal moodSelected(string title, string params)
    // true when the open mood island's span reaches over this header item (with a small gap);
    // positions only change with the window width, which re-runs this through the island's width
    function moodCovers(item) {
        if (notchMode || !isMoodIslandExpanded || !dynamicMoodIsland.visible || !item) return false;
        var left = (headerRoot.width - dynamicMoodIsland.expandedTargetWidth) / 2 - 10;
        var right = item.mapToItem(headerRoot, item.width, 0).x;
        return right > left;
    }

    function formatMoodTitle(title) {
        return I18n.formatMoodChipTitle(title);
    }

    readonly property var activeMoodList: (headerRoot.moods && headerRoot.moods.length > 0) ? headerRoot.moods : [
        { "title": "All", "params": "" },
        { "title": "Relax", "params": "ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Sleep", "params": "ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Energize", "params": "ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Sad", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Romance", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Party", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhADSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Commute", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxADSgQICBABSgQIBhABSgQIBBAB" },
        { "title": "Feel good", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBADSgQIBhABSgQIBBAB" },
        { "title": "Focus", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhADSgQIBBAB" },
        { "title": "Workout", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAD" }
    ]

    onCurrentViewChanged: {
        isMoodIslandExpanded = false;
        searchMode = (currentView === "library" ? "offline" : "online");
        suggestions = [];
        if (currentView !== "search" && (!searchText || searchText.trim() === "")) {
            isSearching = false;
        }
    }

    // Open mood notch glass: the window's own backdrop (wallpaper / cover, the source the player bar's
    // liquid glass samples) cropped behind the notch, blurred and cut to the notch shape, so the open
    // island is frosted glass instead of flat black and the page text under it is gone. Under the
    // frame (z -2), whose band fill and tint darken it for the chips. Built only while it is open.
    Item {
        id: notchGlass
        z: -2
        readonly property bool active: headerRoot.notchMode && headerRoot.backgroundSourceItem !== null
                                       && headerRoot.moodMorph > 0.001 && notchFrame.centerVisible
        visible: active
        opacity: Math.min(1, Math.max(0, headerRoot.moodMorph * 1.5))
        width: headerRoot.width
        height: notchFrame.band + Frame.H + headerRoot.moodRowH + 6 + 4

        readonly property point cropPos: {
            var _dep = headerRoot.x + headerRoot.y + headerRoot.width + headerRoot.height;
            return headerRoot.backgroundSourceItem ? headerRoot.mapToItem(headerRoot.backgroundSourceItem, 0, 0) : Qt.point(0, 0);
        }

        Loader {
            anchors.fill: parent
            active: notchGlass.active
            sourceComponent: Item {
                ShaderEffectSource {
                    id: notchCrop
                    sourceItem: headerRoot.backgroundSourceItem
                    sourceRect: Qt.rect(notchGlass.cropPos.x, notchGlass.cropPos.y, notchGlass.width, notchGlass.height)
                    width: notchGlass.width; height: notchGlass.height
                    visible: false
                    live: true
                    smooth: true
                }
                Item {
                    id: notchGlassMask
                    width: notchGlass.width; height: notchGlass.height
                    visible: false
                    layer.enabled: true
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "white"
                            strokeWidth: -1
                            PathSvg { path: Frame.centerNotchPath(Math.round(notchFrame.width), notchFrame.leftContentWidth, notchFrame.centerContentWidth,
                                                                  notchFrame.rightContentWidth, notchFrame.centerExtraHeight, notchFrame.centerBottomRadius) }
                        }
                    }
                }
                MultiEffect {
                    width: notchGlass.width; height: notchGlass.height
                    source: notchCrop
                    blurEnabled: true
                    blur: 1.0
                    blurMax: Theme.blurAtmosphere
                    saturation: 1.55
                    brightness: -0.08
                    maskEnabled: true
                    maskSource: notchGlassMask
                    // soft mask: glass coverage follows the shape's antialiased edge exactly like the
                    // smoke's does. The default hard mask counted every edge pixel as full glass, a
                    // 1px ring brighter than the smoked inside: a light blue line along the bottom
                    // while the notch moved between pixels.
                    // MultiEffect maps mask alpha through smoothstep(2*min - 1, 2*min, a) when spread is 1:
                    // min 0.5 gives smoothstep(0, 1, a), i.e. the edge's own coverage (min 0 would show
                    // the whole crop rectangle)
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    autoPaddingEnabled: false
                }
                // the smoke is part of the glass and fades in with it: a tint that ramped up on its own
                // let the freshly revealed bottom of the notch show the bright blur for a few frames
                Shape {
                    width: notchGlass.width; height: notchGlass.height
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Qt.rgba(0, 0, 0, 0.5)
                        strokeWidth: -1
                        PathSvg { path: Frame.centerNotchPath(Math.round(notchFrame.width), notchFrame.leftContentWidth, notchFrame.centerContentWidth,
                                                              notchFrame.rightContentWidth, notchFrame.centerExtraHeight, notchFrame.centerBottomRadius) }
                    }
                }
            }
        }
    }

    // Frame + notches, under this header's buttons but over the page (the header stacks above it)
    WindowFrameNotches {
        id: notchFrame
        z: -1
        x: 0; y: 0
        width: headerRoot.width
        height: headerRoot.frameHeight
        visible: headerRoot.notchMode && height > 0
        // the Nutsty mark (home) always, then the collapse chevron while Now Playing is open
        leftContentWidth: headerRoot.notchMode
            ? logoNotchBtn.width + (collapseNotchBtn.shown ? 2 + headerRoot.navBox : 0) + 8 : 0
        // one morph progress drives width, depth and tint together, so the island grows as one shape
        // the closed row: nav icons, or the Now Playing mode switcher, morphing between the two
        readonly property real closedW: navCluster.implicitWidth + 8
            + (Math.max(headerRoot.npRowW, 1) - navCluster.implicitWidth) * Math.min(1, Math.max(0, headerRoot.npMorph))
        readonly property real openW: Math.max(navCluster.implicitWidth, dynamicMoodIsland.expandedTargetWidth) + 8
        centerContentWidth: closedW + (openW - closedW) * headerRoot.moodMorph
        // whole pixels: a bottom edge between pixel rows smears into a soft bright line while it moves
        centerExtraHeight: Math.round((headerRoot.moodRowH + 6) * Math.max(0, headerRoot.moodMorph))
        // with the glass the smoke lives in the glass layer (glass + 0.5 smoke + fill 0.35 ~ 0.68 dark);
        // without a backdrop source it falls back to a near solid black island
        centerTint: notchGlass.active ? 0 : 0.92 * Math.min(1, Math.max(0, headerRoot.moodMorph))
        // bottom corners round out as it opens (boring.notch: 14 -> 24)
        centerBottomRadius: Frame.BR + 7 * Math.min(1, Math.max(0, headerRoot.moodMorph))
        rightContentWidth: headerRoot.navBox * 2 + 2 + 8
        // windowed: concentric with the 24px window corner; maximized: liner's 12px
        cornerRadius: headerRoot.isMaximized ? 12 : 24 - band
    }

    // The top band and the gaps between notches still move the window and restore it on double click
    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: headerRoot.notchMode ? notchFrame.band + notchFrame.contentHeight + 4 : parent.height
        z: -1
        onPressed: {
            if (headerRoot.isMoodIslandExpanded) headerRoot.isMoodIslandExpanded = false;
            if (typeof win !== "undefined" && win && typeof win.startSystemMove === "function") win.startSystemMove();
        }
        onDoubleClicked: headerRoot.maximizeWindowRequested()
    }

    // Left notch, first: the Nutsty mark in white (as on the update screen) is the home button,
    // where liner keeps its logo
    Rectangle {
        id: logoNotchBtn
        visible: headerRoot.notchMode
        x: notchFrame.leftContentX + 2
        y: notchFrame.band
        width: headerRoot.navBox; height: headerRoot.navBox
        radius: 8
        color: logoH.hovered ? Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.22) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: logoH }
        ToolTip.visible: logoH.hovered
        ToolTip.text: I18n.tr("Trang chủ", "Home")
        ToolTip.delay: 400
        AppIcon {
            anchors.centerIn: parent
            source: "../assets/icons/nutsty-outline-symbolic.svg"
            iconSize: 22
            color: "#ffffff"
            opacity: logoH.hovered || (headerRoot.currentView === "home" && !headerRoot.isNowPlayingOpen) ? 1.0 : 0.8
            scale: logoMouse.pressed ? 0.9 : (logoH.hovered ? 1.06 : 1.0)
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
        MouseArea { id: logoMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: headerRoot.homeClicked() }
    }

    // Left notch, after the mark (Now Playing only): collapse back to the page underneath
    Rectangle {
        id: collapseNotchBtn
        readonly property bool shown: headerRoot.notchMode && headerRoot.isNowPlayingOpen
        visible: shown
        x: logoNotchBtn.x + logoNotchBtn.width + 2
        y: notchFrame.band
        width: headerRoot.navBox; height: headerRoot.navBox
        radius: 8
        color: collapseNotchH.hovered ? Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.22) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: collapseNotchH }
        ToolTip.visible: collapseNotchH.hovered
        ToolTip.text: I18n.tr("Thu nhỏ", "Collapse")
        ToolTip.delay: 400
        AppIcon {
            anchors.centerIn: parent
            source: "../assets/icons/material/ms-expand_more.svg"
            iconSize: 18
            color: "#ffffff"
            opacity: collapseNotchH.hovered ? 1.0 : 0.75
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: headerRoot.collapseRequested() }
    }

    // Center notch slot for the Now Playing mode switcher (YTMusicNowPlayingView parents it here)
    Item {
        id: npNotchHost
        visible: headerRoot.notchMode && notchFrame.centerVisible && headerRoot.npMorph > 0.01
        enabled: headerRoot.isNowPlayingOpen
        width: Math.max(0, headerRoot.npRowW)
        clip: true
        height: notchFrame.contentHeight
        x: Math.round(notchFrame.centerMid - width / 2)
        y: notchFrame.band
        z: 2
        // fades in late and out early so it never overlaps the nav icons at full strength
        opacity: Math.min(1, Math.max(0, (headerRoot.npMorph - 0.35) / 0.5))
        transform: Scale {
            origin.x: npNotchHost.width / 2; origin.y: npNotchHost.height / 2
            xScale: 0.92 + 0.08 * npNotchHost.opacity; yScale: xScale
        }
    }

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: headerRoot.notchMode ? notchFrame.band : 0
        height: headerRoot.notchMode ? notchFrame.contentHeight : 64
        // notch mode: the nav cluster starts inside the center notch, the window buttons end inside the right one
        anchors.leftMargin: headerRoot.notchMode ? Math.round(notchFrame.centerMid - navCluster.implicitWidth / 2) : 20
        anchors.rightMargin: headerRoot.notchMode ? notchFrame.band + 2 : 20
        spacing: headerRoot.notchMode ? 2 : 14

        // Top Navigation Cluster: Home, Search, Library, Downloads, Settings (Pure Borderless Icons matching wallpaper accent)
        RowLayout {
            id: navCluster
            spacing: headerRoot.notchMode ? 6 : 14
            // gives the center notch over to the Now Playing mode switcher
            opacity: Math.min(1, Math.max(0, 1 - headerRoot.npMorph / 0.5))
            enabled: headerRoot.npMorph < 0.5
            transform: Scale {
                origin.x: navCluster.width / 2; origin.y: navCluster.height / 2
                xScale: 0.92 + 0.08 * navCluster.opacity; yScale: xScale
            }

            // Profile: the user's own avatar opens the listener card page
            Item {
                id: profileBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(profileBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox
                readonly property bool isActive: headerRoot.currentView === "profile"

                Item {
                    id: profileAvatarBump
                    anchors.fill: parent
                RoundedImage {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    radius: 11
                    source: headerRoot.userAvatar
                    initialsText: headerRoot.userName
                    fallbackIconColor: headerRoot.accentColor
                    fallbackIconSize: 12
                    borderWidth: 1
                    borderColor: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b,
                                         profileBtn.isActive ? 0.95 : (profileMouse.containsMouse ? 0.70 : 0.40))
                    opacity: profileBtn.isActive || profileMouse.containsMouse ? 1.0 : 0.80
                    scale: profileMouse.containsMouse ? 1.12 : (profileBtn.isActive ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                }

                // Ring and bump when the welcome card lands in the avatar
                Rectangle {
                    id: landRing
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: headerRoot.accentColor
                    opacity: 0
                    visible: opacity > 0.001
                }
                ParallelAnimation {
                    id: landAnim
                    NumberAnimation { target: landRing; property: "width"; from: 22; to: 46; duration: 620; easing.type: Easing.OutCubic }
                    NumberAnimation { target: landRing; property: "height"; from: 22; to: 46; duration: 620; easing.type: Easing.OutCubic }
                    NumberAnimation { target: landRing; property: "opacity"; from: 0.9; to: 0; duration: 620; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: profileAvatarBump; property: "scale"; to: 1.28; duration: 140; easing.type: Easing.OutQuad }
                        NumberAnimation { target: profileAvatarBump; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }

                MouseArea {
                    id: profileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.profileClicked()
                }
            }

            // 1. Home Button (windowed header only; the notch layout uses the Nutsty mark in the left notch)
            Item {
                id: homeBtn
                visible: !headerRoot.notchMode
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(homeBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/go-home-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.currentView === "home" ? 1.0 : (homeMouse.containsMouse ? 1.0 : 0.70)
                    scale: homeMouse.containsMouse ? 1.12 : (headerRoot.currentView === "home" ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: homeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.homeClicked()
                }
            }

            // 2. Dedicated Search Button (SimpMusic / Spotify style borderless icon)
            Item {
                id: searchNavBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(searchNavBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/system-search-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.currentView === "search" ? 1.0 : (searchNavM.containsMouse ? 1.0 : 0.70)
                    scale: searchNavM.containsMouse ? 1.12 : (headerRoot.currentView === "search" ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: searchNavM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.searchClicked()
                }
            }

            // 3. Downloads / Local Library Button
            Item {
                id: libBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(libBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox

                readonly property bool isLibActive: headerRoot.currentView === "library" || headerRoot.currentView === "custom_playlist_detail" || (headerRoot.currentView === "playlist" && typeof win !== "undefined" && win.previousView === "library")

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/folder-music-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: libBtn.isLibActive ? 1.0 : (libMouse.containsMouse ? 1.0 : 0.70)
                    scale: libMouse.containsMouse ? 1.12 : (libBtn.isLibActive ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: libMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.libraryClicked()
                }
            }

            // Notch mode, home feed: the selected mood in the middle of the icon row; it opens the
            // chip row by growing the center notch down (the island's own pill is unused here)
            Item {
                id: moodNotchLabel
                visible: headerRoot.notchMode && headerRoot.moodShown
                Layout.preferredWidth: moodNotchTxt.implicitWidth + 24
                Layout.preferredHeight: headerRoot.navBox
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    radius: height / 2
                    color: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b,
                                   moodNotchMouse.containsMouse ? 1.0 : 0.95)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                // stays solid while open (fading fill and text together made the label blink out
                // mid-morph); a slight press-in shows the island is open instead
                Text {
                    id: moodNotchTxt
                    anchors.centerIn: parent
                    text: headerRoot.formatMoodTitle(headerRoot.selectedMood)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    color: dynamicMoodIsland.chipTextColor
                }
                scale: headerRoot.isMoodIslandExpanded ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                MouseArea {
                    id: moodNotchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        headerRoot.isMoodIslandExpanded = !headerRoot.isMoodIslandExpanded;
                        if (headerRoot.isMoodIslandExpanded) autoCollapseTimer.restart();
                    }
                }
            }

            // 4. Downloads Queue Popover Button
            Item {
                id: downloadQueueBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(downloadQueueBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox
                readonly property bool hasActive: typeof downloadManager !== "undefined" && downloadManager && downloadManager.activeTasksCount > 0
                visible: true

                CircularSpinner {
                    anchors.centerIn: parent
                    visible: downloadQueueBtn.hasActive
                    running: downloadQueueBtn.hasActive
                    color: headerRoot.accentColor
                    size: 16
                    strokeWidth: 2
                }

                AppIcon {
                    anchors.centerIn: parent
                    visible: !downloadQueueBtn.hasActive
                    source: "../assets/icons/download-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: dlMouse.containsMouse ? 1.0 : 0.70
                    scale: dlMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: dlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        headerRoot.downloadPopoverRequested();
                    }
                }
            }

            // 5. Settings & Account Button
            Item {
                id: setBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(setBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/preferences-system-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: setMouse.containsMouse ? 1.0 : 0.70
                    scale: setMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: setMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.settingsClicked()
                }
            }

            // 6. Notification Bell Button (Flat layout, accent indicator badge)
            Item {
                id: notificationBtn
                // tucks under the open mood island instead of showing through its glass
                readonly property bool underMood: headerRoot.moodCovers(notificationBtn)
                opacity: underMood ? 0 : 1
                scale: underMood ? 0.8 : 1
                enabled: !underMood
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Layout.preferredWidth: headerRoot.navBox
                Layout.preferredHeight: headerRoot.navBox

                AppIcon {
                    id: bellIcon
                    anchors.centerIn: parent
                    source: "../assets/icons/notifications-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.unreadNotificationsCount > 0 ? 1.0 : (notifMouse.containsMouse ? 1.0 : 0.70)
                    scale: notifMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // Flat Accent Badge (No heavy nested box)
                Rectangle {
                    id: notifBadge
                    visible: headerRoot.unreadNotificationsCount > 0
                    anchors.top: bellIcon.top
                    anchors.topMargin: -2
                    anchors.right: bellIcon.right
                    anchors.rightMargin: -4
                    width: Math.max(14, badgeText.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: headerRoot.accentColor

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: headerRoot.unreadNotificationsCount > 9 ? "9+" : headerRoot.unreadNotificationsCount
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        font.bold: true
                        color: (headerRoot.accentColor.r * 0.299 + headerRoot.accentColor.g * 0.587 + headerRoot.accentColor.b * 0.114) > 0.6 ? "#000000" : "#ffffff"
                    }
                }

                MouseArea {
                    id: notifMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var pt = notificationBtn.mapToItem(headerRoot, notificationBtn.width / 2, notificationBtn.height);
                        headerRoot.notificationsClicked(pt.x, pt.y);
                    }
                }
            }
        }

        // Center Area: Empty drag space between Left Cluster and Right Controls
        Item {
            id: centerHeaderArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    if (headerRoot.isMoodIslandExpanded) {
                        headerRoot.isMoodIslandExpanded = false;
                    }
                    if (typeof win !== "undefined" && win && typeof win.startSystemMove === "function") {
                        win.startSystemMove();
                    }
                }
                onDoubleClicked: {
                    headerRoot.maximizeWindowRequested();
                }
            }
        }

        // Window Maximize / Restore Button [ ◻ ]
        Rectangle {
            id: maxBtn
            Layout.preferredWidth: headerRoot.navBox
            Layout.preferredHeight: headerRoot.navBox
            radius: headerRoot.notchMode ? 8 : 16
            color: !maxMouse.containsMouse ? "transparent"
                : (headerRoot.notchMode ? Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.22) : Qt.rgba(1, 1, 1, 0.12))
            Behavior on color { ColorAnimation { duration: 150 } }

            AppIcon {
                anchors.centerIn: parent
                source: headerRoot.isMaximized ? "../assets/icons/window-restore-symbolic.svg" : "../assets/icons/window-maximize-symbolic.svg"
                iconSize: 14
                color: "#ffffff"
            }

            MouseArea {
                id: maxMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: headerRoot.maximizeWindowRequested()
            }
        }

        // Window Close Button [ ✕ ] (Closes / Minimizes to Desktop Widget)
        Rectangle {
            id: closeBtn
            Layout.preferredWidth: headerRoot.navBox
            Layout.preferredHeight: headerRoot.navBox
            radius: headerRoot.notchMode ? 8 : 16
            color: !closeMouse.containsMouse ? "transparent"
                : (headerRoot.notchMode ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.55) : "#E81123")
            Behavior on color { ColorAnimation { duration: 150 } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/window-close-symbolic.svg"
                iconSize: 14
                color: "#ffffff"
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: headerRoot.closeWindowRequested()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Center Floating: Dynamic Mood Island (Direct child of headerRoot -> Dead Center!)
    // -------------------------------------------------------------------------
    Rectangle {
        id: dynamicMoodIsland
        anchors.horizontalCenter: headerRoot.horizontalCenter
        anchors.verticalCenter: headerRoot.verticalCenter
        // notch mode: the chip row opens inside the grown center notch, under the icon row
        anchors.verticalCenterOffset: headerRoot.notchMode ? (notchFrame.band + notchFrame.contentHeight + 3 + height / 2 - headerRoot.height / 2) : 0
        anchors.horizontalCenterOffset: headerRoot.notchMode ? notchFrame.centerMid - headerRoot.width / 2 : 0
        // Same frosted pill as the Now Playing mode switcher: light translucent fill + hairline,
        // the active mood is a solid segment in the cover / wallpaper accent
        height: headerRoot.notchMode ? Math.max(0, Math.min(headerRoot.moodRowH, notchFrame.centerExtraHeight - 3)) : headerRoot.moodRowH
        radius: 19
        z: 12
        clip: true
        visible: opacity > 0.01 && height > 0.5
        // notch mode: only the open chip row shows here (the closed mood is the label in the icon row).
        // The island is a window onto the notch as it grows: as wide and deep as the notch is at that
        // moment, clipping the chip row like the notch shape clips boring.notch's content, so no chip
        // ever sits outside the notch mid-animation.
        // closing, the row is gone in the first part of the shrink (boring.notch removes content
        // with a plain fade, ahead of the shape)
        readonly property real revealT: headerRoot.moodOpenInNotch
            ? Math.min(1, Math.max(0, (headerRoot.moodMorph - 0.25) / 0.6))
            : Math.min(1, Math.max(0, (headerRoot.moodMorph - 0.6) / 0.4))
        opacity: !headerRoot.moodShown ? 0.0 : 1.0
        Behavior on opacity { enabled: !headerRoot.notchMode; NumberAnimation { duration: 180 } }

        readonly property bool isExpanded: headerRoot.isMoodIslandExpanded
        // Selected chip takes the cover / wallpaper accent; text flips dark on light accents
        readonly property color chipTextColor: topMoodFlickable.accentLuminance > 0.6 ? "#121214" : "#ffffff"
        readonly property real compactWidth: compactTxt.implicitWidth + 36
        readonly property real maxExpandedWidth: headerRoot.width - (headerRoot.notchMode ? 180 : 580)
        readonly property real expandedTargetWidth: Math.min(maxExpandedWidth, moodRow.width + 24)
        // Chips shrink their side padding (24 -> 16) so the whole row fits the island instead of the
        // last chip being cut flat by the clip; it only scrolls if even the tight padding cannot fit
        property real moodTextSum: 0
        readonly property real chipPad: {
            var n = moodRepeater.count;
            if (n <= 0) return 24;
            var free = maxExpandedWidth - 24 - moodRow.spacing * (n - 1) - moodTextSum;
            return Math.max(16, Math.min(24, Math.floor(free / n)));
        }
        function recalcMoodText() {
            var sum = 0;
            for (var i = 0; i < moodRepeater.count; ++i) {
                var it = moodRepeater.itemAt(i);
                if (it) sum += it.textW;
            }
            moodTextSum = sum;
        }
        width: headerRoot.notchMode ? Math.max(0, Math.min(expandedTargetWidth, notchFrame.centerContentWidth - 8))
                                    : (isExpanded ? expandedTargetWidth : compactWidth)
        // Once the island has finished opening, bring the selected mood into view (it may sit past
        // the right end, e.g. "Tâm trạng"). Until then hover never scrolls: chips sliding under the
        // still cursor (it rests where the compact pill was clicked) would drag the row back to 0.
        property bool settled: false
        onIsExpandedChanged: {
            settled = false;
            if (isExpanded) settleTimer.restart(); else settleTimer.stop();
        }
        Timer {
            id: settleTimer
            interval: headerRoot.notchMode ? 520 : 340 // notch morph is 500 ms, pill width 320 ms
            onTriggered: {
                dynamicMoodIsland.settled = true;
                topMoodFlickable.revealSelected();
            }
        }

        // notch mode: the width already follows the notch's spring frame by frame
        Behavior on width {
            enabled: !headerRoot.notchMode
            NumberAnimation {
                duration: 320
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
            }
        }

        // notch mode: the notch's own glass is the background
        color: headerRoot.notchMode ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
        border.width: headerRoot.notchMode ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        scale: (!isExpanded && compactMouse.containsMouse) ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

        // Compact: the selected mood as a white segment inside the frosted pill
        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: height / 2
            color: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.95)
            Behavior on color { ColorAnimation { duration: 400 } }
            opacity: dynamicMoodIsland.isExpanded || headerRoot.notchMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        // Layer 1: Compact View (Single Active Mood Pill in Center)
        Text {
            id: compactTxt
            anchors.centerIn: parent
            text: headerRoot.formatMoodTitle(headerRoot.selectedMood)
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
            color: dynamicMoodIsland.chipTextColor
            visible: opacity > 0.01
            opacity: dynamicMoodIsland.isExpanded || headerRoot.notchMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            z: dynamicMoodIsland.isExpanded ? -1 : 10
            enabled: !dynamicMoodIsland.isExpanded
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                headerRoot.isMoodIslandExpanded = true;
                autoCollapseTimer.restart();
            }
        }

        Item {
            id: moodScrollMask
            anchors.fill: topMoodFlickable
            visible: false
            layer.enabled: true
            // The capsule mask also carries the scroll edge fades, so they follow the round caps
            // (square overlay rectangles lit the corners outside the pill)
            readonly property real fadeFrac: width > 0 ? 24 / width : 0
            readonly property bool fadeLeft: topMoodFlickable.contentWidth > topMoodFlickable.width && topMoodFlickable.contentX > 4
            readonly property bool fadeRight: topMoodFlickable.contentWidth > topMoodFlickable.width
                && topMoodFlickable.contentX < topMoodFlickable.contentWidth - topMoodFlickable.width - 4
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: moodScrollMask.fadeLeft ? "transparent" : "#ffffff" }
                    GradientStop { position: moodScrollMask.fadeFrac; color: "#ffffff" }
                    GradientStop { position: 1.0 - moodScrollMask.fadeFrac; color: "#ffffff" }
                    GradientStop { position: 1.0; color: moodScrollMask.fadeRight ? "transparent" : "#ffffff" }
                }
            }
        }

        // Layer 2: Expanded View (Full Moods Palette with Liquid Tint Glass)
        Flickable {
            id: topMoodFlickable
            // notch mode: full row size, centered, so the growing island reveals it without moving it
            width: headerRoot.notchMode ? dynamicMoodIsland.expandedTargetWidth - 8 : parent.width - 8
            height: headerRoot.moodRowH
            x: Math.round((parent.width - width) / 2)
            y: 0
            contentWidth: moodRow.width
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            pixelAligned: true
            clip: true
            // A square clip lets chips scrolled to either end poke past the pill's round caps;
            // mask to a capsule concentric with the pill (R 19 - inset 4 = 15, same as a chip)
            // kept on while the mood is on screen: creating the layer on the first frame of the
            // reveal flashed the unmasked row for a frame
            layer.enabled: headerRoot.moodShown
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: moodScrollMask
                maskSpreadAtMin: 1.0 // read the mask's alpha smoothly so the edge fades stay soft
                autoPaddingEnabled: false
            }
            interactive: contentWidth > width && dynamicMoodIsland.isExpanded
            enabled: dynamicMoodIsland.isExpanded
            visible: opacity > 0.01
            // notch mode: fades and drops in from under the icon row as the notch opens
            // (boring.notch inserts content with opacity + move from the top edge)
            opacity: headerRoot.notchMode ? dynamicMoodIsland.revealT : (dynamicMoodIsland.isExpanded ? 1.0 : 0.0)
            Behavior on opacity { enabled: !headerRoot.notchMode; NumberAnimation { duration: 200 } }
            transform: Translate { y: headerRoot.notchMode ? -10 * (1 - dynamicMoodIsland.revealT) : 0 }

            readonly property real accentLuminance: (0.299 * headerRoot.accentColor.r + 0.587 * headerRoot.accentColor.g + 0.114 * headerRoot.accentColor.b)

            WheelHandler {
                target: topMoodFlickable
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                    var maxScroll = Math.max(0, topMoodFlickable.contentWidth - topMoodFlickable.width);
                    topMoodFlickable.contentX = Math.max(0, Math.min(maxScroll, topMoodFlickable.contentX - delta * 1.2));
                }
            }

            Rectangle {
                id: activeMoodIndicator
                height: 30
                radius: 15
                y: (topMoodFlickable.height - height) / 2
                z: 2
                color: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.95)
            Behavior on color { ColorAnimation { duration: 400 } }
                visible: width > 0

                // Geometry of the selected chip (animated when the selection moves)
                property real selX: 0
                property real selW: 0
                Behavior on selX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on selW { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                // A selected chip scrolled half out of view keeps a whole capsule inside the bar: the
                // pill shrinks to the visible part instead of being cut flat by the scroll clip
                readonly property real edgeInset: 2
                readonly property real chipLeft: moodRow.x + selX
                readonly property real viewLeft: topMoodFlickable.contentX + edgeInset
                readonly property real viewRight: topMoodFlickable.contentX + topMoodFlickable.width - edgeInset
                x: Math.max(chipLeft, viewLeft)
                width: Math.max(0, Math.min(chipLeft + selW, viewRight) - x)
            }

            Row {
                id: moodRow
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, (topMoodFlickable.width - width) / 2)
                z: 5
                onWidthChanged: Qt.callLater(topMoodFlickable.updateActiveIndicator)

                Repeater {
                    id: moodRepeater
                    model: headerRoot.activeMoodList
                    onCountChanged: Qt.callLater(dynamicMoodIsland.recalcMoodText)

                    delegate: Item {
                        id: pillItem
                        height: 30
                        width: pillTxt.implicitWidth + dynamicMoodIsland.chipPad
                        readonly property real textW: pillTxt.implicitWidth
                        onTextWChanged: Qt.callLater(dynamicMoodIsland.recalcMoodText)
                        readonly property bool isSelected: headerRoot.selectedMood === modelData.title
                        readonly property bool isHovered: pillMouse.containsMouse

                        onXChanged: {
                            if (isSelected) activeMoodIndicator.selX = pillItem.x;
                        }
                        onWidthChanged: {
                            if (isSelected) activeMoodIndicator.selW = pillItem.width;
                        }
                        onIsSelectedChanged: {
                            if (isSelected) {
                                activeMoodIndicator.selX = pillItem.x;
                                activeMoodIndicator.selW = pillItem.width;
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 15
                            // No per-chip fill: chips sit directly on the frosted pill, hover is an accent tint
                            color: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.22)
                            opacity: (pillItem.isHovered && !pillItem.isSelected) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        Text {
                            id: pillTxt
                            anchors.centerIn: parent
                            text: headerRoot.formatMoodTitle(modelData.title)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: pillItem.isSelected ? Font.Bold : Font.DemiBold
                            color: pillItem.isSelected ? dynamicMoodIsland.chipTextColor
                                   : (pillItem.isHovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.78))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                headerRoot.selectedMood = modelData.title;
                                headerRoot.moodSelected(modelData.title, modelData.params || "");
                                headerRoot.isMoodIslandExpanded = false;
                            }
                            onPositionChanged: mouse => {
                                autoCollapseTimer.restart();
                                topMoodFlickable.hoverReveal(pillMouse, mouse, pillItem);
                            }
                        }
                    }
                }
            }

            NumberAnimation {
                id: moodRevealAnim
                target: topMoodFlickable
                property: "contentX"
                duration: 280
                easing.type: Easing.OutCubic
            }

            function revealChip(item) {
                if (contentWidth <= width) return;
                var edge = 6;
                var left = moodRow.x + item.x, right = left + item.width;
                var target = contentX;
                if (right > contentX + width - edge) target = right - width + edge;
                else if (left < contentX + edge) target = left - edge;
                target = Math.max(0, Math.min(contentWidth - width, target));
                if (Math.abs(target - contentX) < 0.5) return;
                moodRevealAnim.to = target;
                moodRevealAnim.restart();
            }

            // A chip half hidden at either end slides fully into view when the pointer really moves
            // onto it; hover events from chips moving under a still cursor (scene point unchanged) are ignored
            property point lastHoverPoint: Qt.point(-1, -1)
            function hoverReveal(area, mouse, item) {
                var p = area.mapToItem(null, mouse.x, mouse.y);
                var moved = lastHoverPoint.x >= 0 && (Math.abs(p.x - lastHoverPoint.x) + Math.abs(p.y - lastHoverPoint.y)) > 0.5;
                lastHoverPoint = p;
                if (moved && dynamicMoodIsland.settled) revealChip(item);
            }

            function revealSelected() {
                for (var i = 0; i < moodRepeater.count; ++i) {
                    var itm = moodRepeater.itemAt(i);
                    if (itm && itm.isSelected) { revealChip(itm); return; }
                }
            }

            function updateActiveIndicator() {
                for (var i = 0; i < moodRepeater.count; ++i) {
                    var itm = moodRepeater.itemAt(i);
                    if (itm && itm.isSelected) {
                        activeMoodIndicator.selX = itm.x;
                        activeMoodIndicator.selW = itm.width;
                        return;
                    }
                }
            }

            Component.onCompleted: Qt.callLater(updateActiveIndicator)
        }

        // Smart Auto-Collapse Timer: 4500ms idle timer
        Timer {
            id: autoCollapseTimer
            interval: 4500
            repeat: false
            running: false
            onTriggered: {
                if (headerRoot.isMoodIslandExpanded) {
                    headerRoot.isMoodIslandExpanded = false;
                }
            }
        }

        Connections {
            target: headerRoot
            function onIsMoodIslandExpandedChanged() {
                if (headerRoot.isMoodIslandExpanded) {
                    autoCollapseTimer.restart();
                    topMoodFlickable.updateActiveIndicator();
                } else {
                    autoCollapseTimer.stop();
                }
            }
        }
    }

    Connections {
        target: headerRoot
        function onSelectedMoodChanged() {
            topMoodFlickable.updateActiveIndicator();
        }
        function onMoodsChanged() {
            Qt.callLater(topMoodFlickable.updateActiveIndicator);
        }
    }

    Connections {
        target: I18n
        function onLocaleChanged() {
            Qt.callLater(topMoodFlickable.updateActiveIndicator);
        }
    }
}
