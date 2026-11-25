import QtQuick
import QtQuick.Layouts
import "."

// One setting card, Mochy's anatomy (DESIGN.md "Setting Card"): bold title top-left, description under it,
// a control top-right (headerRight), then the body. Surface is accent-tinted glass with a hairline, never opaque grey.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: card
    property string title: ""
    property string description: ""
    property color accentColor: Theme.accent
    // false hides the body and its spacing, so a card can collapse to its header
    property bool showBody: true
    default property alias body: bodyCol.data
    property alias headerRight: headerRightSlot.data

    implicitHeight: col.implicitHeight + 36
    radius: 20
    color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.08)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, cardHover.hovered ? 0.18 : 0.07)
    Behavior on border.color { ColorAnimation { duration: 160 } }

    HoverHandler { id: cardHover }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 18
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: card.title
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.description !== ""
                    text: card.description
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.25
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            Item {
                id: headerRightSlot
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: childrenRect.width
                Layout.preferredHeight: childrenRect.height
            }
        }

        ColumnLayout {
            id: bodyCol
            Layout.fillWidth: true
            spacing: 8
            visible: card.showBody
        }
    }
}
