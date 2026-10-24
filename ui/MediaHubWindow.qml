import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "."
import "components"

ApplicationWindow {
    id: mhWindow
    width: 1320
    height: 820
    minimumWidth: 460
    minimumHeight: 380
    visible: true
    title: "Find — Media Hub"
    flags: Qt.Window | Qt.FramelessWindowHint

    color: (backend && backend.transparentBlur) ? "transparent" : Theme.bgBase

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property bool isViewingEpisodeList: backend ? (backend.currentPath !== "mediahub://") : false
    property string activeToastText: ""
    property var currentShowSummary: ({})

    function refreshShowSummary() {
        if (backend && isViewingEpisodeList) {
            currentShowSummary = backend.getFolderMediaSummary(backend.currentPath)
        } else {
            currentShowSummary = ({})
        }
    }

    Component.onCompleted: {
        if (backend) {
            if (backend.currentPath !== "mediahub://") {
                backend.navigateTo("mediahub://")
            } else {
                backend.refreshMediaHub()
            }
        }
    }

    Connections {
        target: backend
        function onCurrentPathChanged() {
            mhWindow.refreshShowSummary()
        }
        function onMediaLibraryStateChanged() {
            if (mhWindow.isViewingEpisodeList) {
                mhWindow.refreshShowSummary()
            }
        }
        function onToastMessage(msg) {
            mhWindow.activeToastText = msg
            toastTimer.restart()
        }
    }

    Timer {
        id: toastTimer
        interval: 3000
        repeat: false
        onTriggered: mhWindow.activeToastText = ""
    }

    // Keyboard Shortcuts
    Shortcut {
        sequences: ["F", "F11"]
        context: Qt.WindowShortcut
        onActivated: {
            if (mhWindow.visibility === Window.FullScreen) {
                mhWindow.showNormal()
            } else {
                mhWindow.showFullScreen()
            }
        }
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (mhWindow.isViewingEpisodeList && backend) {
                backend.navigateTo("mediahub://")
            }
        }
    }
    Shortcut {
        sequence: "Backspace"
        context: Qt.WindowShortcut
        onActivated: {
            if (mhWindow.isViewingEpisodeList && backend) {
                backend.navigateTo("mediahub://")
            }
        }
    }
    Shortcut {
        sequences: ["F5", "Ctrl+R"]
        context: Qt.WindowShortcut
        onActivated: {
            if (backend) backend.syncJellyfinAndRefresh()
            mhWindow.refreshShowSummary()
        }
    }
    Shortcut {
        sequence: "C"
        context: Qt.WindowShortcut
        onActivated: if (backend && backend.isMediaLibraryView) backend.toggleSubtitlesInMedia()
    }
    Shortcut {
        sequence: "Shift+A"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.toggleAnonymousMode()
    }

    Rectangle {
        id: mhContainer
        anchors.fill: parent
        color: Theme.bgBase

        // Completely Transparent Floating Window Drag/Control Area (No solid header bar)
        Item {
            id: topWindowArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(52 * Theme.scaleFactor)
            z: 100

            DragHandler {
                target: null
                onActiveChanged: if (active) mhWindow.startSystemMove()
            }

            // Floating Back Arrow (Top-Left, visible only inside episode list)
            Rectangle {
                id: backArrowBtn
                visible: mhWindow.isViewingEpisodeList
                anchors.left: parent.left
                anchors.leftMargin: Math.round(18 * Theme.scaleFactor)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(36 * Theme.scaleFactor)
                height: Math.round(36 * Theme.scaleFactor)
                radius: width / 2
                color: backArrowMouse.containsMouse ? "#45181824" : "#2a12121c"
                border.color: backArrowMouse.containsMouse ? Theme.accent : "#35ffffff"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: backArrowMouse.containsMouse ? Theme.accent : Theme.textPrimary
                    font.pixelSize: Math.round(18 * Theme.scaleFactor)
                    font.bold: true
                }

                MouseArea {
                    id: backArrowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (backend) backend.navigateTo("mediahub://")
                }
            }

            // Floating Controls: Maximize & Close (Top-Right)
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: Math.round(18 * Theme.scaleFactor)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(8 * Theme.scaleFactor)

                // Maximize / Restore Button
                Rectangle {
                    width: Math.round(34 * Theme.scaleFactor)
                    height: Math.round(34 * Theme.scaleFactor)
                    radius: width / 2
                    color: maxMouse.containsMouse ? "#45181824" : "#2a12121c"
                    border.color: maxMouse.containsMouse ? Theme.accent : "#35ffffff"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: (mhWindow.visibility === Window.FullScreen || mhWindow.visibility === Window.Maximized) ? "❐" : "🗖"
                        color: maxMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                        font.pixelSize: Math.round(12 * Theme.scaleFactor)
                        font.bold: true
                    }

                    MouseArea {
                        id: maxMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (mhWindow.visibility === Window.FullScreen || mhWindow.visibility === Window.Maximized) {
                                mhWindow.showNormal()
                            } else {
                                mhWindow.showMaximized()
                            }
                        }
                    }
                }

                // Close Button
                Rectangle {
                    width: Math.round(34 * Theme.scaleFactor)
                    height: Math.round(34 * Theme.scaleFactor)
                    radius: width / 2
                    color: closeMouse.containsMouse ? "#dc2626" : "#2a12121c"
                    border.color: closeMouse.containsMouse ? "#ef4444" : "#35ffffff"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeMouse.containsMouse ? "#ffffff" : Theme.textSecondary
                        font.pixelSize: Math.round(12 * Theme.scaleFactor)
                        font.bold: true
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mhWindow.close()
                    }
                }
            }
        }

        // Main Viewport Container
        Item {
            anchors.fill: parent
            anchors.topMargin: Math.round(10 * Theme.scaleFactor)

            // =========================================================
            // 1. HUB CARDS VIEW (mediahub://)
            // =========================================================
            Flickable {
                id: hubFlick
                anchors.fill: parent
                visible: !mhWindow.isViewingEpisodeList
                contentWidth: width
                contentHeight: hubCol.implicitHeight + Math.round(50 * Theme.scaleFactor)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: hubCol
                    width: hubFlick.width - Math.round(36 * Theme.scaleFactor)
                    x: Math.round(18 * Theme.scaleFactor)
                    spacing: Math.round(30 * Theme.scaleFactor)

                    Repeater {
                        model: backend ? backend.mediaHubModel : null
                        delegate: ColumnLayout {
                            id: secRowLayout
                            Layout.fillWidth: true
                            spacing: Math.round(12 * Theme.scaleFactor)

                            required property string section_id
                            required property string title
                            required property string subtitle
                            required property int item_count
                            required property var cards_model

                            readonly property bool isWideCardRow: secRowLayout.section_id === "continue_watching" || secRowLayout.section_id === "next_up"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: secRowLayout.title
                                    color: Theme.textPrimary
                                    font.pixelSize: Math.round(20 * Theme.scaleFactor)
                                    font.bold: true
                                }

                                Rectangle {
                                    implicitWidth: countText.implicitWidth + 12
                                    implicitHeight: Math.round(20 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgCard
                                    border.color: Theme.borderDim
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: String(secRowLayout.item_count)
                                        color: Theme.textSecondary
                                        font.pixelSize: Math.round(10 * Theme.scaleFactor)
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: secRowLayout.subtitle || ""
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }

                            ListView {
                                id: cardsHView
                                Layout.fillWidth: true
                                height: Math.round((secRowLayout.isWideCardRow ? 186 : 252) * Theme.scaleFactor)
                                orientation: ListView.Horizontal
                                spacing: Math.round(18 * Theme.scaleFactor)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: secRowLayout.cards_model

                                delegate: Item {
                                    id: cardItemContainer
                                    readonly property bool isWideCard: secRowLayout.isWideCardRow
                                    readonly property int cardW: Math.round((isWideCard ? 240 : 156) * Theme.scaleFactor)
                                    readonly property int cardH: Math.round((isWideCard ? 184 : 250) * Theme.scaleFactor)
                                    width: cardW
                                    height: cardH

                                    Component.onCompleted: {
                                        if (!backend || !model.path || model.is_airing_card) return
                                        if (model.is_dir) {
                                            backend.requestFolderPreview(model.path)
                                        } else if (!model.thumb || model.thumb === "") {
                                            backend.requestItemThumbnail(model.path)
                                        }
                                    }

                                    Rectangle {
                                        id: cardDelegate
                                        anchors.fill: parent
                                        radius: Theme.radiusLarge
                                        color: cardArea.containsMouse ? "#18ffffff" : "transparent"
                                        border.color: cardArea.containsMouse ? Theme.accent : "transparent"
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 6

                                            // Media Thumbnail Box
                                            Rectangle {
                                                id: mediaArtBox
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: Math.round(10 * Theme.scaleFactor)
                                                color: "#14141c"
                                                border.color: cardArea.containsMouse ? "#66ffffff" : "#22ffffff"
                                                border.width: 1
                                                clip: true

                                                Rectangle {
                                                    id: cardArtMask
                                                    anchors.fill: parent
                                                    radius: mediaArtBox.radius
                                                    visible: false
                                                    layer.enabled: true
                                                    layer.smooth: true
                                                }

                                                Image {
                                                    id: cardArt
                                                    anchors.fill: parent
                                                    visible: model.art_source !== ""
                                                    source: model.art_source
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    smooth: true
                                                    mipmap: true
                                                    layer.enabled: visible
                                                    layer.smooth: true
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: cardArtMask
                                                    }
                                                }

                                                // Find Watched Overlay: Dimmed glass + centered elegant WATCHED frame
                                                Rectangle {
                                                    visible: model.is_watched === true || (model.progress !== undefined && model.progress >= 0.90)
                                                    anchors.fill: parent
                                                    color: "#aa09090d"
                                                    radius: parent.radius
                                                    z: 15

                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        implicitWidth: watchedLabelText.implicitWidth + Math.round(18 * Theme.scaleFactor)
                                                        implicitHeight: Math.round(26 * Theme.scaleFactor)
                                                        radius: Math.round(5 * Theme.scaleFactor)
                                                        color: "#50000000"
                                                        border.color: "#ddffffff"
                                                        border.width: 1.2

                                                        Text {
                                                            id: watchedLabelText
                                                            anchors.centerIn: parent
                                                            text: "WATCHED"
                                                            color: "#ffffff"
                                                            font.pixelSize: Math.round(10 * Theme.scaleFactor)
                                                            font.bold: true
                                                            font.letterSpacing: 2.0
                                                        }
                                                    }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: model.art_source === ""
                                                    text: model.is_dir ? "📺" : "🎬"
                                                    font.pixelSize: Math.round(36 * Theme.scaleFactor)
                                                }

                                                // Top Badge
                                                Rectangle {
                                                    visible: model.badge !== undefined && model.badge !== ""
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.margins: 6
                                                    implicitWidth: Math.min(parent.width - 12, bTxt.implicitWidth + 12)
                                                    implicitHeight: Math.round(20 * Theme.scaleFactor)
                                                    radius: height / 2
                                                    color: "#ea0f172a"
                                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                                                    border.width: 1

                                                    Text {
                                                        id: bTxt
                                                        anchors.centerIn: parent
                                                        text: model.badge || ""
                                                        color: Theme.accent
                                                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                        font.bold: true
                                                    }
                                                }

                                                // Bottom Progress Bar
                                                Rectangle {
                                                    visible: model.progress !== undefined && model.progress > 0.005
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 6
                                                    height: Math.round(5 * Theme.scaleFactor)
                                                    radius: height / 2
                                                    color: "#88000000"
                                                    clip: true

                                                    Rectangle {
                                                        width: parent.width * Math.min(1.0, Math.max(0.0, model.progress || 0.0))
                                                        height: parent.height
                                                        radius: parent.radius
                                                        color: model.is_watched ? "#10b981" : Theme.accent
                                                    }
                                                }
                                            }

                                            // Text Info Container (Exactly matches thumbnail width)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: model.display_title || model.name
                                                    color: Theme.textPrimary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.bold: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: model.subtitle || ""
                                                    color: model.is_airing_card ? (model.is_going_tight ? "#34d399" : "#fbbf24") : Theme.textTertiary
                                                    font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                    font.bold: Boolean(model.is_airing_card)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: cardArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    mhContext.targetPath = model.path || ""
                                                    mhContext.targetName = model.name || ""
                                                    mhContext.isDir = Boolean(model.is_dir)
                                                    mhContext.isAiringItem = Boolean(model.is_airing_card)
                                                    mhContext.airingId = model.airing_id || ""
                                                    mhContext.airingLinkedPath = model.linked_path || ""
                                                    mhContext.popupSafe(cardDelegate, mouse.x, mouse.y)
                                                } else {
                                                    if (model.is_dir) {
                                                        backend.setViewMode("details")
                                                        backend.navigateTo(model.path)
                                                    } else {
                                                        backend.openEntry(model.path)
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

            // =========================================================
            // 2. SHOW DETAILS & EPISODES LIST VIEW
            // =========================================================
            ColumnLayout {
                anchors.fill: parent
                visible: mhWindow.isViewingEpisodeList
                spacing: 0

                // RICH HEADER BANNER AT THE TOP OF SHOW (Seamless Glass Background)
                Rectangle {
                    id: showHeaderBanner
                    Layout.fillWidth: true
                    height: Math.round(160 * Theme.scaleFactor)
                    color: "#20181824"
                    clip: true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#22ffffff"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Math.round(18 * Theme.scaleFactor)
                        spacing: Math.round(20 * Theme.scaleFactor)

                        // Vertical Poster Box
                        Rectangle {
                            id: headerPosterBox
                            Layout.preferredWidth: Math.round(88 * Theme.scaleFactor)
                            Layout.preferredHeight: Math.round(126 * Theme.scaleFactor)
                            radius: Math.round(8 * Theme.scaleFactor)
                            color: "#181820"
                            border.color: Theme.borderDim
                            border.width: 1
                            clip: true

                            readonly property bool hasPoster: mhWindow.currentShowSummary && mhWindow.currentShowSummary.poster !== undefined && mhWindow.currentShowSummary.poster !== ""

                            Image {
                                id: headerPosterImg
                                anchors.fill: parent
                                visible: headerPosterBox.hasPoster
                                source: visible ? ("file://" + mhWindow.currentShowSummary.poster) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !headerPosterBox.hasPoster
                                text: "📺"
                                font.pixelSize: Math.round(34 * Theme.scaleFactor)
                            }
                        }

                        // Metadata & Synopsis
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                text: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.title) ? mhWindow.currentShowSummary.title : ((backend && backend.breadcrumbs && backend.breadcrumbs.length > 0) ? backend.breadcrumbs[backend.breadcrumbs.length - 1].name : "Show")
                                color: Theme.textPrimary
                                font.pixelSize: Math.round(21 * Theme.scaleFactor)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            // Meta Stats Badges Row
                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Episodes: " + ((mhWindow.currentShowSummary && mhWindow.currentShowSummary.episode_count !== undefined) ? mhWindow.currentShowSummary.episode_count : "0")
                                    color: Theme.accent
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                                Text { text: "•"; color: Theme.textTertiary; font.bold: true }
                                Text {
                                    text: "Total Time: " + ((mhWindow.currentShowSummary && mhWindow.currentShowSummary.total_duration) ? mhWindow.currentShowSummary.total_duration : "-")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                                Text { text: "•"; color: Theme.textTertiary; font.bold: true }
                                Text {
                                    text: "Total Size: " + ((mhWindow.currentShowSummary && mhWindow.currentShowSummary.total_size) ? mhWindow.currentShowSummary.total_size : "0 B")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                                Text {
                                    visible: Boolean(mhWindow.currentShowSummary && mhWindow.currentShowSummary.rating)
                                    text: "•"
                                    color: Theme.textTertiary
                                    font.bold: true
                                }
                                Text {
                                    visible: Boolean(mhWindow.currentShowSummary && mhWindow.currentShowSummary.rating)
                                    text: "⭐ " + ((mhWindow.currentShowSummary && mhWindow.currentShowSummary.rating) ? mhWindow.currentShowSummary.rating : "")
                                    color: "#fbbf24"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.overview) ? mhWindow.currentShowSummary.overview : "Local series folder with automatic episode tracking and audio/subtitle matching."
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                            }
                        }

                        // Actions & Soft Pill-Shaped Resume Button
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 8

                            // Perfectly Rounded Pill Resume Button with Clean Progress Track Fill
                            Rectangle {
                                id: mainResumeBtn
                                Layout.preferredWidth: Math.round(180 * Theme.scaleFactor)
                                Layout.preferredHeight: Math.round(38 * Theme.scaleFactor)
                                radius: height / 2
                                color: "#32323e"
                                border.color: "#ffffff"
                                border.width: 1
                                clip: true

                                readonly property var resData: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.resume) ? mhWindow.currentShowSummary.resume : ({})
                                readonly property bool hasResumeProgress: resData.is_resumable === true
                                readonly property real fillRatio: Math.min(1.0, Math.max(0.0, resData.ratio || 0.0))

                                // Incomplete Progress Track (Clean Dark Slate)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "#333342"
                                }

                                // Active Watched Progress Portion
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: mainResumeBtn.hasResumeProgress ? (parent.width * mainResumeBtn.fillRatio) : parent.width
                                    radius: parent.radius
                                    color: resumeBtnMouse.containsMouse ? Theme.accentHover : Theme.accent
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    z: 10

                                    Text {
                                        text: "▶"
                                        color: "#ffffff"
                                        font.pixelSize: Math.round(12 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    Text {
                                        text: {
                                            var d = mainResumeBtn.resData
                                            if (mainResumeBtn.hasResumeProgress) {
                                                return "Resume EP " + (d.ep_num || "1") + (d.time_str ? " (" + d.time_str + ")" : "")
                                            }
                                            return "Play Show"
                                        }
                                        color: "#ffffff"
                                        font.pixelSize: Theme.fontSizeNormal
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: resumeBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) backend.resumeMediaFolder(backend.currentPath)
                                    }
                                }
                            }

                            // Open in Find Button
                            Rectangle {
                                Layout.preferredWidth: Math.round(180 * Theme.scaleFactor)
                                Layout.preferredHeight: Math.round(32 * Theme.scaleFactor)
                                radius: height / 2
                                color: openFindMouse.containsMouse ? "#45222230" : "#221c1c28"
                                border.color: Theme.borderDim
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: "📂"; font.pixelSize: Theme.fontSizeSmall }
                                    Text {
                                        text: "Open in Find"
                                        color: Theme.textPrimary
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                MouseArea {
                                    id: openFindMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) backend.openInFindInstance(backend.currentPath)
                                    }
                                }
                            }
                        }
                    }
                }

                // EPISODES LIST (Translucent Glass cards, pure 'ar' tag when Arabic subtitle metadata is present)
                ListView {
                    id: episodesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Math.round(16 * Theme.scaleFactor)
                    clip: true
                    spacing: 8
                    model: visible && backend ? backend.files : null

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: epRowBox
                        width: episodesList.width
                        height: Math.round(80 * Theme.scaleFactor)
                        radius: Theme.radiusLarge
                        color: epMouse.containsMouse ? "#30262635" : "#1e1a1a24"
                        border.color: epMouse.containsMouse ? Theme.accent : "#22ffffff"
                        border.width: 1

                        readonly property var epDetail: (backend && model.path) ? backend.getEpisodeDetailedInfo(model.path) : ({})

                        Component.onCompleted: {
                            if (!backend || !model.path) return
                            if (model.is_dir) {
                                backend.requestFolderPreview(model.path)
                            } else if (!model.thumb || model.thumb === "") {
                                backend.requestItemThumbnail(model.path)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 14

                            // Episode Thumbnail with smooth Rounded Corners Mask
                            Rectangle {
                                id: epThumbContainer
                                Layout.preferredWidth: Math.round(116 * Theme.scaleFactor)
                                Layout.preferredHeight: Math.round(66 * Theme.scaleFactor)
                                radius: Math.round(12 * Theme.scaleFactor)
                                color: "#16161c"
                                border.color: "#30ffffff"
                                border.width: 1
                                clip: true

                                Rectangle {
                                    id: epThumbMask
                                    anchors.fill: parent
                                    radius: epThumbContainer.radius
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                }

                                Image {
                                    id: epImg
                                    anchors.fill: parent
                                    visible: model.thumb !== undefined && model.thumb !== ""
                                    source: visible ? ("file://" + model.thumb) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    layer.enabled: visible
                                    layer.smooth: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: epThumbMask
                                    }
                                }

                                // Watched Dim Overlay on Episode Thumbnail
                                Rectangle {
                                    visible: model.is_watched === true || (model.progress !== undefined && model.progress >= 0.90)
                                    anchors.fill: parent
                                    radius: epThumbContainer.radius
                                    color: "#66000000"
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !epImg.visible
                                    text: model.is_dir ? "📁" : "🎬"
                                    font.pixelSize: Theme.fontSizeLarge
                                }
                            }

                            // Episode Number Pill
                            Rectangle {
                                visible: model.episode_num !== undefined && model.episode_num !== ""
                                Layout.preferredWidth: Math.max(Math.round(36 * Theme.scaleFactor), epBadgeText.implicitWidth + 12)
                                Layout.preferredHeight: Math.round(24 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: model.is_watched ? "#2210b981" : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                border.color: model.is_watched ? "#10b981" : Theme.accent
                                border.width: 1

                                Text {
                                    id: epBadgeText
                                    anchors.centerIn: parent
                                    text: model.episode_num || ""
                                    color: model.is_watched ? "#34d399" : Theme.accent
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeNormal
                                }
                            }

                            // Title & Metadata (Duration, Size, Pure 'ar' Tag)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: (model.episode_title && model.episode_title !== "") ? model.episode_title : (model.name || "")
                                        color: model.is_watched ? Theme.textSecondary : Theme.textPrimary
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeNormal
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        visible: Boolean(epRowBox.epDetail && epRowBox.epDetail.duration_str)
                                        text: "⏱ " + ((epRowBox.epDetail && epRowBox.epDetail.duration_str) ? epRowBox.epDetail.duration_str : "")
                                        color: Theme.textSecondary
                                        font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    Text {
                                        visible: Boolean(epRowBox.epDetail && epRowBox.epDetail.duration_str)
                                        text: "•"
                                        color: Theme.textTertiary
                                    }

                                    Text {
                                        text: "💾 " + ((epRowBox.epDetail && epRowBox.epDetail.size_str) ? epRowBox.epDetail.size_str : (model.size || ""))
                                        color: Theme.textSecondary
                                        font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    // Display 'ar' Tag ONLY when Arabic subtitles are verified in metadata
                                    Rectangle {
                                        visible: epRowBox.epDetail && epRowBox.epDetail.has_arabic_sub === true
                                        implicitWidth: arBadgeTxt.implicitWidth + 8
                                        implicitHeight: Math.round(18 * Theme.scaleFactor)
                                        radius: Theme.radiusSmall
                                        color: "#2810b981"
                                        border.color: "#10b981"
                                        border.width: 1

                                        Text {
                                            id: arBadgeTxt
                                            anchors.centerIn: parent
                                            text: "ar"
                                            color: "#34d399"
                                            font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                            font.bold: true
                                        }
                                    }
                                }

                                // Rounded Episode Progress Bar
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(4 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: "#22ffffff"
                                    clip: true
                                    visible: (model.progress !== undefined && model.progress > 0.005) || model.is_watched === true

                                    Rectangle {
                                        width: parent.width * Math.min(1.0, Math.max(0.0, model.progress || 0.0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: model.is_watched ? "#10b981" : Theme.accent
                                    }
                                }
                            }

                            // Watched Checkmark Badge
                            Rectangle {
                                visible: model.is_watched === true
                                Layout.preferredWidth: Math.round(22 * Theme.scaleFactor)
                                Layout.preferredHeight: Math.round(22 * Theme.scaleFactor)
                                radius: Layout.preferredWidth / 2
                                color: "#10b981"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: Math.round(11 * Theme.scaleFactor)
                                }
                            }
                        }

                        MouseArea {
                            id: epMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    mhContext.targetPath = model.path || ""
                                    mhContext.targetName = model.name || ""
                                    mhContext.isDir = Boolean(model.is_dir)
                                    mhContext.isAiringItem = false
                                    mhContext.popupSafe(epRowBox, mouse.x, mouse.y)
                                } else {
                                    backend.openEntry(model.path)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Floating Toast Banner
        Rectangle {
            visible: mhWindow.activeToastText !== ""
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(24 * Theme.scaleFactor)
            anchors.horizontalCenter: parent.horizontalCenter
            z: 999
            implicitWidth: toastMsg.implicitWidth + 26
            implicitHeight: Math.round(36 * Theme.scaleFactor)
            radius: Theme.radiusLarge
            color: "#f018181f"
            border.color: Theme.accent
            border.width: 1

            Text {
                id: toastMsg
                anchors.centerIn: parent
                text: mhWindow.activeToastText
                color: Theme.textPrimary
                font.bold: true
                font.pixelSize: Theme.fontSizeNormal
            }
        }
    }

    MediaHubContextMenu {
        id: mhContext
    }
}
