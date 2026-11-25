import QtQuick
import QtQuick.Layouts
import "."

// One setting group in the flat anatomy of the other Settings rows: 13px bold title, 11px description,
// a control on the right (headerRight), then the body. No surface of its own, so it sits in line with the rows below.
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

    implicitHeight: col.implicitHeight + 12
    color: "transparent"

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: card.title
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.description !== ""
                    text: card.description
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            Item {
                id: headerRightSlot
                Layout.alignment: Qt.AlignVCenter
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
