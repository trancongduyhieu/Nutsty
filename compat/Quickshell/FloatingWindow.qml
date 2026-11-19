import QtQuick
import QtQuick.Window

Window {
    id: root
    default property alias contentData: root.data
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    property real implicitWidth: 1280
    property real implicitHeight: 820

    // Auto-fit screen: Constrain initial width & height to available screen dimensions
    // so window buttons never get clipped on lower resolutions (800x600, 1024x768, 1280x720)
    width: Math.min(root.implicitWidth > 0 ? root.implicitWidth : 1280, Math.max(760, (Screen.desktopAvailableWidth || 800) - 16))
    height: Math.min(root.implicitHeight > 0 ? root.implicitHeight : 820, Math.max(500, (Screen.desktopAvailableHeight || 600) - 30))

    // Auto-center window on screen
    x: Math.max(0, Math.round(((Screen.desktopAvailableWidth || 800) - width) / 2))
    y: Math.max(0, Math.round(((Screen.desktopAvailableHeight || 600) - height) / 2))

    property bool maximized: root.visibility === Window.Maximized
    property bool fullscreen: root.visibility === Window.FullScreen
    readonly property bool minimized: root.visibility === Window.Minimized

    // Windows keeps a minimized Qt Quick window exposed, so it goes on re-rendering every
    // progress/lyric tick (10-20% of a core on the CPU renderer while music plays). Opacity 0
    // makes the scene graph skip the whole tree; `visible: false` would fire every view's
    // onVisibleChanged on restore (wiping a half-written note, re-fetching lyrics).
    Binding {
        target: root.contentItem
        property: "opacity"
        value: root.minimized ? 0.0 : 1.0
    }

    onMaximizedChanged: {
        if (maximized && root.visibility !== Window.Maximized) {
            root.showMaximized();
        } else if (!maximized && root.visibility === Window.Maximized) {
            root.showNormal();
        }
    }

    signal closed()
    // Alt+F4 / taskbar "Close window": the shell decides (minimize to the taskbar), so a
    // plain close never drops the taskbar button while music keeps playing
    onClosing: closeEvent => {
        closeEvent.accepted = false;
        root.closed();
    }

    Component.onCompleted: {
        root.show();
        root.raise();
        root.requestActivate();
    }
}
