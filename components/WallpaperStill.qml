import QtQuick
import QtMultimedia

// One still picture of the desktop wallpaper for the lyrics previews. An image wallpaper is used
// as it is. A video wallpaper (mp4, webm, mkv) is opened once, paused on its first frame and
// grabbed into an image, then the player is unloaded, so the previews cost nothing to keep.
Item {
    id: root

    property string source: ""
    // What an Image can show: the picture itself, or the grabbed frame of a video
    readonly property string still: root.isVideo ? root.grabbedUrl : root.source
    readonly property bool isVideo: root.videoPath(root.source)
    function videoPath(s) { return /\.(mp4|webm|mkv|mov|avi)$/i.test(String(s)); }

    property string grabbedUrl: ""
    property var grabResult: null   // holds the grab alive; its url stops working once freed
    property bool grabbing: false

    // Grabbing needs a rendered item: tiny opacity, never visible:false
    width: 640
    height: 360
    opacity: 0.001
    enabled: false

    onSourceChanged: {
        root.grabbedUrl = "";
        root.grabResult = null;
        root.grabbing = root.videoPath(root.source);
    }
    Component.onCompleted: root.grabbing = root.videoPath(root.source)

    Loader {
        id: grabber
        anchors.fill: parent
        active: root.grabbing && root.visible
        sourceComponent: Item {
            anchors.fill: parent

            MediaPlayer {
                id: player
                source: root.source
                videoOutput: output
                audioOutput: null
                Component.onCompleted: play()
                onErrorOccurred: root.grabbing = false
            }

            VideoOutput {
                id: output
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }

            Connections {
                target: output.videoSink
                function onVideoFrameChanged() {
                    if (player.playbackState !== MediaPlayer.PlayingState) return;
                    player.pause();
                    settle.start();
                }
            }

            // let the paused frame reach the screen before grabbing it
            Timer {
                id: settle
                interval: 120
                onTriggered: output.grabToImage(function (result) {
                    root.grabResult = result;
                    root.grabbedUrl = result.url;
                    root.grabbing = false;
                })
            }
        }
    }
}
