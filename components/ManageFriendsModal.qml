import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell.Io
import "."

Item {
    id: root
    anchors.fill: parent
    enabled: isOpen || closingGuard
    visible: opacity > 0 || closingGuard
    opacity: isOpen ? 1 : 0
    z: 9999

    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property bool closingGuard: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string currentUserEmail: ""
    property string currentUserName: ""
    property string currentUserAvatar: ""
    property string currentUserPin: ""
    property string currentUserTag: ""
    property bool copiedPinTooltip: false
    property var friends: [] // Array of { email, name, avatar, note }
    property var searchResults: []
    property bool isSearching: false
    property string confirmUnfriendEmail: ""

    property bool isEditingProfile: false
    property bool isUpdatingProfile: false
    property string profileUpdateError: ""

    signal sendFriendRequestRequested(string targetEmail)
    signal unfriendRequested(string targetEmail)
    signal refreshFriendsRequested()
    signal regeneratePinRequested()

    Process {
        id: copyProc
        command: ["wl-copy", root.currentUserTag || (root.currentUserName + (root.currentUserPin ? ("#" + root.currentUserPin) : ""))]
    }

    Timer {
        id: resetPinCopyTimer
        interval: 1800
        repeat: false
        onTriggered: root.copiedPinTooltip = false
    }

    Timer {
        id: closeTimer
        interval: 220
        repeat: false
        onTriggered: root.closingGuard = false
    }

    Timer {
        id: searchDebounceTimer
        interval: 250
        repeat: false
        onTriggered: root.executeUserSearch()
    }

    Timer {
        id: resetUnfriendConfirmTimer
        interval: 3500
        repeat: false
        onTriggered: root.confirmUnfriendEmail = ""
    }

    Timer {
        id: updateProfileTimeoutTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.isUpdatingProfile) {
                root.isUpdatingProfile = false;
                root.profileUpdateError = I18n.tr("Hết thời gian chờ", "Request timeout");
            }
        }
    }

    function openModal() {
        closeTimer.stop();
        root.closingGuard = false;
        root.confirmUnfriendEmail = "";
        searchTextInput.text = "";
        root.searchResults = [];
        root.isOpen = true;
        root.refreshFriendsRequested();
    }

    function closeModal() {
        if (!root.isOpen && !root.closingGuard) return;
        root.isOpen = false;
        root.closingGuard = true;
        root.confirmUnfriendEmail = "";
        closeTimer.restart();
    }

    function executeUserSearch() {
        var q = searchTextInput.text ? searchTextInput.text.trim() : "";
        if (!q) {
            root.searchResults = [];
            root.isSearching = false;
            return;
        }

        root.isSearching = true;
        var apiUrl = (typeof win !== "undefined" && win.notesApiUrl) ? win.notesApiUrl : "https://nutsty-global-relay.nutsty-global-relay.workers.dev";
        var url = apiUrl + "/api/users/search?q=" + encodeURIComponent(q) + "&user_email=" + encodeURIComponent(root.currentUserEmail);

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.isSearching = false;
                if (xhr.status === 200) {
                    try {
                        var parsed = JSON.parse(xhr.responseText);
                        root.searchResults = (parsed && Array.isArray(parsed.results)) ? parsed.results : [];
                    } catch(e) {
                        root.searchResults = [];
                    }
                }
            }
        };
        xhr.send();
    }

    // Full screen 70% dark scrim backdrop (Chống xuyên thấu màn hình theo yêu cầu)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.70)
        opacity: root.isOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    // Dismiss backdrop (click outside to close)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeModal()
    }

    // Modal Glass Dialog Container (Keo 502 Dark Glass - Nền phẳng, chữ phẳng)
    Item {
        id: modalDialog
        width: Math.min(540, root.width - 32)
        height: Math.min(620, root.height - 40)
        anchors.centerIn: parent

        scale: root.isOpen ? 1 : 0.94
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutBack }
        }


        // Dark Acrylic Base for crisp contrast (Không bị xuyên thấu chữ/ảnh nền)
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Qt.rgba(0.06, 0.07, 0.10, 0.85)
            z: 1
        }

        // Keo 502 LiquidGlass container
        LiquidGlass {
            id: glassCard
            anchors.fill: parent
            radius: 24
            displacement: 18.0
            aberration: 0.03
            bevelWidth: 24.0
            tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
            backgroundSourceItem: root.backgroundSourceItem
            isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
            clip: true
            z: 2

            // Dark tint layer over glass so text never suffers from backlight interference
            Rectangle {
                anchors.fill: parent
                radius: glassCard.radius
                color: Qt.rgba(0.04, 0.05, 0.08, 0.70)
                z: 0
            }

            // Hairline Accent Border
            Rectangle {
                anchors.fill: parent
                radius: glassCard.radius
                color: "transparent"
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                border.width: 1
                z: 1
            }

            // Prevent clicks inside modal from closing
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: 1
                onPressed: mouse => mouse.accepted = true
                onReleased: mouse => mouse.accepted = true
                onClicked: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14
                z: 10

                // 1. TOP HEADER ROW: Title + Close Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    AppIcon {
                        source: "../assets/icons/system-users-symbolic.svg"
                        iconSize: 18
                        color: root.accentColor
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Quản lý bạn bè", "Manage Friends")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }

                    // Nút Đóng [ ✕ ]
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 13
                            color: "#ffffff"
                            opacity: closeMouse.containsMouse ? 1.0 : 0.70
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeModal()
                        }
                    }
                }

                // 2. THẺ ĐỊNH DANH CÁ NHÂN (Nutsty Discord-style Tag Card)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isEditingProfile ? 154 : 54
                    radius: 16
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                    border.width: 1
                    clip: true

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Dòng 1: Avatar + Tên#Tag + Nút Copy Tag + Nút Đổi tên/Tag
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            RoundedImage {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 17
                                source: root.currentUserAvatar || ""
                                initialsText: root.currentUserName || root.currentUserEmail || "User"
                                fallbackIcon: "../assets/icons/preferences-system-symbolic.svg"
                                borderWidth: 1
                                borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.50)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                RowLayout {
                                    spacing: 4
                                    Text {
                                        text: root.currentUserName || "User"
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.currentUserPin ? ("#" + root.currentUserPin) : ""
                                        color: root.accentColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentUserTag || (root.currentUserName + (root.currentUserPin ? ("#" + root.currentUserPin) : ""))
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            // Nút Sao chép Tag [ 📋 Sao chép ]
                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: copyTagRow.implicitWidth + 16
                                radius: 14
                                color: copyTagM.containsMouse
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, copyTagM.containsMouse ? 0.85 : 0.40)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    id: copyTagRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    AppIcon {
                                        source: "../assets/icons/edit-copy-symbolic.svg"
                                        iconSize: 11
                                        color: root.copiedPinTooltip ? "#4ade80" : root.accentColor
                                    }

                                    Text {
                                        text: root.copiedPinTooltip ? I18n.tr("Đã chép!", "Copied!") : I18n.tr("Sao chép Tag", "Copy Tag")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: root.copiedPinTooltip ? "#4ade80" : "#ffffff"
                                    }
                                }

                                MouseArea {
                                    id: copyTagM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var fullTag = root.currentUserTag || (root.currentUserName + (root.currentUserPin ? ("#" + root.currentUserPin) : ""));
                                        copyProc.running = false;
                                        copyProc.command = ["wl-copy", fullTag];
                                        copyProc.running = true;
                                        root.copiedPinTooltip = true;
                                        resetPinCopyTimer.restart();
                                    }
                                }
                            }

                            // Nút Mở bảng Đổi tên & Tag [ ✎ ]
                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: editTagRow.implicitWidth + 16
                                radius: 14
                                color: root.isEditingProfile
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                                    : (editTagM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.07))
                                border.color: root.isEditingProfile
                                    ? root.accentColor
                                    : Qt.rgba(1, 1, 1, editTagM.containsMouse ? 0.30 : 0.15)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    id: editTagRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    AppIcon {
                                        source: "../assets/icons/accessories-text-editor-symbolic.svg"
                                        iconSize: 11
                                        color: root.isEditingProfile ? root.accentColor : (editTagM.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.70))
                                    }

                                    Text {
                                        text: I18n.tr("Đổi tên", "Edit")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: root.isEditingProfile ? root.accentColor : (editTagM.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.85))
                                    }
                                }

                                MouseArea {
                                    id: editTagM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.isEditingProfile = !root.isEditingProfile;
                                        if (root.isEditingProfile) {
                                            editNameInput.text = root.currentUserName || "User";
                                            editDiscInput.text = root.currentUserPin || "";
                                            root.profileUpdateError = "";
                                            editNameInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }

                        // Dòng 2 (Mở rộng khi isEditingProfile): Form đổi tên & Tag định danh
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.isEditingProfile
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.08)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Ô nhập Tên mới
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    border.color: editNameInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.20)
                                    border.width: 1

                                    TextInput {
                                        id: editNameInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: "#ffffff"
                                        maximumLength: 32
                                        selectByMouse: true
                                    }
                                }

                                Text {
                                    text: "#"
                                    color: root.accentColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                // Ô nhập Tag 4 số
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    border.color: editDiscInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.20)
                                    border.width: 1

                                    TextInput {
                                        id: editDiscInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        horizontalAlignment: TextInput.AlignHCenter
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.accentColor
                                        maximumLength: 4
                                        selectByMouse: true
                                    }
                                }

                                // Nút Random Tag 4 số [ 🎲 ]
                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: rndTagM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                    border.color: Qt.rgba(1, 1, 1, 0.20)
                                    border.width: 1

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/view-refresh-symbolic.svg"
                                        iconSize: 12
                                        color: rndTagM.containsMouse ? root.accentColor : "#ffffff"
                                    }

                                    MouseArea {
                                        id: rndTagM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var rnd = String(Math.floor(1000 + Math.random() * 9000));
                                            editDiscInput.text = rnd;
                                        }
                                    }
                                }

                                // Nút Lưu
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: saveProfileM.containsMouse
                                        ? root.accentColor
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                    border.color: root.accentColor
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isUpdatingProfile ? "..." : I18n.tr("Lưu", "Save")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: saveProfileM.containsMouse ? "#ffffff" : root.accentColor
                                    }

                                    MouseArea {
                                        id: saveProfileM
                                        anchors.fill: parent
                                        enabled: !root.isUpdatingProfile
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var newName = editNameInput.text ? editNameInput.text.trim() : "";
                                            var newDisc = editDiscInput.text ? editDiscInput.text.trim() : "";
                                            if (!newName) return;
                                            root.isUpdatingProfile = true;
                                            root.profileUpdateError = "";
                                            updateProfileTimeoutTimer.restart();
                                            if (typeof win !== "undefined" && typeof win.updateUserProfile === "function") {
                                                win.updateUserProfile(newName, newDisc, function(success, res) {
                                                    updateProfileTimeoutTimer.stop();
                                                    root.isUpdatingProfile = false;
                                                    if (success) {
                                                        root.isEditingProfile = false;
                                                        if (res && res.user) {
                                                            root.currentUserName = res.user.username || newName;
                                                            root.currentUserPin = res.user.discriminator || newDisc;
                                                            root.currentUserTag = res.user.tag || (newName + "#" + newDisc);
                                                        }
                                                        root.refreshFriendsRequested();
                                                    } else {
                                                        var err = (res && res.error) ? res.error : I18n.tr("Thất bại", "Failed");
                                                        if (res && res.suggested_tag) {
                                                            err += I18n.tr(" (Gợi ý: ", " (Suggested: ") + res.suggested_tag + ")";
                                                        }
                                                        root.profileUpdateError = err;
                                                    }
                                                });
                                            } else {
                                                updateProfileTimeoutTimer.stop();
                                                root.isUpdatingProfile = false;
                                                root.isEditingProfile = false;
                                            }
                                        }
                                    }
                                }

                                // Nút Hủy
                                Rectangle {
                                    Layout.preferredWidth: 54
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: cancelProfileM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                                    border.color: Qt.rgba(1, 1, 1, 0.20)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Hủy", "Cancel")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Qt.rgba(1, 1, 1, 0.70)
                                    }

                                    MouseArea {
                                        id: cancelProfileM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.isEditingProfile = false;
                                            root.profileUpdateError = "";
                                        }
                                    }
                                }
                            }

                            // Thông báo lỗi nếu trùng tag
                            Text {
                                Layout.fillWidth: true
                                visible: root.profileUpdateError.length > 0
                                text: root.profileUpdateError
                                color: Qt.rgba(251, 113, 133, 0.95)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // 3. SEARCH ENGINE SECTION (Reusing Search Engine UX - Pill, accent ring, live typing)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    Rectangle {
                        id: searchBoxContainer
                        anchors.fill: parent
                        radius: 20
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: searchTextInput.activeFocus
                            ? root.accentColor
                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/system-search-symbolic.svg"
                                iconSize: 15
                                color: searchTextInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.50)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            TextInput {
                                id: searchTextInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: "#ffffff"
                                selectByMouse: true
                                clip: true

                                Text {
                                    text: I18n.tr("Nhập Nutsty Tag (ví dụ: Shiraori#6180) hoặc tên...", "Enter Nutsty Tag (e.g. Shiraori#6180) or name...")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Qt.rgba(1, 1, 1, 0.40)
                                    visible: searchTextInput.text.length === 0 && !searchTextInput.activeFocus
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                onTextChanged: searchDebounceTimer.restart()
                                onAccepted: {
                                    searchDebounceTimer.stop();
                                    root.executeUserSearch();
                                }
                            }

                            // Spinner khi đang tìm kiếm
                            CircularSpinner {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                visible: root.isSearching
                                running: root.isSearching
                                color: root.accentColor
                                strokeWidth: 2
                            }

                            // Nút xóa nhanh [ ✕ ]
                            Item {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                visible: searchTextInput.text.length > 0 && !root.isSearching

                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/edit-clear-all-symbolic.svg"
                                    iconSize: 13
                                    color: clearSearchM.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.50)
                                }

                                MouseArea {
                                    id: clearSearchM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchTextInput.text = "";
                                        root.searchResults = [];
                                    }
                                }
                            }
                        }
                    }
                }

                // SEARCH RESULTS POP-DOWN - NỀN PHẲNG, CHỮ PHẲNG (Không lồng hộp)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (root.searchResults && root.searchResults.length > 0) || (searchTextInput.text.trim().length >= 3 && !root.isSearching)
                    spacing: 6

                    Text {
                        text: I18n.tr("Kết quả tìm kiếm", "Search Results")
                        color: root.accentColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Text {
                        visible: searchTextInput.text.trim().length >= 3 && !root.isSearching && (!root.searchResults || root.searchResults.length === 0)
                        text: I18n.tr("Không tìm thấy người dùng", "No user found")
                        color: Qt.rgba(1, 1, 1, 0.50)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    ListView {
                        id: searchResultsList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(130, count * 44)
                        visible: root.searchResults && root.searchResults.length > 0
                        model: root.searchResults || []
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: searchResultsList.width
                            height: 38

                            RowLayout {
                                anchors.fill: parent
                                spacing: 10

                                RoundedImage {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    source: modelData.avatar || ""
                                    initialsText: modelData.name || modelData.email || ""
                                    fallbackIcon: "../assets/icons/system-users-symbolic.svg"
                                    borderWidth: 1
                                    borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            text: modelData.name || modelData.username || modelData.email
                                            color: "#ffffff"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: !!modelData.discriminator || !!modelData.pin_code
                                            text: "#" + (modelData.discriminator || modelData.pin_code)
                                            color: root.accentColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.tag || modelData.nutsty_tag || modelData.email || ""
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                // Status / Action Button phẳng
                                Item {
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: 26

                                    // 1. Nếu là chính mình
                                    Text {
                                        anchors.centerIn: parent
                                        visible: modelData.is_self
                                        text: I18n.tr("(Bạn)", "(You)")
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }

                                    // 2. Nếu đã là bạn bè
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !modelData.is_self && modelData.is_friend
                                        text: I18n.tr("✓ Bạn bè", "✓ Friends")
                                        color: root.accentColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    // 3. Nếu đã gửi lời mời
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !modelData.is_self && !modelData.is_friend && modelData.has_outgoing_request
                                        text: I18n.tr("Đã gửi lời mời", "Request sent")
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }

                                    // 4. Nút Gửi lời mời kết bạn phẳng
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: !modelData.is_self && !modelData.is_friend && !modelData.has_outgoing_request
                                        radius: 13
                                        color: sendReqM.containsMouse
                                            ? root.accentColor
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, sendReqM.containsMouse ? 0.90 : 0.45)
                                        border.width: 1
                                        scale: sendReqM.containsMouse ? 1.04 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: I18n.tr("+ Kết bạn", "+ Add")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: sendReqM.containsMouse ? "#ffffff" : root.accentColor
                                        }

                                        MouseArea {
                                            id: sendReqM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.sendFriendRequestRequested(modelData.email);
                                                modelData.has_outgoing_request = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                }

                // 3. CURRENT FRIENDS LIST SECTION (Nền phẳng, chữ phẳng, không hộp lồng hộp)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Danh sách bạn bè", "Friends List") + (root.friends ? " (" + root.friends.length + ")" : " (0)")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                // Empty State phẳng khi chưa có bạn bè nào
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.friends || root.friends.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            source: "../assets/icons/system-users-symbolic.svg"
                            iconSize: 32
                            color: root.accentColor
                            opacity: 0.4
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr("Chưa có bạn bè nào", "No friends yet")
                            color: Qt.rgba(1, 1, 1, 0.70)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr("Hãy nhập mã PIN 6 số, Nutsty Tag hoặc email ở ô trên để tìm và kết bạn!", "Search by 6-digit PIN, Nutsty Tag or email above to connect!")
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }

                // ListView bạn bè hiện tại - NỀN PHẲNG, CHỮ PHẲNG
                ListView {
                    id: friendsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.friends && root.friends.length > 0
                    model: root.friends || []
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        width: friendsList.width
                        height: 48

                        RowLayout {
                            anchors.fill: parent
                            spacing: 12

                            // Avatar tròn phẳng không răng cưa
                            RoundedImage {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: 19
                                source: modelData.avatar || ""
                                initialsText: modelData.name || modelData.email || "Friend"
                                fallbackIcon: "../assets/icons/system-users-symbolic.svg"
                                borderWidth: 1
                                borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                            }

                            // Tên và Tag phẳng
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: modelData.name || modelData.username || "Friend"
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: !!modelData.discriminator || (modelData.tag && modelData.tag.includes("#"))
                                        text: modelData.discriminator ? ("#" + modelData.discriminator) : ("#" + modelData.tag.split("#")[1])
                                        color: root.accentColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.tag || modelData.nutsty_tag || modelData.email || ""
                                    color: Qt.rgba(1, 1, 1, 0.50)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            // Nút phẳng "Hủy kết bạn" (Muted Rose) kèm xác nhận inline
                            Rectangle {
                                id: unfriendBtn
                                readonly property bool isConfirming: root.confirmUnfriendEmail === (modelData.email || "")
                                Layout.preferredWidth: isConfirming ? 104 : 88
                                Layout.preferredHeight: 28
                                radius: 14
                                color: unfriendM.containsMouse
                                    ? (isConfirming ? Qt.rgba(244, 63, 94, 0.40) : Qt.rgba(244, 63, 94, 0.25))
                                    : (isConfirming ? Qt.rgba(244, 63, 94, 0.28) : Qt.rgba(244, 63, 94, 0.12))
                                border.color: Qt.rgba(244, 63, 94, isConfirming ? 0.75 : (unfriendM.containsMouse ? 0.55 : 0.25))
                                border.width: 1
                                scale: unfriendM.containsMouse ? 1.04 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    AppIcon {
                                        source: "../assets/icons/user-trash-symbolic.svg"
                                        iconSize: 11
                                        color: Qt.rgba(251, 113, 133, 0.95)
                                    }

                                    Text {
                                        text: unfriendBtn.isConfirming
                                            ? I18n.tr("Xác nhận?", "Confirm?")
                                            : I18n.tr("Hủy kết bạn", "Unfriend")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Qt.rgba(251, 113, 133, 0.95)
                                    }
                                }

                                MouseArea {
                                    id: unfriendM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var target = modelData.email || "";
                                        if (root.confirmUnfriendEmail === target) {
                                            root.confirmUnfriendEmail = "";
                                            resetUnfriendConfirmTimer.stop();
                                            root.unfriendRequested(target);
                                        } else {
                                            root.confirmUnfriendEmail = target;
                                            resetUnfriendConfirmTimer.restart();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
