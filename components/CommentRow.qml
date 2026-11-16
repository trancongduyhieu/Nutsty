import QtQuick
import QtQuick.Layouts
import "."

// One row of MochyCommentsView: a comment, a reply (indented) or a "more replies" link.
Item {
    id: row

    required property int index
    required property string kind
    required property string cid
    required property string parentId
    required property string author
    required property string avatar
    required property string text
    required property string published
    required property string likes
    required property bool isCreator
    required property bool isVerified
    required property bool isPinned
    required property bool isHearted
    required property string repliesLabel
    required property string repliesToken
    required property string replyParams
    required property bool expanded
    required property bool busy

    property color accentColor: Theme.accent
    property bool canReply: false
    property bool replyTargeted: false

    signal toggleRepliesRequested()
    signal replyRequested()
    signal moreRepliesRequested()

    readonly property bool isReply: kind === "reply"
    readonly property bool isMore: kind === "more"
    readonly property real indent: isReply || isMore ? 40 : 0
    readonly property real avatarSize: isReply ? 24 : 32

    // YouTube answers in English; these keep Vietnamese mode free of English fragments
    function relTime(s) {
        s = String(s || "");
        if (!I18n.isVietnamese) return s;
        var units = { second: "giây", minute: "phút", hour: "giờ", day: "ngày", week: "tuần", month: "tháng", year: "năm" };
        var edited = s.indexOf("(edited)") !== -1;
        var m = s.match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/);
        var out = m ? (m[1] + " " + units[m[2]] + " trước") : s.replace("(edited)", "").trim();
        return edited ? out + " (đã sửa)" : out;
    }

    function repliesText(label) {
        var m = String(label || "").match(/[\d.,]+\s*[KMB]?/i);
        var n = m ? m[0].replace(/\s+/g, "") : "";
        if (!n) return I18n.tr("Xem phản hồi", "View replies");
        return I18n.tr(n + " phản hồi", n + (n === "1" ? " reply" : " replies"));
    }

    implicitHeight: isMore ? 32 : body.implicitHeight + 20

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: row.indent
        radius: 14
        visible: !row.isMore
        color: Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b,
                       row.replyTargeted ? 0.14 : (rowHover.hovered ? 0.08 : 0.0))
        Behavior on color { ColorAnimation { duration: 140 } }
    }
    HoverHandler { id: rowHover; enabled: !row.isMore }

    // Tapping a comment opens or closes its replies
    MouseArea {
        anchors.fill: parent
        enabled: !row.isMore && row.kind === "comment" && row.repliesToken !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.toggleRepliesRequested()
    }

    Text {
        visible: row.isMore
        anchors.left: parent.left
        anchors.leftMargin: row.indent + 8
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr("Xem thêm phản hồi", "Show more replies")
        color: row.accentColor
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        opacity: moreMouse.containsMouse ? 1.0 : 0.85
        MouseArea {
            id: moreMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.moreRepliesRequested()
        }
    }

    RowLayout {
        id: body
        visible: !row.isMore
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: row.indent + 10
        anchors.rightMargin: 10
        anchors.topMargin: 10
        spacing: 10

        RoundedImage {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: row.avatarSize
            Layout.preferredHeight: row.avatarSize
            radius: row.avatarSize / 2
            source: row.avatar
            sourceSize: Qt.size(row.avatarSize * 2, row.avatarSize * 2)
            initialsText: row.author.replace(/^@/, "").slice(0, 1).toUpperCase()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                visible: row.isPinned
                spacing: 4
                AppIcon {
                    source: "../assets/icons/material/ms-push_pin.svg"
                    iconSize: 11
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
                Text {
                    text: I18n.tr("Đã ghim", "Pinned")
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // The uploader's own comments get an accent capsule, as on YouTube
                Rectangle {
                    Layout.maximumWidth: body.width - 120
                    Layout.preferredWidth: authorText.implicitWidth + (row.isCreator ? 14 : 0)
                    Layout.preferredHeight: authorText.implicitHeight + (row.isCreator ? 4 : 0)
                    radius: height / 2
                    color: row.isCreator ? Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.28) : "transparent"
                    Text {
                        id: authorText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - (row.isCreator ? 14 : 0))
                        text: row.author
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.relTime(row.published)
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.text
                color: Qt.rgba(1, 1, 1, 0.9)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.Wrap
                lineHeight: 1.15
                textFormat: Text.PlainText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 14

                RowLayout {
                    spacing: 4
                    AppIcon {
                        source: "../assets/icons/material/ms-thumb_up.svg"
                        iconSize: 13
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    Text {
                        visible: row.likes !== "" && row.likes !== "0"
                        text: row.likes
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                AppIcon {
                    visible: row.isHearted
                    source: "../assets/icons/material/ms-favorite-fill.svg"
                    iconSize: 13
                    color: Qt.rgba(0.96, 0.25, 0.37, 1)
                }

                Text {
                    visible: row.canReply && (row.replyParams !== "" || row.isReply)
                    text: I18n.tr("Trả lời", "Reply")
                    color: replyMouse.containsMouse ? row.accentColor : Qt.rgba(1, 1, 1, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    MouseArea {
                        id: replyMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.replyRequested()
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    visible: row.kind === "comment" && row.repliesToken !== ""
                    spacing: 4
                    Text {
                        text: row.expanded ? I18n.tr("Ẩn phản hồi", "Hide replies") : row.repliesText(row.repliesLabel)
                        color: row.accentColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    CircularSpinner {
                        visible: row.busy
                        size: 12
                        strokeWidth: 1.6
                        color: row.accentColor
                        running: visible
                    }
                }
            }
        }
    }
}
