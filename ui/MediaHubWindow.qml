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

    color: Theme.mhBgBase

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property string activeBackdropSource: {
        if (isViewingMoviePage && currentMovieSummary) {
            if (currentMovieSummary.backdrop && currentMovieSummary.backdrop !== "") {
                return "file://" + currentMovieSummary.backdrop
            }
            if (currentMovieSummary.poster && currentMovieSummary.poster !== "") {
                return "file://" + currentMovieSummary.poster
            }
        }
        if (isViewingEpisodeList && currentShowSummary) {
            if (currentShowSummary.backdrop && currentShowSummary.backdrop !== "") {
                return "file://" + currentShowSummary.backdrop
            }
            if (currentShowSummary.poster && currentShowSummary.poster !== "") {
                return "file://" + currentShowSummary.poster
            }
        }
        return ""
    }

    readonly property bool isViewingEpisodeList: backend ? (backend.currentPath !== "mediahub://") : false
    readonly property bool isMovieLibraryFolder: backend ? (isViewingEpisodeList && backend.isMovieFolderView) : false
    property string activeMovieWorkPath: ""
    property var currentMovieSummary: ({})
    readonly property bool isViewingMoviePage: activeMovieWorkPath !== ""
    property string activeToastText: ""
    property var currentShowSummary: ({})

    function openMoviePage(moviePath) {
        if (!backend || !moviePath) return
        activeMovieWorkPath = moviePath
        currentMovieSummary = backend.getMovieWorkSummary(moviePath)
    }

    function closeMoviePage() {
        activeMovieWorkPath = ""
        currentMovieSummary = ({})
    }

    function refreshShowSummary() {
        if (backend && isViewingMoviePage) {
            currentMovieSummary = backend.getMovieWorkSummary(activeMovieWorkPath)
        }
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
            mhWindow.closeMoviePage()
            mhWindow.refreshShowSummary()
        }
        function onMediaLibraryStateChanged() {
            if (mhWindow.isViewingEpisodeList || mhWindow.isViewingMoviePage) {
                mhWindow.refreshShowSummary()
            }
        }
        function onSelectedItemChanged() {
            if (mhWindow.isViewingMoviePage && backend) {
                mhWindow.currentMovieSummary = backend.getMovieWorkSummary(mhWindow.activeMovieWorkPath)
            }
        }
        function onFolderMediaSummaryChanged(folderPath, summaryData) {
            if (mhWindow.isViewingEpisodeList && backend && folderPath === backend.currentPath) {
                mhWindow.currentShowSummary = summaryData
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
            if (mhWindow.isViewingMoviePage) {
                mhWindow.closeMoviePage()
            } else if (mhWindow.isViewingEpisodeList && backend) {
                backend.navigateTo("mediahub://")
            }
        }
    }
    Shortcut {
        sequence: "Backspace"
        context: Qt.WindowShortcut
        onActivated: {
            if (mhWindow.isViewingMoviePage) {
                mhWindow.closeMoviePage()
            } else if (mhWindow.isViewingEpisodeList && backend) {
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

    SettingsDialog {
        id: mhSettingsDialog
        mediaOnlyMode: true
    }

    Rectangle {
        id: mhContainer
        anchors.fill: parent
        color: Theme.mhBgBase

        // Ambient Cinematic Backdrop Layer (Blur + Dark Vignette)
        Item {
            id: backdropContainer
            anchors.fill: parent
            z: 0
            visible: mhWindow.activeBackdropSource !== ""

            Image {
                id: backdropImage
                anchors.fill: parent
                source: mhWindow.activeBackdropSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                opacity: status === Image.Ready ? 0.85 : 0.0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                visible: true
                mipmap: false
            }

            MultiEffect {
                anchors.fill: backdropImage
                source: backdropImage
                blurEnabled: true
                blur: 0.00
                blurMax: 24
                saturation: 0.90
                brightness: -0.05
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#880b0d13" }
                    GradientStop { position: 0.6; color: "#440b0d13" }
                    GradientStop { position: 1.0; color: Theme.mhBgBase }
                }
            }
        }

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

            // Floating Back Arrow (Top-Left, visible inside Movie Page or Episode List)
            Rectangle {
                id: backArrowBtn
                visible: mhWindow.isViewingMoviePage || mhWindow.isViewingEpisodeList
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
                    text: "←"
                    color: backArrowMouse.containsMouse ? Theme.accent : Theme.textPrimary
                    font.pixelSize: Math.round(18 * Theme.scaleFactor)
                    font.bold: true
                }

                MouseArea {
                    id: backArrowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (mhWindow.isViewingMoviePage) {
                            mhWindow.closeMoviePage()
                        } else if (backend) {
                            backend.navigateTo("mediahub://")
                        }
                    }
                }
            }

            // Floating Controls: Maximize & Close (Top-Right)
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: Math.round(18 * Theme.scaleFactor)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(8 * Theme.scaleFactor)

                // Media Settings Tab Button
                Rectangle {
                    height: Math.round(34 * Theme.scaleFactor)
                    implicitWidth: mhSetRow.implicitWidth + Math.round(20 * Theme.scaleFactor)
                    radius: height / 2
                    color: mhSetMouse.containsMouse ? Qt.rgba(Theme.mhAccent.r, Theme.mhAccent.g, Theme.mhAccent.b, 0.28) : "#2a12121c"
                    border.color: mhSetMouse.containsMouse ? Theme.mhAccent : "#35ffffff"
                    border.width: 1

                    RowLayout {
                        id: mhSetRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "⚙️"
                            font.pixelSize: Math.round(12 * Theme.scaleFactor)
                        }
                        Text {
                            text: "Media Settings"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: mhSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mhSettingsDialog.openMediaSettings()
                    }
                }

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
                visible: !mhWindow.isViewingEpisodeList && !mhWindow.isViewingMoviePage
                contentWidth: width
                contentHeight: hubCol.implicitHeight + Math.round(50 * Theme.scaleFactor)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                SmoothScroll { target: hubFlick; orientation: Qt.Vertical }

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
                            required property bool has_movie_poster

                            readonly property bool isWideCardRow: secRowLayout.section_id === "continue_watching" || secRowLayout.section_id === "next_up"
                            readonly property bool expandRowForMoviePoster: secRowLayout.section_id === "continue_watching" && secRowLayout.has_movie_poster

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
                                height: Math.round(((secRowLayout.isWideCardRow && !secRowLayout.expandRowForMoviePoster) ? 186 : 252) * Theme.scaleFactor)
                                orientation: ListView.Horizontal
                                spacing: Math.round(18 * Theme.scaleFactor)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: secRowLayout.cards_model
                                SmoothScroll { target: cardsHView; orientation: Qt.Horizontal }

                                delegate: Item {
                                    id: cardItemContainer
                                    readonly property bool isMovieCardInWideRow: secRowLayout.section_id === "continue_watching" && Boolean(model.is_movie_item)
                                    readonly property bool isWideCard: secRowLayout.isWideCardRow && !isMovieCardInWideRow
                                    readonly property int cardW: Math.round((isWideCard ? 240 : 156) * Theme.scaleFactor)
                                    readonly property int cardH: Math.round((isWideCard ? 184 : 250) * Theme.scaleFactor)
                                    width: cardW
                                    height: cardH
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

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
                                        color: (cardArea.containsMouse || showLinkArea.containsMouse) ? "#18ffffff" : "transparent"
                                        border.color: (cardArea.containsMouse || showLinkArea.containsMouse) ? Theme.accent : "transparent"
                                        border.width: 1

                                        MouseArea {
                                            id: cardArea
                                            anchors.fill: parent
                                            z: 0
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    mhContext.targetPath = model.path || ""
                                                    mhContext.targetName = model.name || ""
                                                    mhContext.showPath = model.show_path || ""
                                                    mhContext.isDir = Boolean(model.is_dir)
                                                    mhContext.isAiringItem = Boolean(model.is_airing_card)
                                                    mhContext.airingId = model.airing_id || ""
                                                    mhContext.airingLinkedPath = model.linked_path || ""
                                                    mhContext.popupSafe(cardDelegate, mouse.x, mouse.y)
                                                } else {
                                                    if (model.is_dir) {
                                                        backend.setViewMode("details")
                                                        backend.navigateTo(model.path)
                                                    } else if (model.is_movie_item && !model.is_airing_card) {
                                                        mhWindow.openMoviePage(model.path)
                                                    } else {
                                                        backend.openEntry(model.path)
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 6
                                            z: 10

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
                                                    mipmap: false
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

                                                // Top-Left Badge
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

                                                // Top-Right NEW & HDR Badges Row
                                                RowLayout {
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 6
                                                    spacing: 4
                                                    z: 12

                                                    Rectangle {
                                                        visible: model.is_new === true && !model.is_watched && !model.is_airing_card
                                                        implicitWidth: cardNewTxt.implicitWidth + 8
                                                        implicitHeight: Math.round(16 * Theme.scaleFactor)
                                                        radius: Theme.radiusSmall
                                                        color: "#d9451a03"
                                                        border.color: "#f59e0b"
                                                        border.width: 1

                                                        Text {
                                                            id: cardNewTxt
                                                            anchors.centerIn: parent
                                                            text: "NEW"
                                                            color: "#fbbf24"
                                                            font.pixelSize: Math.round(7.5 * Theme.scaleFactor)
                                                            font.bold: true
                                                        }
                                                    }

                                                    Rectangle {
                                                        visible: model.is_hdr === true
                                                        implicitWidth: cardHdrTxt.implicitWidth + 8
                                                        implicitHeight: Math.round(16 * Theme.scaleFactor)
                                                        radius: Math.round(3 * Theme.scaleFactor)
                                                        color: "#d91e293b"
                                                        border.color: "#e2e8f0"
                                                        border.width: 1

                                                        Text {
                                                            id: cardHdrTxt
                                                            anchors.centerIn: parent
                                                            text: "HDR"
                                                            color: "#f8fafc"
                                                            font.pixelSize: Math.round(7.5 * Theme.scaleFactor)
                                                            font.bold: true
                                                        }
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

                                            // Text Info Container (Headline = Episode Name, Subtitle = Clickable Show Link)
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

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: showLinkText.implicitHeight + Math.round(4 * Theme.scaleFactor)
                                                    radius: Theme.radiusSmall
                                                    readonly property bool hasShowLink: !model.is_airing_card && model.show_path !== undefined && model.show_path !== ""
                                                    color: (showLinkArea.containsMouse && hasShowLink) ? "#280078d4" : "transparent"

                                                    Text {
                                                        id: showLinkText
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: model.subtitle || ""
                                                        color: model.is_airing_card
                                                               ? (model.is_going_tight ? "#34d399" : "#fbbf24")
                                                               : (showLinkArea.containsMouse && parent.hasShowLink ? Theme.accent : Theme.textSecondary)
                                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                                        font.bold: Boolean(model.is_airing_card) || parent.hasShowLink
                                                        font.underline: showLinkArea.containsMouse && parent.hasShowLink
                                                        horizontalAlignment: Text.AlignHCenter
                                                        elide: Text.ElideMiddle
                                                    }

                                                    MouseArea {
                                                        id: showLinkArea
                                                        anchors.fill: parent
                                                        enabled: parent.hasShowLink
                                                        hoverEnabled: parent.hasShowLink
                                                        acceptedButtons: Qt.LeftButton
                                                        cursorShape: parent.hasShowLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: function(mouse) {
                                                            mouse.accepted = true
                                                            if (backend && model.show_path) {
                                                                if (model.is_movie_item && !model.is_dir && !model.is_airing_card) {
                                                                    mhWindow.openMoviePage(model.path)
                                                                } else {
                                                                    backend.setViewMode("details")
                                                                    backend.navigateTo(model.show_path)
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
                    }
                }
            }

            // =========================================================
            // 1B. DEDICATED CINEMATIC MOVIE WORK PAGE
            // =========================================================
            Flickable {
                id: moviePageFlick
                anchors.fill: parent
                visible: mhWindow.isViewingMoviePage
                contentWidth: width
                contentHeight: Math.max(height, movieHeroLayout.implicitHeight + Math.round(64 * Theme.scaleFactor))
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Rectangle {
                    id: moviePageCard
                    width: Math.min(Math.round(1080 * Theme.scaleFactor), parent.width - Math.round(44 * Theme.scaleFactor))
                    implicitHeight: movieHeroLayout.implicitHeight + Math.round(48 * Theme.scaleFactor)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(Math.round(52 * Theme.scaleFactor), (parent.height - implicitHeight) / 2)
                    radius: Math.round(16 * Theme.scaleFactor)
                    color: "#24161822"
                    border.color: "#33ffffff"
                    border.width: 1

                    RowLayout {
                        id: movieHeroLayout
                        anchors.fill: parent
                        anchors.margins: Math.round(24 * Theme.scaleFactor)
                        spacing: Math.round(28 * Theme.scaleFactor)

                        // Large Vertical Movie Poster
                        Rectangle {
                            id: movieHeroPosterBox
                            Layout.preferredWidth: Math.round((mhWindow.width < 680 ? 150 : 230) * Theme.scaleFactor)
                            Layout.preferredHeight: Math.round((mhWindow.width < 680 ? 220 : 335) * Theme.scaleFactor)
                            Layout.alignment: Qt.AlignTop
                            radius: Math.round(12 * Theme.scaleFactor)
                            color: "#12131a"
                            border.color: "#40ffffff"
                            border.width: 1
                            clip: true

                            readonly property string posterSrc: {
                                if (!mhWindow.currentMovieSummary) return ""
                                if (mhWindow.currentMovieSummary.poster && mhWindow.currentMovieSummary.poster !== "") {
                                    return "file://" + mhWindow.currentMovieSummary.poster
                                }
                                if (mhWindow.currentMovieSummary.thumb && mhWindow.currentMovieSummary.thumb !== "") {
                                    return "file://" + mhWindow.currentMovieSummary.thumb
                                }
                                return ""
                            }

                            Image {
                                anchors.fill: parent
                                visible: parent.posterSrc !== ""
                                source: parent.posterSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                mipmap: false
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: parent.posterSrc === ""
                                text: "🎬"
                                font.pixelSize: Math.round(54 * Theme.scaleFactor)
                            }
                        }

                        // Movie Details, Badges, Synopsis & Play Actions
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Math.round(12 * Theme.scaleFactor)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    implicitWidth: movBadgeTxt.implicitWidth + 12
                                    implicitHeight: Math.round(22 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: Qt.rgba(Theme.mhAccent.r, Theme.mhAccent.g, Theme.mhAccent.b, 0.25)
                                    border.color: Theme.mhAccent
                                    Text {
                                        id: movBadgeTxt
                                        anchors.centerIn: parent
                                        text: "FEATURE FILM"
                                        color: "#ffffff"
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: true
                                        font.letterSpacing: 1.2
                                    }
                                }

                                Rectangle {
                                    visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.is_hdr)
                                    implicitWidth: movHdrTxt.implicitWidth + 12
                                    implicitHeight: Math.round(22 * Theme.scaleFactor)
                                    radius: Math.round(4 * Theme.scaleFactor)
                                    color: "#33fbbf24"
                                    border.color: "#fbbf24"
                                    Text {
                                        id: movHdrTxt
                                        anchors.centerIn: parent
                                        text: "HDR10 / Dolby Vision"
                                        color: "#fde68a"
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.watched)
                                    implicitWidth: movWatchedTxt.implicitWidth + 12
                                    implicitHeight: Math.round(22 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: "#2810b981"
                                    border.color: "#10b981"
                                    Text {
                                        id: movWatchedTxt
                                        anchors.centerIn: parent
                                        text: "✓ WATCHED"
                                        color: "#34d399"
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: true
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.title) ? mhWindow.currentMovieSummary.title : "Movie"
                                color: Theme.textPrimary
                                font.pixelSize: Math.round(26 * Theme.scaleFactor)
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.year)
                                    text: "📅 " + (mhWindow.currentMovieSummary.year || "")
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }
                                Text {
                                    visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.rating)
                                    text: "⭐ " + (mhWindow.currentMovieSummary.rating || "")
                                    color: "#fbbf24"
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }
                                Text {
                                    text: "⏱ " + ((mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.duration_str) ? mhWindow.currentMovieSummary.duration_str : "Movie")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }
                                Text {
                                    text: "💾 " + ((mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.size) ? mhWindow.currentMovieSummary.size : "-")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }
                                Text {
                                    visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.resolution && mhWindow.currentMovieSummary.resolution !== "N/A")
                                    text: "🖥 " + (mhWindow.currentMovieSummary.resolution || "") + (mhWindow.currentMovieSummary.codec ? (" • " + mhWindow.currentMovieSummary.codec) : "")
                                    color: Theme.mhAccent
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }
                            }

                            // Progress bar if movie is partially watched
                            ColumnLayout {
                                visible: Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.progress > 0.005)
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(6 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: "#33ffffff"
                                    clip: true

                                    Rectangle {
                                        width: parent.width * Math.min(1.0, Math.max(0.0, (mhWindow.currentMovieSummary ? mhWindow.currentMovieSummary.progress : 0.0)))
                                        height: parent.height
                                        radius: parent.radius
                                        color: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.watched) ? "#10b981" : Theme.mhAccent
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.overview)
                                      ? mhWindow.currentMovieSummary.overview
                                      : "Local movie file ready for direct playback in MPV."
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                wrapMode: Text.WordWrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.filename) ? ("File: " + mhWindow.currentMovieSummary.filename) : ""
                                color: Theme.textTertiary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideMiddle
                            }

                            // Action Buttons Row
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 12

                                // Primary Play / Resume Movie Button
                                Rectangle {
                                    width: Math.round(220 * Theme.scaleFactor)
                                    height: Math.round(42 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: playMovieHeroMouse.containsMouse ? Qt.lighter(Theme.mhAccent, 1.15) : Theme.mhAccent
                                    border.color: "#ffffff"
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: "▶"; color: "#ffffff"; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
                                        Text {
                                            text: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.is_resumable)
                                                  ? ("Resume (" + mhWindow.currentMovieSummary.resume_time_str + ")")
                                                  : "Play Movie"
                                            color: "#ffffff"
                                            font.pixelSize: Theme.fontSizeNormal
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: playMovieHeroMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend && mhWindow.activeMovieWorkPath) backend.openEntry(mhWindow.activeMovieWorkPath)
                                    }
                                }

                                // Play with HDR Force Button
                                Rectangle {
                                    width: Math.round(160 * Theme.scaleFactor)
                                    height: Math.round(42 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: hdrMovieMouse.containsMouse ? "#35fbbf24" : "#221c1c28"
                                    border.color: "#fbbf24"
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "🔆"; font.pixelSize: Theme.fontSizeSmall }
                                        Text {
                                            text: "Play MPV HDR"
                                            color: "#fde68a"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: hdrMovieMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend && mhWindow.activeMovieWorkPath) backend.openInMpvCustom(mhWindow.activeMovieWorkPath, true)
                                    }
                                }

                                // Toggle Watched Status
                                Rectangle {
                                    width: Math.round(150 * Theme.scaleFactor)
                                    height: Math.round(42 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: toggleWatchedMovMouse.containsMouse ? "#3510b981" : "#221c1c28"
                                    border.color: Theme.borderDim
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            text: (mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.watched) ? "↺ Mark Unwatched" : "✓ Mark Watched"
                                            color: Theme.textPrimary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: toggleWatchedMovMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (backend && mhWindow.activeMovieWorkPath) {
                                                var curW = Boolean(mhWindow.currentMovieSummary && mhWindow.currentMovieSummary.watched)
                                                backend.markMediaWatched(mhWindow.activeMovieWorkPath, !curW)
                                                mhWindow.currentMovieSummary = backend.getMovieWorkSummary(mhWindow.activeMovieWorkPath)
                                            }
                                        }
                                    }
                                }

                                // Open in Find
                                Rectangle {
                                    width: Math.round(145 * Theme.scaleFactor)
                                    height: Math.round(42 * Theme.scaleFactor)
                                    radius: height / 2
                                    color: openFindMovMouse.containsMouse ? "#45222230" : "#221c1c28"
                                    border.color: Theme.borderDim
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "📂"; font.pixelSize: Theme.fontSizeSmall }
                                        Text {
                                            text: "Open in Find"
                                            color: Theme.textPrimary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: openFindMovMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend && mhWindow.activeMovieWorkPath) backend.openInFindInstance(mhWindow.activeMovieWorkPath)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =========================================================
            // 2. SHOW DETAILS & EPISODES LIST VIEW (OR MOVIES FOLDER GRID)
            // =========================================================
            ColumnLayout {
                anchors.fill: parent
                visible: mhWindow.isViewingEpisodeList && !mhWindow.isViewingMoviePage
                spacing: 0

                // ADAPTIVE DYNAMIC HEADER BANNER (Tailored for Extreme Hyprland Tiling & Split-Screen)
                Rectangle {
                    id: showHeaderBanner
                    Layout.fillWidth: true

                    // 0: Wide (>= 860px), 1: Medium (580px - 859px), 2: Compact (< 580px)
                    readonly property int layoutMode: mhWindow.width >= Math.round(860 * Theme.scaleFactor)
                                                      ? 0
                                                      : (mhWindow.width >= Math.round(580 * Theme.scaleFactor) ? 1 : 2)

                    implicitHeight: headerMainLayout.implicitHeight + Math.round(24 * Theme.scaleFactor)
                    color: "#20181824"
                    clip: true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#22ffffff"
                    }

                    component ShowResumePill: Rectangle {
                        id: resumePillComponent
                        implicitHeight: Math.round(38 * Theme.scaleFactor)
                        radius: Math.round(height / 2)
                        color: "#272733"
                        border.color: "#ffffff"
                        border.width: 1.2
                        clip: true

                        readonly property var resData: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.resume) ? mhWindow.currentShowSummary.resume : ({})
                        readonly property bool hasResumeProgress: resData.is_resumable === true
                        readonly property real fillRatio: Math.min(1.0, Math.max(0.0, resData.ratio || 0.0))

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#282836"
                        }

                        Item {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: resumePillComponent.hasResumeProgress
                                   ? Math.max(0, parent.width * resumePillComponent.fillRatio)
                                   : parent.width
                            clip: true

                            Rectangle {
                                width: resumePillComponent.width
                                height: resumePillComponent.height
                                radius: resumePillComponent.radius
                                color: resumeBtnMouse.containsMouse ? Theme.accentHover : Theme.accent
                            }
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
                                    var d = resumePillComponent.resData
                                    if (resumePillComponent.hasResumeProgress) {
                                        return "Resume EP " + (d.ep_num || "1") + (d.time_str ? " (" + d.time_str + ")" : "")
                                    }
                                    return "Play Show"
                                }
                                color: "#ffffff"
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                elide: Text.ElideRight
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

                    component OpenFindPill: Rectangle {
                        implicitHeight: Math.round(34 * Theme.scaleFactor)
                        radius: Math.round(height / 2)
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

                    RowLayout {
                        id: headerMainLayout
                        anchors.fill: parent
                        anchors.margins: Math.round(14 * Theme.scaleFactor)
                        spacing: Math.round(16 * Theme.scaleFactor)

                        Rectangle {
                            id: headerPosterBox
                            Layout.preferredWidth: Math.round((showHeaderBanner.layoutMode === 2 ? 64 : 88) * Theme.scaleFactor)
                            Layout.preferredHeight: Math.round((showHeaderBanner.layoutMode === 2 ? 92 : 126) * Theme.scaleFactor)
                            Layout.alignment: Qt.AlignTop
                            radius: Math.round(8 * Theme.scaleFactor)
                            color: "#18181f"
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
                                mipmap: false
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !headerPosterBox.hasPoster
                                text: "📺"
                                font.pixelSize: Math.round((showHeaderBanner.layoutMode === 2 ? 24 : 34) * Theme.scaleFactor)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Math.round(5 * Theme.scaleFactor)

                            Text {
                                Layout.fillWidth: true
                                text: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.title)
                                      ? mhWindow.currentShowSummary.title
                                      : ((backend && backend.breadcrumbs && backend.breadcrumbs.length > 0)
                                         ? backend.breadcrumbs[backend.breadcrumbs.length - 1].name
                                         : "Show")
                                color: Theme.textPrimary
                                font.pixelSize: Math.round((showHeaderBanner.layoutMode === 2 ? 17 : 21) * Theme.scaleFactor)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Flow {
                                Layout.fillWidth: true
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
                                visible: showHeaderBanner.layoutMode !== 2
                                Layout.fillWidth: true
                                text: (mhWindow.currentShowSummary && mhWindow.currentShowSummary.overview)
                                      ? mhWindow.currentShowSummary.overview
                                      : "Local series folder with automatic episode tracking and audio/subtitle matching."
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                            }

                            RowLayout {
                                visible: showHeaderBanner.layoutMode === 1
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 10

                                ShowResumePill {
                                    Layout.preferredWidth: Math.round(200 * Theme.scaleFactor)
                                }

                                OpenFindPill {
                                    Layout.preferredWidth: Math.round(140 * Theme.scaleFactor)
                                }

                                Item { Layout.fillWidth: true }
                            }

                            RowLayout {
                                visible: showHeaderBanner.layoutMode === 2
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8

                                ShowResumePill {
                                    Layout.fillWidth: true
                                }

                                OpenFindPill {
                                    Layout.preferredWidth: Math.round(110 * Theme.scaleFactor)
                                }
                            }
                        }

                        ColumnLayout {
                            visible: showHeaderBanner.layoutMode === 0
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: Math.round(200 * Theme.scaleFactor)
                            spacing: 8

                            ShowResumePill {
                                Layout.fillWidth: true
                            }

                            OpenFindPill {
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // MOVIES FOLDER POSTER GRID (When viewing a Movies Folder so it's never treated as a TV series!)
                GridView {
                    id: moviesCatalogGrid
                    visible: mhWindow.isMovieLibraryFolder
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Math.round(18 * Theme.scaleFactor)
                    clip: true
                    cellWidth: Math.round(176 * Theme.scaleFactor)
                    cellHeight: Math.round(268 * Theme.scaleFactor)
                    model: visible && backend ? backend.files : null

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    SmoothScroll { target: moviesCatalogGrid; orientation: Qt.Vertical }

                    delegate: Item {
                        width: moviesCatalogGrid.cellWidth
                        height: moviesCatalogGrid.cellHeight

                        Rectangle {
                            id: movGridCard
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Theme.radiusLarge
                            color: movGridMouse.containsMouse ? "#28ffffff" : "#161822"
                            border.color: movGridMouse.containsMouse ? Theme.mhAccent : "#26ffffff"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Math.round(8 * Theme.scaleFactor)
                                    color: "#10121a"
                                    clip: true

                                    readonly property string artUrl: (model.poster && model.poster !== "")
                                                                     ? ("file://" + model.poster)
                                                                     : ((model.thumb && model.thumb !== "") ? ("file://" + model.thumb) : "")

                                    Image {
                                        anchors.fill: parent
                                        visible: parent.artUrl !== ""
                                        source: parent.artUrl
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        mipmap: false
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.artUrl === ""
                                        text: model.is_dir ? "📁" : "🎬"
                                        font.pixelSize: Math.round(38 * Theme.scaleFactor)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (model.episode_title && model.episode_title !== "") ? model.episode_title : model.name
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: movGridMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        mhContext.targetPath = model.path || ""
                                        mhContext.targetName = model.name || ""
                                        mhContext.showPath = ""
                                        mhContext.isDir = Boolean(model.is_dir)
                                        mhContext.isAiringItem = false
                                        mhContext.popupSafe(movGridCard, mouse.x, mouse.y)
                                    } else {
                                        if (model.is_dir) {
                                            backend.navigateTo(model.path)
                                        } else {
                                            mhWindow.openMoviePage(model.path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // EPISODES LIST (Translucent Glass cards, pure 'ar' tag when Arabic subtitle metadata is present)
                ListView {
                    id: episodesList
                    visible: !mhWindow.isMovieLibraryFolder
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Math.round(16 * Theme.scaleFactor)
                    clip: true
                    interactive: false
                    highlightFollowsCurrentItem: false
                    spacing: 8
                    model: visible && backend ? backend.files : null

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    SmoothScroll { target: episodesList; orientation: Qt.Vertical }

                    delegate: Rectangle {
                        id: epRowBox
                        width: episodesList.width - Math.round(12 * Theme.scaleFactor)
                        height: Math.round(80 * Theme.scaleFactor)
                        radius: Theme.radiusLarge
                        color: epMouse.containsMouse ? "#30262635" : "#1e1a1a24"
                        border.color: epMouse.containsMouse ? Theme.accent : "#22ffffff"
                        border.width: 1

                        Component.onCompleted: {
                            if (!backend || !model.path) return
                            if (model.is_dir) {
                                backend.requestFolderPreview(model.path)
                            } else {
                                if (!model.thumb || model.thumb === "") {
                                    backend.requestItemThumbnail(model.path)
                                }
                                backend.requestEpisodeDetailedInfoAsync(model.path)
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
                                    mipmap: false
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

                                    // NEW Badge inside Show Episode List
                                    Rectangle {
                                        visible: model.is_new === true && !model.is_watched
                                        implicitWidth: epNewLbl.implicitWidth + 10
                                        implicitHeight: Math.round(17 * Theme.scaleFactor)
                                        radius: Theme.radiusSmall
                                        color: "#22f59e0b"
                                        border.color: "#f59e0b"
                                        border.width: 1

                                        Text {
                                            id: epNewLbl
                                            anchors.centerIn: parent
                                            text: "NEW"
                                            color: "#fbbf24"
                                            font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                            font.bold: true
                                        }
                                    }

                                    // HDR Badge inside Show Episode List
                                    Rectangle {
                                        visible: model.is_hdr === true
                                        implicitWidth: epHdrLbl.implicitWidth + Math.round(10 * Theme.scaleFactor)
                                        implicitHeight: Math.round(16 * Theme.scaleFactor)
                                        radius: Math.round(3 * Theme.scaleFactor)
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "#28e2e8f0" }
                                            GradientStop { position: 1.0; color: "#1294a3b8" }
                                        }
                                        border.color: "#e2e8f0"
                                        border.width: 1

                                        Text {
                                            id: epHdrLbl
                                            anchors.centerIn: parent
                                            text: "HDR"
                                            color: "#f1f5f9"
                                            font.pixelSize: Math.round(8 * Theme.scaleFactor)
                                            font.bold: true
                                            font.letterSpacing: 0.8
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        visible: model.duration_str !== undefined && model.duration_str !== ""
                                        text: "⏱ " + (model.duration_str || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    Text {
                                        visible: model.duration_str !== undefined && model.duration_str !== ""
                                        text: "•"
                                        color: Theme.textTertiary
                                    }

                                    Text {
                                        text: "💾 " + (model.size || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    // Display 'ar' Tag ONLY when Arabic subtitles are verified in metadata
                                    Rectangle {
                                        visible: model.has_arabic_sub === true
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
                                    mhContext.showPath = ""
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
        onRequestAiringLinkModal: function(aid, aTitle) {
            mhAiringLinkDialog.openForAiring(aid, aTitle)
        }
    }

    Dialog {
        id: mhAiringLinkDialog
        title: "Link Airing Anime with Media Hub Work"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(520 * Theme.scaleFactor), mhWindow.width - 24)
        height: Math.min(Math.round(440 * Theme.scaleFactor), mhWindow.height - 24)

        property string targetAiringId: ""
        property string targetAiringTitle: ""
        property var candidatesList: []
        property bool browsingCustomLink: false

        function openForAiring(aid, title) {
            targetAiringId = aid
            targetAiringTitle = title
            mhLinkFilterField.text = ""
            candidatesList = backend ? backend.getMediaHubLinkCandidates() : []
            mhAiringLinkDialog.open()
            mhLinkFilterField.forceActiveFocus()
        }

        Connections {
            target: backend
            function onPickerCompleted(paths) {
                if (paths.length > 0 && mhAiringLinkDialog.browsingCustomLink) {
                    mhAiringLinkDialog.browsingCustomLink = false
                    backend.linkAiringToMediaFolder(mhAiringLinkDialog.targetAiringId, paths[0])
                    mhAiringLinkDialog.close()
                }
            }
        }

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.accent
            border.width: 1
            radius: Theme.radiusLarge
        }

        header: Rectangle {
            height: Math.round(44 * Theme.scaleFactor)
            color: Theme.bgCard
            radius: Theme.radiusLarge
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                Text {
                    Layout.fillWidth: true
                    text: "🔗 Link '" + mhAiringLinkDialog.targetAiringTitle + "' with Local Work"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: mhLinkFilterField
                    Layout.fillWidth: true
                    placeholderText: "🔍 Search your Media Hub works..."
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                    selectByMouse: true
                    background: Rectangle {
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: mhLinkFilterField.activeFocus ? Theme.accent : Theme.borderDim
                    }
                }
                Button {
                    text: "📂 Browse Folder..."
                    onClicked: {
                        mhAiringLinkDialog.browsingCustomLink = true
                        if (backend) backend.openInternalPicker("folder", "", "Select Local Anime Folder to Link")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textPrimary
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(130 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : Theme.bgCard
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgBase
                radius: Theme.radiusMedium
                border.color: Theme.borderDim
                clip: true

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    clip: true
                    model: {
                        var q = mhLinkFilterField.text.trim().toLowerCase()
                        var all = mhAiringLinkDialog.candidatesList || []
                        if (q === "") return all
                        var filtered = []
                        for (var i = 0; i < all.length; i++) {
                            if (all[i].name.toLowerCase().indexOf(q) !== -1 || all[i].path.toLowerCase().indexOf(q) !== -1) {
                                filtered.push(all[i])
                            }
                        }
                        return filtered
                    }

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Math.round(40 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: mhCandMouse.containsMouse ? Theme.bgHover : Theme.bgCard
                        border.color: mhCandMouse.containsMouse ? Theme.accent : Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            Text { text: "📺"; font.pixelSize: Theme.fontSizeMedium }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeNormal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.path
                                    color: Theme.textTertiary
                                    font.family: "monospace"
                                    font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        MouseArea {
                            id: mhCandMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend) {
                                    backend.linkAiringToMediaFolder(mhAiringLinkDialog.targetAiringId, modelData.path)
                                }
                                mhAiringLinkDialog.close()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: "Cancel"
                    onClicked: mhAiringLinkDialog.close()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(85 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : "transparent"
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }
            }
        }
    }
}
