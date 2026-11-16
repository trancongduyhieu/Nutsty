import QtQuick

// Creates a rarely used modal only when it is first opened and destroys it again once it has
// stayed closed for releaseDelay, so its objects and textures do not sit in RAM all session.
// Callers open it through ensure(), e.g. myLoader.ensure().openModal(), and read state via item.
Loader {
    id: root

    property int releaseDelay: 30000
    readonly property bool shown: item !== null && item.visible

    function ensure() {
        releaseTimer.stop();
        if (!active)
            active = true;
        return item;
    }

    active: false

    onShownChanged: {
        if (shown)
            releaseTimer.stop();
        else if (item !== null)
            releaseTimer.restart();
    }

    Timer {
        id: releaseTimer
        interval: root.releaseDelay
        onTriggered: {
            if (root.item !== null && !root.item.visible)
                root.active = false;
        }
    }
}
