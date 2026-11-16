pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "."

// YouTube comments for the playing track, the third Mochy tab. Data comes from /api/comments*
// (backend/youtube_comments.py). Replies are inserted as rows right under their comment, so one
// ListModel keeps scroll position stable while pages and replies arrive.
Item {
    id: root

    property string videoId: ""
    property color accentColor: Theme.accent
    property bool isLoggedIn: false
    property bool active: false
    // Space kept free at the bottom for the Mochy action row
    property real bottomInset: 0

    signal closeRequested()

    readonly property string apiBase: "http://127.0.0.1:17890/api/comments"
    property string loadedFor: ""
    property int generation: 0
    property bool loading: false
    property bool loadingMore: false
    property string errorText: ""
    property bool disabledComments: false
    property string countText: ""
    property string createParams: ""
    property string nextToken: ""
    property var seenIds: ({})
    // Reply target: empty cid means a new top-level comment
    property string replyCid: ""
    property string replyAuthor: ""
    property string replyParams: ""
    property bool sending: false
    property string sendError: ""

    readonly property bool canPost: root.isLoggedIn && root.createParams !== ""

    ListModel { id: commentModel }

    function request(method, path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var data = null;
            try { data = JSON.parse(xhr.responseText); } catch (e) {}
            cb(xhr.status === 200 && data && !data.error ? data : null, data);
        };
        xhr.open(method, root.apiBase + path);
        if (body) {
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.send(JSON.stringify(body));
        } else {
            xhr.send();
        }
    }

    // YouTube answers in English; these keep Vietnamese mode free of English fragments
    function leadingNumber(s) {
        var m = String(s || "").match(/[\d.,]+\s*[KMB]?/i);
        return m ? m[0].replace(/\s+/g, "") : "";
    }

    function rowFor(c, kind, parentId) {
        return {
            kind: kind, cid: c.id || "", parentId: parentId || "",
            author: c.author || "", avatar: c.avatar || "", text: c.text || "",
            published: c.published || "", likes: c.likes || "",
            isCreator: !!c.isCreator, isVerified: !!c.isVerified,
            isPinned: !!c.isPinned, isHearted: !!c.isHearted,
            repliesLabel: c.repliesLabel || "", repliesToken: c.repliesToken || "",
            replyParams: c.replyParams || "", expanded: false, busy: false, token: ""
        };
    }

    function moreRow(parentId, token) {
        var r = rowFor({}, "more", parentId);
        r.token = token;
        return r;
    }

    function reset() {
        root.generation++;
        commentModel.clear();
        root.seenIds = ({});
        root.nextToken = "";
        root.countText = "";
        root.createParams = "";
        root.errorText = "";
        root.disabledComments = false;
        root.loadingMore = false;
        root.clearReply();
    }

    function load() {
        reset();
        root.loadedFor = root.videoId;
        if (!root.videoId) return;
        var gen = root.generation;
        root.loading = true;
        request("GET", "?videoId=" + encodeURIComponent(root.videoId), null, function(data, raw) {
            if (gen !== root.generation) return;
            root.loading = false;
            if (!data) {
                root.errorText = I18n.tr("Không tải được bình luận", "Could not load comments");
                return;
            }
            root.disabledComments = !!data.disabled;
            if (data.header) {
                root.countText = leadingNumber(data.header.count);
                root.createParams = data.header.createParams || "";
            }
            appendTop(data.comments || []);
            root.nextToken = data.next || "";
        });
    }

    function appendTop(list) {
        var added = 0;
        for (var i = 0; i < list.length; i++) {
            var c = list[i];
            if (!c.id || root.seenIds[c.id]) continue;
            root.seenIds[c.id] = true;
            commentModel.append(rowFor(c, "comment", ""));
            added++;
        }
        return added;
    }

    function loadMore() {
        if (!root.nextToken || root.loadingMore || root.loading) return;
        var gen = root.generation;
        root.loadingMore = true;
        request("GET", "/page?token=" + encodeURIComponent(root.nextToken), null, function(data) {
            if (gen !== root.generation) return;
            root.loadingMore = false;
            if (!data) return;
            // A page with nothing new means YouTube started repeating itself
            var added = appendTop(data.comments || []);
            root.nextToken = added > 0 ? (data.next || "") : "";
        });
    }

    // Index right after a comment's reply rows (and its "more" row)
    function endOfThread(index) {
        var cid = commentModel.get(index).cid;
        var j = index + 1;
        while (j < commentModel.count && commentModel.get(j).parentId === cid) j++;
        return j;
    }

    function fetchReplies(parentIndex, token, insertAt) {
        var parent = commentModel.get(parentIndex);
        var cid = parent.cid;
        var gen = root.generation;
        commentModel.setProperty(parentIndex, "busy", true);
        request("GET", "/page?token=" + encodeURIComponent(token), null, function(data) {
            if (gen !== root.generation) return;
            var idx = -1;
            for (var k = 0; k < commentModel.count; k++) {
                if (commentModel.get(k).cid === cid && commentModel.get(k).kind === "comment") { idx = k; break; }
            }
            if (idx < 0) return;
            commentModel.setProperty(idx, "busy", false);
            if (!data) return;
            var at = insertAt < 0 ? endOfThread(idx) : insertAt;
            var list = data.comments || [];
            var start = at;
            for (var i = 0; i < list.length; i++) {
                var c = list[i];
                if (!c.id || root.seenIds[c.id]) continue;
                root.seenIds[c.id] = true;
                commentModel.insert(at++, rowFor(c, "reply", cid));
            }
            if (data.next) commentModel.insert(at, moreRow(cid, data.next));
            // The count can include deleted replies; with nothing to show, drop the toggle
            if (at === start && !data.next && insertAt < 0) commentModel.setProperty(idx, "repliesToken", "");
            else commentModel.setProperty(idx, "expanded", true);
        });
    }

    function toggleReplies(index) {
        var row = commentModel.get(index);
        if (row.kind !== "comment" || !row.repliesToken || row.busy) return;
        if (row.expanded) {
            var end = endOfThread(index);
            for (var j = end - 1; j > index; j--) {
                var r = commentModel.get(j);
                if (r.kind === "reply") delete root.seenIds[r.cid];
                commentModel.remove(j);
            }
            commentModel.setProperty(index, "expanded", false);
        } else {
            fetchReplies(index, row.repliesToken, -1);
        }
    }

    function loadMoreReplies(moreIndex) {
        var row = commentModel.get(moreIndex);
        var token = row.token;
        for (var k = moreIndex - 1; k >= 0; k--) {
            if (commentModel.get(k).kind === "comment") {
                commentModel.remove(moreIndex);
                fetchReplies(k, token, moreIndex);
                return;
            }
        }
    }

    function startReply(index) {
        var row = commentModel.get(index);
        // Replying to a reply goes to its thread's top comment, like on YouTube
        var target = index;
        if (row.kind === "reply") {
            for (var k = index - 1; k >= 0; k--) {
                if (commentModel.get(k).kind === "comment") { target = k; break; }
            }
        }
        var t = commentModel.get(target);
        if (!t.replyParams) return;
        root.replyCid = t.cid;
        root.replyAuthor = row.author;
        root.replyParams = t.replyParams;
        commentInput.forceActiveFocus();
    }

    function clearReply() {
        root.replyCid = "";
        root.replyAuthor = "";
        root.replyParams = "";
        root.sendError = "";
    }

    function send() {
        var pre = commentInput.preeditText ? String(commentInput.preeditText) : "";
        var text = (commentInput.text + pre).trim();
        if (!text || root.sending) return;
        var isReply = root.replyCid !== "";
        var params = isReply ? root.replyParams : root.createParams;
        if (!params) return;
        var gen = root.generation;
        var parentCid = root.replyCid;
        root.sending = true;
        root.sendError = "";
        request("POST", isReply ? "/reply" : "/create", { params: params, text: text }, function(data) {
            root.sending = false;
            if (gen !== root.generation) return;
            if (!data || !data.success) {
                root.sendError = I18n.tr("Chưa gửi được, thử lại sau", "Could not post, try again later");
                return;
            }
            commentInput.text = "";
            var c = data.comment || { id: "local-" + Date.now(), author: I18n.tr("Bạn", "You"), text: text, published: "" };
            if (c.id) root.seenIds[c.id] = true;
            if (isReply) {
                for (var k = 0; k < commentModel.count; k++) {
                    if (commentModel.get(k).cid === parentCid && commentModel.get(k).kind === "comment") {
                        commentModel.insert(k + 1, rowFor(c, "reply", parentCid));
                        break;
                    }
                }
            } else {
                commentModel.insert(0, rowFor(c, "comment", ""));
                commentList.positionViewAtBeginning();
            }
            root.clearReply();
        });
    }

    onVideoIdChanged: {
        if (root.active) load();
        else root.loadedFor = "";
    }
    onActiveChanged: {
        if (root.active && root.loadedFor !== root.videoId) load();
    }

    // Header
    Item {
        id: commentsHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 16
        height: 48
        z: 20

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                id: titleText
                text: I18n.tr("Bình luận", "Comments")
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: "#ffffff"
            }
            Text {
                anchors.baseline: titleText.baseline
                visible: root.countText !== ""
                text: root.countText
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.55)
            }
        }

        Item {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            HoverHandler { id: closeH }
            scale: closeH.hovered ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 120 } }

            Rectangle {
                anchors.fill: parent
                radius: 15
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, closeH.hovered ? 0.28 : 0.14)
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/window-close-symbolic.svg"
                    iconSize: 12
                    color: "#ffffff"
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }

    ListView {
        id: commentList
        anchors.top: commentsHeader.bottom
        anchors.bottom: composer.visible ? composer.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: composer.visible ? 8 : root.bottomInset
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: commentModel
        visible: commentModel.count > 0

        onContentYChanged: {
            if (contentHeight - (contentY + height) < 600) root.loadMore();
        }
        onCountChanged: {
            // A short first page may not fill the view, so scrolling would never ask for more
            if (contentHeight < height * 1.5) root.loadMore();
        }

        footer: Item {
            width: commentList.width
            height: root.loadingMore ? 48 : 12
            CircularSpinner {
                anchors.centerIn: parent
                visible: root.loadingMore
                size: 22
                color: root.accentColor
                running: visible
            }
        }

        delegate: CommentRow {
            id: commentDelegate
            width: commentList.width
            accentColor: root.accentColor
            canReply: root.isLoggedIn
            replyTargeted: root.replyCid !== "" && (commentDelegate.cid === root.replyCid || commentDelegate.parentId === root.replyCid)
            onToggleRepliesRequested: root.toggleReplies(commentDelegate.index)
            onReplyRequested: root.startReply(commentDelegate.index)
            onMoreRepliesRequested: root.loadMoreReplies(commentDelegate.index)
        }
    }

    // Loading / empty / error states
    CircularSpinner {
        anchors.centerIn: parent
        visible: root.loading
        size: 32
        color: root.accentColor
        running: visible
    }

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 340)
        visible: !root.loading && commentModel.count === 0
        icon: "../assets/icons/material/ms-forum.svg"
        shape: "clover"
        accentColor: root.accentColor
        title: root.errorText !== "" ? root.errorText
             : !root.videoId ? I18n.tr("Chưa có bài trực tuyến", "No online track playing")
             : root.disabledComments ? I18n.tr("Bình luận đã tắt", "Comments are turned off")
             : I18n.tr("Chưa có bình luận", "No comments yet")
        description: root.errorText !== "" ? I18n.tr("Kiểm tra kết nối mạng rồi mở lại tab này", "Check your connection, then reopen this tab")
                   : !root.videoId ? I18n.tr("Bình luận chỉ có ở bài phát từ YouTube Music", "Comments are only available for YouTube Music tracks")
                   : root.disabledComments ? I18n.tr("Bài này không nhận bình luận", "This track does not accept comments")
                   : root.canPost ? I18n.tr("Hãy là người đầu tiên bình luận", "Be the first to comment")
                   : I18n.tr("Đăng nhập Google để bình luận", "Sign in with Google to comment")
    }

    // Composer, only when signed in
    Rectangle {
        id: composer
        visible: root.canPost && !root.disabledComments
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: root.bottomInset
        height: composerCol.implicitHeight + 16
        radius: 18
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, commentInput.activeFocus ? 0.55 : 0.25)
        Behavior on border.color { ColorAnimation { duration: 140 } }

        ColumnLayout {
            id: composerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                visible: root.replyCid !== "" || root.sendError !== ""
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.sendError !== "" ? root.sendError
                        : I18n.tr("Đang trả lời ", "Replying to ") + root.replyAuthor
                    color: root.sendError !== "" ? Qt.rgba(0.96, 0.45, 0.55, 1) : Qt.rgba(1, 1, 1, 0.65)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                AppIcon {
                    visible: root.replyCid !== ""
                    source: "../assets/icons/window-close-symbolic.svg"
                    iconSize: 10
                    color: "#ffffff"
                    opacity: cancelReplyMouse.containsMouse ? 1.0 : 0.6
                    MouseArea {
                        id: cancelReplyMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearReply()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextInput {
                    id: commentInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(20, Math.min(contentHeight, 72))
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    wrapMode: TextInput.Wrap
                    clip: true
                    selectByMouse: true
                    maximumLength: 10000
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: !root.sending
                    onAccepted: root.send()
                    Keys.onEscapePressed: root.clearReply()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: root.replyCid !== "" ? I18n.tr("Viết phản hồi...", "Write a reply...")
                                                   : I18n.tr("Viết bình luận...", "Add a comment...")
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font: commentInput.font
                        visible: !commentInput.text && !commentInput.inputMethodComposing
                    }
                }

                Item {
                    id: sendBtn
                    readonly property bool ready: (commentInput.text.trim() !== "" || commentInput.inputMethodComposing) && !root.sending
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    HoverHandler { id: sendH }
                    scale: sendMouse.pressed ? 0.92 : (sendH.hovered && ready ? 1.06 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: sendBtn.ready ? root.accentColor
                             : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    AppIcon {
                        anchors.centerIn: parent
                        visible: !root.sending
                        source: "../assets/icons/material/ms-send.svg"
                        iconSize: 15
                        color: sendBtn.ready ? "#101014" : "#ffffff"
                    }
                    CircularSpinner {
                        anchors.centerIn: parent
                        visible: root.sending
                        size: 16
                        color: "#ffffff"
                        running: visible
                    }
                    MouseArea {
                        id: sendMouse
                        anchors.fill: parent
                        cursorShape: sendBtn.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.send()
                    }
                }
            }
        }
    }
}
