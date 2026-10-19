import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: "transparent"

    property var appWindow: null

    readonly property bool showModifiedCol: width >= Math.round(420 * Theme.scaleFactor)
    readonly property bool showSizeCol: width >= Math.round(290 * Theme.scaleFactor)
    property string hoveredSubfolderPath: ""
    readonly property bool hasOpenModal: permDeleteDialog.visible || airingLinkDialog.visible || desktopMakerModal.visible || propertiesModal.visible || dolphinMenu.visible || dolphinMenu.hasDialogOpen || backgroundMenu.visible

    function extractDropUrls(drop) {
        var urls = []
        if (drop.hasUrls) {
            for (var i = 0; i < drop.urls.length; i++) {
                urls.push(drop.urls[i].toString())
            }
        } else if (drop.text && drop.text.trim() !== "") {
            urls = drop.text.trim().split(/\r?\n/)
        }
        return urls
    }

    function currentGridColumns() {
        return fileGridView.targetCols > 0 ? fileGridView.targetCols : 1
    }

    function syncViewScrollToSelection() {
        if (!backend) return
        var rowIdx = backend.getSelectedRowIndex()
        if (rowIdx < 0) return
        if (backend.viewMode === "details") {
            fileListView.currentIndex = rowIdx
            fileListView.positionViewAtIndex(rowIdx, ListView.Contain)
        } else {
            fileGridView.currentIndex = rowIdx
            fileGridView.positionViewAtIndex(rowIdx, GridView.Contain)
        }
    }

    function openRenameForSelected() {
        if (backend && backend.selectedItem && backend.selectedItem.path) {
            dolphinMenu.targetPath = backend.selectedItem.path
            dolphinMenu.targetName = backend.selectedItem.name
            dolphinMenu.isDir = backend.selectedItem.is_dir
            dolphinMenu.openRenameModal()
        }
    }

    DesktopMakerDialog {
        id: desktopMakerModal
    }

    PropertiesDialog {
        id: propertiesModal
    }

    function openPropertiesForSelected() {
        if (!backend) return
        var p = (backend.selectedItem && backend.selectedItem.path) ? backend.selectedItem.path : backend.currentPath
        propertiesModal.openForPath(p)
    }

    function promptPermanentDelete(targetPath, isEmptyAll) {
        permDeleteDialog.targetPath = targetPath || ""
        permDeleteDialog.emptyAllMode = Boolean(isEmptyAll)
        permDeleteDialog.open()
    }

    Dialog {
        id: permDeleteDialog
        title: "Confirm Permanent Deletion"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(420 * Theme.scaleFactor), root.width - 24)

        property string targetPath: ""
        property bool emptyAllMode: false

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.textDanger
            border.width: 1
            radius: Theme.radiusLarge
        }

        header: Rectangle {
            height: Math.round(42 * Theme.scaleFactor)
            color: Theme.bgCard
            radius: Theme.radiusLarge
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: permDeleteDialog.emptyAllMode ? "🔥 Empty Entire Trash?" : "🔥 Permanently Delete Item(s)?"
                color: Theme.textDanger
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: permDeleteDialog.emptyAllMode
                      ? ("Are you sure you want to permanently erase all " + (backend ? backend.trashItemCount : 0) + " item(s) (" + (backend ? backend.trashTotalSize : "0 B") + ") in the Trash?\n\nThis action cannot be undone!")
                      : "Are you sure you want to permanently delete the selected item(s)?\n\nThis action cannot be undone!"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: permDeleteDialog.close()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(80 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : "transparent"
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }

                Button {
                    text: "🔥 Delete Forever"
                    onClicked: {
                        if (backend) {
                            if (permDeleteDialog.emptyAllMode) {
                                backend.emptyTrash()
                            } else {
                                backend.deletePermanently(permDeleteDialog.targetPath)
                            }
                        }
                        permDeleteDialog.close()
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(145 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? "#dc2626" : "#b91c1c"
                        radius: Theme.radiusSmall
                    }
                }
            }
        }
    }

    Dialog {
        id: airingLinkDialog
        title: "Link Airing Anime with Media Hub Work"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(520 * Theme.scaleFactor), root.width - 24)
        height: Math.min(Math.round(440 * Theme.scaleFactor), root.height - 24)

        property string targetAiringId: ""
        property string targetAiringTitle: ""
        property var candidatesList: []

        function openForAiring(aid, title) {
            targetAiringId = aid
            targetAiringTitle = title
            linkFilterField.text = ""
            candidatesList = backend ? backend.getMediaHubLinkCandidates() : []
            airingLinkDialog.open()
            linkFilterField.forceActiveFocus()
        }

        Connections {
            target: backend
            function onPickerCompleted(paths) {
                if (paths.length > 0 && airingLinkDialog.browsingCustomLink) {
                    airingLinkDialog.browsingCustomLink = false
                    backend.linkAiringToMediaFolder(airingLinkDialog.targetAiringId, paths[0])
                    airingLinkDialog.close()
                }
            }
        }

        property bool browsingCustomLink: false

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
                    text: "🔗 Link '" + airingLinkDialog.targetAiringTitle + "' with Local Work"
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
                    id: linkFilterField
                    Layout.fillWidth: true
                    placeholderText: "🔍 Search your Media Hub works..."
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                    selectByMouse: true
                    background: Rectangle {
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: linkFilterField.activeFocus ? Theme.accent : Theme.borderDim
                    }
                }
                Button {
                    text: "📂 Browse Folder..."
                    onClicked: {
                        airingLinkDialog.browsingCustomLink = true
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
                        var q = linkFilterField.text.trim().toLowerCase()
                        var all = airingLinkDialog.candidatesList || []
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
                        color: candMouse.containsMouse ? Theme.bgHover : Theme.bgCard
                        border.color: candMouse.containsMouse ? Theme.accent : Theme.borderDim

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
                            id: candMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend) {
                                    backend.linkAiringToMediaFolder(airingLinkDialog.targetAiringId, modelData.path)
                                }
                                airingLinkDialog.close()
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
                    onClicked: airingLinkDialog.close()
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

    DolphinContextMenu {
        id: dolphinMenu
        onRequestDesktopMaker: function(execPath) {
            desktopMakerModal.openForExecutable(execPath)
        }
        onRequestPermanentDelete: function(tPath) {
            root.promptPermanentDelete(tPath, false)
        }
        onRequestProperties: function(tPath) {
            propertiesModal.openForPath(tPath)
        }
        onRequestAiringLinkModal: function(aid, aTitle) {
            airingLinkDialog.openForAiring(aid, aTitle)
        }
    }

    StyledMenu {
        id: backgroundMenu

        StyledMenuItem {
            iconGlyph: "📁"
            text: "New Folder"
            font.bold: true
            onTriggered: backend.createItem("folder", "")
        }
        StyledMenuItem {
            iconGlyph: "📄"
            text: "New Text File"
            onTriggered: backend.createItem("txt", "")
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            iconGlyph: "📋"
            text: "Paste Here"
            shortcutText: "Ctrl+V"
            enabled: backend ? ((backend.hasClipboardItems || backend.getClipboardPath() !== "") && backend.currentPath !== "recent://" && backend.currentPath !== "trash://" && backend.currentPath !== "mediahub://" && backend.currentPath !== "favorites://") : false
            onTriggered: {
                if (root.appWindow) {
                    root.appWindow.triggerPasteInCurrentFolder()
                } else if (backend) {
                    backend.pasteToFolder(backend.currentPath)
                }
            }
        }
        StyledMenuItem {
            visible: backend ? backend.canResumeFolder(backend.currentPath) : false
            iconGlyph: "▶"
            text: "Resume Last Episode Here"
            font.bold: true
            onTriggered: if (backend) backend.resumeMediaFolder(backend.currentPath)
        }
        StyledMenuItem {
            visible: backend ? backend.canInstallFontsFrom(backend.currentPath) : false
            iconGlyph: "🔤"
            text: "Install All Fonts in Folder"
            font.bold: true
            onTriggered: if (backend) backend.installFontsToSystem(backend.currentPath, "")
        }
        StyledMenuItem {
            iconGlyph: "⭐"
            text: "Pin Current Folder to Favorites"
            onTriggered: if (backend) backend.addToFavorites(backend.currentPath)
        }
        StyledMenuItem {
            iconGlyph: "💻"
            text: "Open in Terminal"
            onTriggered: backend.openInTerminal(backend.currentPath)
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            text: "Show Hidden Files"
            shortcutText: "Ctrl+H"
            checkable: true
            checked: backend ? backend.showHidden : false
            onTriggered: if (backend) backend.toggleShowHidden()
        }
        StyledMenuItem {
            visible: backend ? backend.isMediaLibraryView : false
            text: "Show Subtitle Files in Media Library"
            shortcutText: "C"
            checkable: true
            checked: backend ? backend.showSubtitlesInMedia : false
            onTriggered: if (backend) backend.toggleSubtitlesInMedia()
        }
        StyledMenuItem {
            iconGlyph: "⟳"
            text: "Sync Jellyfin & Refresh"
            shortcutText: "Ctrl+R"
            onTriggered: if (backend) backend.syncJellyfinAndRefresh()
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            iconGlyph: "ℹ️"
            text: "Folder Properties & Permissions"
            shortcutText: "Alt+Enter"
            onTriggered: propertiesModal.openForPath(backend ? backend.currentPath : "")
        }
    }

    // Main DropArea for external and internal drops (Strictly ignores same-folder drops unless hovering a subfolder!)
    DropArea {
        id: viewDropArea
        anchors.fill: parent
        z: 5
        property bool canAcceptCurrentDrag: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Theme.radiusLarge
            color: "#180078d4"
            border.color: Theme.accent
            border.width: 2
            visible: viewDropArea.containsDrag && viewDropArea.canAcceptCurrentDrag && root.hoveredSubfolderPath === ""
        }

        function updateDragTargetState(drag) {
            if (!backend) {
                root.hoveredSubfolderPath = ""
                canAcceptCurrentDrag = false
                return
            }
            var curDir = backend.currentPath
            if (curDir === "recent://" || curDir === "trash://") {
                root.hoveredSubfolderPath = ""
                canAcceptCurrentDrag = false
                return
            }

            var activeView = backend.viewMode === "details" ? fileListView : fileGridView
            var viewPt = root.mapToItem(activeView, drag.x, drag.y)
            var hoveredItem = activeView.itemAt(viewPt.x + activeView.contentX, viewPt.y + activeView.contentY)

            var subTarget = ""
            if (hoveredItem && hoveredItem.itemIsDir && hoveredItem.itemPath !== "") {
                subTarget = hoveredItem.itemPath
            }

            var urls = root.extractDropUrls(drag)
            var destToCheck = subTarget !== "" ? subTarget : curDir
            var validSources = backend.filterValidDropSources(urls, destToCheck)

            if (validSources && validSources.length > 0) {
                root.hoveredSubfolderPath = subTarget
                canAcceptCurrentDrag = true
            } else {
                root.hoveredSubfolderPath = ""
                canAcceptCurrentDrag = false
            }
        }

        onEntered: function(drag) {
            if (backend && backend.currentPath === "favorites://") {
                canAcceptCurrentDrag = true
                return
            }
            updateDragTargetState(drag)
        }

        onPositionChanged: function(drag) {
            if (backend && backend.currentPath === "favorites://") {
                canAcceptCurrentDrag = true
                return
            }
            updateDragTargetState(drag)
        }

        onExited: {
            root.hoveredSubfolderPath = ""
            canAcceptCurrentDrag = false
        }

        onDropped: function(drop) {
            var subPath = root.hoveredSubfolderPath
            root.hoveredSubfolderPath = ""
            canAcceptCurrentDrag = false
            if (!backend) return

            var urls = root.extractDropUrls(drop)
            if (backend.currentPath === "favorites://") {
                for (var i = 0; i < urls.length; i++) {
                    var cleanU = urls[i].replace("file://", "")
                    backend.addToFavorites(cleanU)
                }
                drop.acceptProposedAction()
                return
            }

            var targetFolder = subPath !== "" ? subPath : backend.currentPath
            if (targetFolder === "recent://" || targetFolder === "trash://") return

            var valid = backend.filterValidDropSources(urls, targetFolder)
            if (valid && valid.length > 0 && root.appWindow) {
                var winPt = root.mapToItem(root.appWindow.contentItem, drop.x, drop.y)
                root.appWindow.requestSmartDrop(valid, targetFolder, winPt.x, winPt.y)
                drop.acceptProposedAction()
            }
        }
    }

    MouseArea {
        id: backgroundArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (!backend) return
            var swapped = backend.swapMouseButtons
            var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
            var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

            if (isPrimary) {
                backend.clearSelection()
            } else if (isSecondary) {
                backgroundMenu.popup()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Search Results Overlay (Shows folders + files, real file icons/thumbnails, and full context menu)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: backend && backend.searchResults ? backend.searchResults.length > 0 : false
            color: Theme.bgBase

            ListView {
                id: searchListView
                anchors.fill: parent
                model: backend ? backend.searchResults : []
                clip: true
                spacing: 2

                WheelHandler {
                    target: null
                    orientation: Qt.Vertical
                    onWheel: function(event) {
                        var step = (event.angleDelta.y / 120.0) * Math.round(920 * Theme.scaleFactor)
                        var maxY = Math.max(0, searchListView.contentHeight - searchListView.height)
                        searchListView.contentY = Math.max(0, Math.min(maxY, searchListView.contentY - step))
                        event.accepted = true
                    }
                }

                delegate: Rectangle {
                    id: sRow
                    width: ListView.view.width - 12
                    x: 6
                    height: Math.round(40 * Theme.scaleFactor)
                    radius: Theme.radiusMedium
                    readonly property bool isSel: (backend && backend.selectedItem && backend.selectedItem.path === modelData.path) ? true : false
                    color: isSel ? Theme.bgSelected : (sHover.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.accent : "transparent"
                    border.width: isSel ? 1 : 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Item {
                            implicitWidth: Math.round(26 * Theme.scaleFactor)
                            implicitHeight: Math.round(26 * Theme.scaleFactor)

                            Image {
                                id: sThumbImg
                                anchors.fill: parent
                                visible: !modelData.is_dir && ((modelData.thumb && modelData.thumb !== "") || (modelData.icon && (modelData.icon.indexOf("/") !== -1 || modelData.icon.indexOf(".") !== -1)))
                                source: visible ? ((modelData.thumb && modelData.thumb !== "") ? ("file://" + modelData.thumb) : ("file://" + modelData.icon)) : ""
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !sThumbImg.visible
                                text: modelData.icon ? modelData.icon : (modelData.is_dir ? "📁" : "📄")
                                font.pixelSize: Theme.fontSizeIcon
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.path
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            visible: modelData.is_dir
                            implicitWidth: dirBadge.implicitWidth + 10
                            implicitHeight: Math.round(18 * Theme.scaleFactor)
                            radius: Theme.radiusSmall
                            color: Theme.bgCard
                            border.color: Theme.borderDim
                            Text {
                                id: dirBadge
                                anchors.centerIn: parent
                                text: "Folder"
                                color: Theme.textSecondary
                                font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                font.bold: true
                            }
                        }

                        Text {
                            visible: !modelData.is_dir && modelData.size !== undefined && modelData.size !== ""
                            text: modelData.size || ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    MouseArea {
                        id: sHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: function(mouse) {
                            if (!backend) return
                            if (mouse.button === Qt.MiddleButton && modelData.is_dir) {
                                backend.addTab(modelData.path)
                                return
                            }
                            backend.selectItem(modelData.path, modelData.name, modelData.is_dir, modelData.size || "", "", modelData.type || "")
                            if (mouse.button === Qt.RightButton) {
                                dolphinMenu.targetPath = modelData.path
                                dolphinMenu.targetName = modelData.name
                                dolphinMenu.isDir = modelData.is_dir
                                dolphinMenu.popupSafe(sRow, mouse.x, mouse.y)
                            }
                        }
                        onDoubleClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton && backend) {
                                backend.openEntry(modelData.path)
                            }
                        }
                    }
                }
            }
        }

        // Normal View
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: backend && backend.searchResults ? backend.searchResults.length === 0 : true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Storage Analyzer Action Banner (Shows total analyzed folder size + descending usage breakdown)
                Rectangle {
                    visible: backend ? backend.isStorageAnalyzerView : false
                    Layout.fillWidth: true
                    height: Math.round(46 * Theme.scaleFactor)
                    color: "#16202a"
                    border.color: "#4538bdf8"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Text {
                            text: "📊  Storage Analyzer  •  Total Used: " + (backend ? backend.analyzerTotalSize : "0 B") + "  •  " + (backend ? backend.analyzerItemCount : 0) + " items (Sorted Largest First)"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "↑ Up Folder"
                            onClicked: if (backend) backend.goUp()
                            contentItem: Text {
                                text: parent.text
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                implicitWidth: Math.round(95 * Theme.scaleFactor)
                                implicitHeight: Math.round(28 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: parent.hovered ? Theme.bgHover : Theme.bgSurface
                                border.color: Theme.borderDim
                            }
                        }

                        Button {
                            text: "📂 Open Normal View"
                            onClicked: {
                                if (!backend) return
                                var raw = backend.currentPath.replace("analyzer://", "")
                                backend.navigateTo(raw)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                implicitWidth: Math.round(135 * Theme.scaleFactor)
                                implicitHeight: Math.round(28 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: parent.hovered ? Theme.accentHover : Theme.accent
                            }
                        }
                    }
                }

                // Trash Management Action Banner (Shows total Trash size + Restore + Permanent Delete)
                Rectangle {
                    visible: backend ? backend.isTrashView : false
                    Layout.fillWidth: true
                    height: Math.round(46 * Theme.scaleFactor)
                    color: "#1f181b"
                    border.color: "#45f87171"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Text {
                            text: "🗑️  TrashTotal Size: " + (backend ? backend.trashTotalSize : "0 B") + "  •  " + (backend ? backend.trashItemCount : 0) + " item(s)"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "↩ Restore Selected"
                            enabled: backend ? (backend.selectedPaths.length > 0 || (backend.selectedItem && backend.selectedItem.path !== undefined && backend.selectedItem.path !== "")) : false
                            onClicked: if (backend) backend.restoreFromTrash("")
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#ffffff" : Theme.textTertiary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                implicitWidth: Math.round(135 * Theme.scaleFactor)
                                implicitHeight: Math.round(30 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: parent.enabled ? (parent.hovered ? Theme.accentHover : Theme.accent) : Theme.bgCard
                            }
                        }

                        Button {
                            text: "🔥 Delete Selected"
                            enabled: backend ? (backend.selectedPaths.length > 0 || (backend.selectedItem && backend.selectedItem.path !== undefined && backend.selectedItem.path !== "")) : false
                            onClicked: root.promptPermanentDelete("", false)
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#ffffff" : Theme.textTertiary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                implicitWidth: Math.round(135 * Theme.scaleFactor)
                                implicitHeight: Math.round(30 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: parent.enabled ? (parent.hovered ? "#dc2626" : "#b91c1c") : Theme.bgCard
                            }
                        }

                        Button {
                            text: "🧹 Empty Trash"
                            enabled: backend ? (backend.trashItemCount > 0) : false
                            onClicked: root.promptPermanentDelete("", true)
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? Theme.textDanger : Theme.textTertiary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                implicitWidth: Math.round(115 * Theme.scaleFactor)
                                implicitHeight: Math.round(30 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: parent.hovered ? "#25f87171" : Theme.bgSurface
                                border.color: parent.enabled ? "#66f87171" : Theme.borderDim
                            }
                        }
                    }
                }

                // Table Header
                Rectangle {
                    Layout.fillWidth: true
                    height: Math.round(32 * Theme.scaleFactor)
                    color: Theme.bgSurface
                    visible: backend ? (backend.viewMode === "details" && !backend.isMediaHubView) : true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.borderDim
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: "Name" + ((backend && backend.sortBy === "name") ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (backend) backend.setSort("name")
                            }
                        }

                        Text {
                            visible: root.showModifiedCol
                            Layout.preferredWidth: Math.round(135 * Theme.scaleFactor)
                            text: "Date modified" + ((backend && backend.sortBy === "modified") ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (backend) backend.setSort("modified")
                            }
                        }

                        Text {
                            visible: root.showSizeCol
                            Layout.preferredWidth: Math.round(80 * Theme.scaleFactor)
                            text: "Size" + ((backend && backend.sortBy === "size") ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            horizontalAlignment: Text.AlignRight
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setSort("size")
                            }
                        }
                    }
                }

                // Viewport Stack (Eliminates ColumnLayout relayout flashing between ListView and GridView!)
                Item {
                    id: viewStackContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                // 0. Media Hub Multi-Row Smart View (mediahub://)
                Flickable {
                    id: mediaHubFlick
                    anchors.fill: parent
                    visible: backend ? backend.isMediaHubView : false
                    contentWidth: width
                    contentHeight: hubMainCol.implicitHeight + Math.round(36 * Theme.scaleFactor)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        target: null
                        orientation: Qt.Vertical
                        onWheel: function(event) {
                            var step = (event.angleDelta.y / 120.0) * Math.round(960 * Theme.scaleFactor)
                            var maxY = Math.max(0, mediaHubFlick.contentHeight - mediaHubFlick.height)
                            mediaHubFlick.contentY = Math.max(0, Math.min(maxY, mediaHubFlick.contentY - step))
                            event.accepted = true
                        }
                    }

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: hubMainCol
                        width: mediaHubFlick.width - Math.round(28 * Theme.scaleFactor)
                        x: Math.round(14 * Theme.scaleFactor)
                        y: Math.round(12 * Theme.scaleFactor)
                        spacing: Math.round(22 * Theme.scaleFactor)

                        // Media Hub Top Banner
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.round(58 * Theme.scaleFactor)
                            radius: Theme.radiusLarge
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#280078d4" }
                                GradientStop { position: 1.0; color: "#141e293b" }
                            }
                            border.color: (backend && backend.anonymousMode) ? "#f59e0b" : "#450078d4"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: (backend && backend.anonymousMode) ? "🕵️" : "🎬"
                                    font.pixelSize: Math.round(24 * Theme.scaleFactor)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        spacing: 8
                                        Text {
                                            text: "Media Hub"
                                            color: Theme.textPrimary
                                            font.pixelSize: Theme.fontSizeTitle
                                            font.bold: true
                                        }
                                        Rectangle {
                                            visible: backend ? backend.anonymousMode : false
                                            implicitWidth: anonHubBadge.implicitWidth + 10
                                            implicitHeight: Math.round(18 * Theme.scaleFactor)
                                            radius: Theme.radiusSmall
                                            color: "#33f59e0b"
                                            border.color: "#f59e0b"
                                            Text {
                                                id: anonHubBadge
                                                anchors.centerIn: parent
                                                text: "ANONYMOUS MODE ACTIVE (Shift+A)"
                                                color: "#fbbf24"
                                                font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                font.bold: true
                                            }
                                        }
                                    }
                                    Text {
                                        text: "Smart links directly connected to your local media files & Jellyfin progress"
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Button {
                                    text: "🔄 Sync Hub"
                                    onClicked: if (backend) backend.syncJellyfinAndRefresh()
                                    contentItem: Text {
                                        text: parent.text
                                        color: "#ffffff"
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    background: Rectangle {
                                        implicitWidth: Math.round(92 * Theme.scaleFactor)
                                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                                        radius: Theme.radiusMedium
                                        color: parent.hovered ? Theme.accentHover : Theme.accent
                                    }
                                }
                            }
                        }

                        // Empty State when no media libraries are configured or all rows are empty
                        Rectangle {
                            visible: (!backend || !backend.mediaHubSections || backend.mediaHubSections.length === 0)
                            Layout.fillWidth: true
                            implicitHeight: Math.round(140 * Theme.scaleFactor)
                            radius: Theme.radiusLarge
                            color: Theme.bgCard
                            border.color: Theme.borderDim

                            Text {
                                anchors.centerIn: parent
                                text: "No visible Media Hub rows enabled. You can enable or reorder rows in Settings → Media Library & HDR."
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeNormal
                            }
                        }

                        // Persistent Damage-Tracked Media Hub Sections (Zero Flashing, Preserves Scroll & Delegates!)
                        Repeater {
                            model: backend ? backend.mediaHubModel : null
                            delegate: ColumnLayout {
                                id: sectionBlock
                                Layout.fillWidth: true
                                spacing: Math.round(10 * Theme.scaleFactor)

                                required property string section_id
                                required property string title
                                required property string subtitle
                                required property int item_count
                                required property var cards_model

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: sectionBlock.title
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeTitle
                                        font.bold: true
                                    }

                                    Rectangle {
                                        implicitWidth: cntTxt.implicitWidth + 10
                                        implicitHeight: Math.round(18 * Theme.scaleFactor)
                                        radius: Theme.radiusSmall
                                        color: Theme.bgCard
                                        border.color: Theme.borderDim
                                        Text {
                                            id: cntTxt
                                            anchors.centerIn: parent
                                            text: String(sectionBlock.item_count)
                                            color: Theme.textSecondary
                                            font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: sectionBlock.subtitle || ""
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    visible: sectionBlock.item_count === 0
                                    Layout.fillWidth: true
                                    height: Math.round(78 * Theme.scaleFactor)
                                    radius: Theme.radiusMedium
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    Text {
                                        anchors.centerIn: parent
                                        text: "No items in this row right now."
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                ListView {
                                    id: rowHorizList
                                    visible: sectionBlock.item_count > 0
                                    Layout.fillWidth: true
                                    height: Math.round(238 * Theme.scaleFactor)
                                    orientation: ListView.Horizontal
                                    spacing: Math.round(12 * Theme.scaleFactor)
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    reuseItems: false
                                    model: sectionBlock.cards_model

                                    WheelHandler {
                                        target: null
                                        orientation: Qt.Horizontal
                                        onWheel: function(event) {
                                            var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                                            var step = (delta / 120.0) * Math.round(840 * Theme.scaleFactor)
                                            var maxX = Math.max(0, rowHorizList.contentWidth - rowHorizList.width)
                                            rowHorizList.contentX = Math.max(0, Math.min(maxX, rowHorizList.contentX - step))
                                            event.accepted = true
                                        }
                                    }

                                    delegate: Rectangle {
                                        id: hubCard
                                        width: Math.round(154 * Theme.scaleFactor)
                                        height: Math.round(236 * Theme.scaleFactor)
                                        radius: Theme.radiusLarge
                                        readonly property bool isCardSel: {
                                            if (!backend || !model.path) return false
                                            var sList = backend.selectedPaths
                                            if (sList && sList.indexOf(model.path) !== -1) return true
                                            return (backend.selectedItem && backend.selectedItem.path === model.path) ? true : false
                                        }
                                        // Floating Poster Preview style: transparent background, no heavy box frame!
                                        color: isCardSel ? "#240078d4" : (hubCardMouse.containsMouse ? "#12ffffff" : "transparent")
                                        border.color: isCardSel ? Theme.accent : "transparent"
                                        border.width: isCardSel ? 1 : 0

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 6

                                            // Floating Poster / Thumbnail Viewport (Hugs painted image with ultra-thin border & smooth corners)
                                            Item {
                                                id: posterViewport
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                Image {
                                                    id: hubPosterImg
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    visible: model.art_source !== ""
                                                    source: model.art_source
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                    smooth: true
                                                    mipmap: true
                                                }

                                                // Fallback Icon Card only when no poster/thumb exists
                                                Rectangle {
                                                    visible: model.art_source === ""
                                                    width: parent.width * 0.84
                                                    height: parent.height * 0.92
                                                    anchors.centerIn: parent
                                                    radius: Math.round(10 * Theme.scaleFactor)
                                                    color: Theme.bgSurface
                                                    border.color: "#26ffffff"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: model.is_dir ? "📺" : "🎬"
                                                        font.pixelSize: Math.round(34 * Theme.scaleFactor)
                                                    }
                                                }

                                                // Tightly hugs the actual fitted poster dimensions
                                                Rectangle {
                                                    id: posterOverlayFrame
                                                    anchors.centerIn: hubPosterImg
                                                    width: hubPosterImg.paintedWidth > 0 ? hubPosterImg.paintedWidth : ( parent.width * 0.86 )
                                                    height: hubPosterImg.paintedHeight > 0 ? hubPosterImg.paintedHeight : ( parent.height * 0.94 )
                                                    radius: Math.round(10 * Theme.scaleFactor)
                                                    color: "transparent"
                                                    border.color: hubCard.isCardSel ? Theme.accent : (hubCardMouse.containsMouse ? "#45ffffff" : "#1affffff")
                                                    border.width: 1

                                                    // Top-Left Smart Episode / Range Badge (e.g. "EP 5-15 added", "EP 04 • 62%")
                                                    Rectangle {
                                                        visible: model.badge !== undefined && model.badge !== ""
                                                        anchors.left: parent.left
                                                        anchors.top: parent.top
                                                        anchors.margins: 6
                                                        implicitWidth: Math.min(parent.width - 12, badgeLbl.implicitWidth + 12)
                                                        implicitHeight: Math.round(19 * Theme.scaleFactor)
                                                        radius: height / 2
                                                        color: "#dd0f172a"
                                                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                                                        border.width: 1

                                                        Text {
                                                            id: badgeLbl
                                                            anchors.centerIn: parent
                                                            width: parent.width - 8
                                                            text: model.badge || ""
                                                            color: Theme.accent
                                                            font.pixelSize: Math.round(8.2 * Theme.scaleFactor)
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                            horizontalAlignment: Text.AlignHCenter
                                                        }
                                                    }

                                                    // Top-Right HDR Badge
                                                    Rectangle {
                                                        visible: model.is_hdr === true
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.margins: 6
                                                        implicitWidth: hubHdrTxt.implicitWidth + 8
                                                        implicitHeight: Math.round(15 * Theme.scaleFactor)
                                                        radius: Math.round(3 * Theme.scaleFactor)
                                                        color: "#d91e293b"
                                                        border.color: "#e2e8f0"
                                                        border.width: 1

                                                        Text {
                                                            id: hubHdrTxt
                                                            anchors.centerIn: parent
                                                            text: "HDR"
                                                            color: "#f8fafc"
                                                            font.pixelSize: Math.round(7.5 * Theme.scaleFactor)
                                                            font.bold: true
                                                        }
                                                    }

                                                    // Dimmed Overlay + Elegant White "WATCHED" Typography when a Recently Added Card is completed!
                                                    Rectangle {
                                                        visible: model.is_recently_added_card === true && model.is_watched === true
                                                        anchors.fill: parent
                                                        radius: parent.radius
                                                        color: "#aa09090d"

                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            implicitWidth: watchedTypography.implicitWidth + Math.round(20 * Theme.scaleFactor)
                                                            implicitHeight: Math.round(28 * Theme.scaleFactor)
                                                            radius: Math.round(6 * Theme.scaleFactor)
                                                            color: "#40000000"
                                                            border.color: "#ccffffff"
                                                            border.width: 1.2

                                                            Text {
                                                                id: watchedTypography
                                                                anchors.centerIn: parent
                                                                text: "WATCHED"
                                                                color: "#ffffff"
                                                                font.pixelSize: Math.round(11 * Theme.scaleFactor)
                                                                font.bold: true
                                                                font.letterSpacing: 2.4
                                                            }
                                                        }
                                                    }

                                                    // Airing Linked Indicator Pill (Bottom-Left)
                                                    Rectangle {
                                                        visible: model.is_airing_card === true && model.linked_path !== undefined && model.linked_path !== ""
                                                        anchors.left: parent.left
                                                        anchors.bottom: parent.bottom
                                                        anchors.leftMargin: 6
                                                        anchors.bottomMargin: 15
                                                        implicitWidth: linkedBadgeTxt.implicitWidth + 10
                                                        implicitHeight: Math.round(16 * Theme.scaleFactor)
                                                        radius: height / 2
                                                        color: "#d9064e3b"
                                                        border.color: "#10b981"
                                                        border.width: 1

                                                        Text {
                                                            id: linkedBadgeTxt
                                                            anchors.centerIn: parent
                                                            text: "🔗 Linked"
                                                            color: "#6ee7b7"
                                                            font.pixelSize: Math.round(7.5 * Theme.scaleFactor)
                                                            font.bold: true
                                                        }
                                                    }

                                                    // Quick Increment (+1) & Decrement (-1) Episode Stepper Pill on Airing Cards (Bottom-Right)
                                                    Rectangle {
                                                        visible: model.is_airing_card === true && (hubCardMouse.containsMouse || decEpMouse.containsMouse || incEpMouse.containsMouse || hubCard.isCardSel)
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: 6
                                                        anchors.bottomMargin: 14
                                                        z: 20
                                                        width: Math.round(68 * Theme.scaleFactor)
                                                        height: Math.round(22 * Theme.scaleFactor)
                                                        radius: height / 2
                                                        color: "#e6111827"
                                                        border.color: "#8838bdf8"
                                                        border.width: 1

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 2
                                                            anchors.rightMargin: 2
                                                            spacing: 0

                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.fillHeight: true
                                                                radius: height / 2
                                                                color: decEpMouse.containsMouse ? "#45f87171" : "transparent"
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "−"
                                                                    color: "#f8fafc"
                                                                    font.pixelSize: Math.round(11 * Theme.scaleFactor)
                                                                    font.bold: true
                                                                }
                                                                MouseArea {
                                                                    id: decEpMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        if (backend && model.airing_id) {
                                                                            backend.adjustAiringEpisode(model.airing_id, -1)
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 1
                                                                Layout.fillHeight: true
                                                                Layout.topMargin: 4
                                                                Layout.bottomMargin: 4
                                                                color: "#35ffffff"
                                                            }

                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                Layout.fillHeight: true
                                                                radius: height / 2
                                                                color: incEpMouse.containsMouse ? "#4510b981" : "transparent"
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "＋"
                                                                    color: "#34d399"
                                                                    font.pixelSize: Math.round(10 * Theme.scaleFactor)
                                                                    font.bold: true
                                                                }
                                                                MouseArea {
                                                                    id: incEpMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        if (backend && model.airing_id) {
                                                                            backend.adjustAiringEpisode(model.airing_id, 1)
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Sleek Pill-Rounded Progress Bar floating cleanly near bottom of Poster
                                                    Rectangle {
                                                        visible: model.progress !== undefined && model.progress > 0.005
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        anchors.bottomMargin: 7
                                                        height: Math.round(5.5 * Theme.scaleFactor)
                                                        radius: height / 2
                                                        color: "#8809090b"
                                                        border.color: "#28ffffff"
                                                        border.width: 1
                                                        clip: true

                                                        Rectangle {
                                                            width: Math.max(parent.height, parent.width * Math.min(1.0, Math.max(0.0, model.progress)))
                                                            height: parent.height
                                                            radius: height / 2
                                                            gradient: Gradient {
                                                                orientation: Gradient.Horizontal
                                                                GradientStop { position: 0.0; color: model.is_watched ? "#10b981" : Theme.accent }
                                                                GradientStop { position: 1.0; color: model.is_watched ? "#34d399" : Theme.accent }
                                                            }
                                                            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        }
                                                    }
                                                }
                                            }

                                            // Title & Episode/Batch Subtitle
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

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
                                                    text: model.subtitle || model.name
                                                    color: model.is_airing_card === true
                                                           ? (model.is_going_tight === true ? "#34d399" : "#fbbf24")
                                                           : Theme.textTertiary
                                                    font.bold: model.is_airing_card === true
                                                    font.pixelSize: Math.round(8.8 * Theme.scaleFactor)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: hubCardMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                            cursorShape: Qt.PointingHandCursor

                                            onPressed: function(mouse) {
                                                if (!backend || !model.path) return
                                                var swapped = backend.swapMouseButtons
                                                var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                                if (isPrimary && mouse.modifiers === Qt.NoModifier && !hubCard.isCardSel) {
                                                    backend.selectItem(
                                                        model.path || "",
                                                        model.name || "",
                                                        Boolean(model.is_dir),
                                                        model.size || "",
                                                        model.modified || "",
                                                        model.type || "",
                                                        0
                                                    )
                                                }
                                            }

                                            onClicked: function(mouse) {
                                                if (!backend || !model.path) return
                                                if (mouse.button === Qt.MiddleButton) {
                                                    if (model.is_dir) {
                                                        backend.addTab(model.path)
                                                    } else if (!model.is_airing_card) {
                                                        backend.goToParentFolder(model.path)
                                                    }
                                                    return
                                                }
                                                var swapped = backend.swapMouseButtons
                                                var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                                var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

                                                backend.selectItem(
                                                    model.path || "",
                                                    model.name || "",
                                                    Boolean(model.is_dir),
                                                    model.size || "",
                                                    model.modified || "",
                                                    model.type || "",
                                                    mouse.modifiers
                                                )

                                                if (isSecondary) {
                                                    dolphinMenu.targetPath = model.path || ""
                                                    dolphinMenu.targetName = model.name || ""
                                                    dolphinMenu.isDir = Boolean(model.is_dir)
                                                    dolphinMenu.isAiringItem = Boolean(model.is_airing_card)
                                                    dolphinMenu.airingId = model.airing_id || ""
                                                    dolphinMenu.airingLinkedPath = model.linked_path || ""
                                                    dolphinMenu.popupSafe(hubCard, mouse.x, mouse.y)
                                                }
                                            }

                                            onDoubleClicked: function(mouse) {
                                                if (!backend || !model.path) return
                                                var swapped = backend.swapMouseButtons
                                                var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                                if (isPrimary) {
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

                // 1. Details List View
                ListView {
                    id: fileListView
                    anchors.fill: parent
                    visible: backend ? (backend.viewMode === "details" && !backend.isMediaHubView) : true
                    model: visible && backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.VerticalFlick
                    contentWidth: width
                    boundsBehavior: Flickable.StopAtBounds
                    pixelAligned: true
                    flickDeceleration: 4500
                    maximumFlickVelocity: 14000
                    focus: true

                    // Rubber-Band Marquee Selection + Empty Space Click Handler for ListView
                    Rectangle {
                        id: listRubberBand
                        parent: fileListView.contentItem
                        visible: false
                        z: 999
                        color: "#280078d4"
                        border.color: Theme.accent
                        border.width: 1
                        radius: 4
                    }

                    MouseArea {
                        id: listBgMarqueeArea
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true

                        property real startContentX: 0
                        property real startContentY: 0
                        property bool isMarqueeActive: false

                        onPressed: function(mouse) {
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                            if (isPrimary) {
                                startContentX = mouse.x + fileListView.contentX
                                startContentY = mouse.y + fileListView.contentY
                                isMarqueeActive = false
                                if (!(mouse.modifiers & Qt.ControlModifier)) {
                                    backend.clearSelection()
                                }
                            }
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed || !backend) return
                            var swapped = backend.swapMouseButtons
                            var primaryBtn = swapped ? Qt.RightButton : Qt.LeftButton
                            if (!(mouse.buttons & primaryBtn)) return

                            var curX = mouse.x + fileListView.contentX
                            var curY = mouse.y + fileListView.contentY
                            if (!isMarqueeActive && (Math.abs(curX - startContentX) > 6 || Math.abs(curY - startContentY) > 6)) {
                                isMarqueeActive = true
                                listRubberBand.visible = true
                            }
                            if (isMarqueeActive) {
                                if (mouse.y > fileListView.height - 24) {
                                    fileListView.contentY = Math.min(Math.max(0, fileListView.contentHeight - fileListView.height), fileListView.contentY + 14)
                                } else if (mouse.y < 24) {
                                    fileListView.contentY = Math.max(0, fileListView.contentY - 14)
                                }
                                curY = mouse.y + fileListView.contentY
                                var rx = Math.min(startContentX, curX)
                                var ry = Math.min(startContentY, curY)
                                var rw = Math.abs(curX - startContentX)
                                var rh = Math.abs(curY - startContentY)
                                listRubberBand.x = rx
                                listRubberBand.y = ry
                                listRubberBand.width = rw
                                listRubberBand.height = rh

                                var total = fileListView.count
                                if (total > 0) {
                                    var avgH = fileListView.contentHeight / total
                                    var firstIdx = Math.max(0, Math.floor(ry / Math.max(1, avgH)))
                                    var lastIdx = Math.min(total - 1, Math.floor((ry + rh) / Math.max(1, avgH)))
                                    var indices = []
                                    for (var i = firstIdx; i <= lastIdx; i++) {
                                        indices.push(i)
                                    }
                                    backend.setRubberBandSelection(indices, Boolean(mouse.modifiers & Qt.ControlModifier))
                                }
                            }
                        }

                        onReleased: function(mouse) {
                            if (isMarqueeActive) {
                                isMarqueeActive = false
                                listRubberBand.visible = false
                                return
                            }
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)
                            if (isSecondary) {
                                backgroundMenu.popup()
                            }
                        }

                        onCanceled: {
                            isMarqueeActive = false
                            listRubberBand.visible = false
                        }
                    }

                    WheelHandler {
                        id: listFastWheel
                        target: null
                        orientation: Qt.Vertical
                        onWheel: function(event) {
                            fileListView.cancelFlick()
                            var step = (event.angleDelta.y / 120.0) * Math.round(960 * Theme.scaleFactor)
                            var maxY = Math.max(0, fileListView.contentHeight - fileListView.height)
                            fileListView.contentY = Math.max(0, Math.min(maxY, fileListView.contentY - step))
                            event.accepted = true
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: rowContainer
                        width: fileListView.width
                        readonly property bool isSeriesFolderWithPoster: (backend ? (backend.isMediaLibraryView && !backend.isMovieFolderView && backend.showSeriesPosters) : false) && model.is_dir && model.poster !== undefined && model.poster !== ""
                        readonly property bool isMovieRow: ((backend ? backend.isMovieFolderView : false) && model.is_movie_item && (model.type === "Video" || (model.is_dir && model.poster !== ""))) || isSeriesFolderWithPoster
                        readonly property bool isAnalyzerRow: backend ? backend.isStorageAnalyzerView : false
                        readonly property bool isMediaVideoRow: ((backend ? backend.isMediaLibraryView : false) && !model.is_dir && model.type === "Video") || isMovieRow
                        readonly property bool showMovieSeparator: isMovieRow
                        height: Math.round((isMovieRow ? 124 : (isMediaVideoRow ? 72 : (isAnalyzerRow ? 48 : 38))) * Theme.scaleFactor)

                        readonly property string itemPath: model.path
                        readonly property bool itemIsDir: model.is_dir
                        readonly property bool isHiddenEntry: model.name !== undefined && model.name.startsWith(".")
                        opacity: isHiddenEntry ? 0.52 : 1.0

                        Component.onCompleted: {
                            if (!backend) return
                            if (model.is_dir) {
                                backend.requestFolderPreview(model.path)
                            } else if (model.thumb === "") {
                                backend.requestItemThumbnail(model.path)
                            }
                        }

                        // Movie Separator Line (Placed cleanly between movie items when folder is marked as Movie Mode)
                        Rectangle {
                            visible: rowContainer.showMovieSeparator && index > 0
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            height: 1
                            color: "#38ffffff"
                        }

                        Rectangle {
                            id: rowDelegate
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: rowContainer.showMovieSeparator ? 9 : 1
                            anchors.bottomMargin: rowContainer.showMovieSeparator ? 9 : 1
                            radius: Theme.radiusMedium

                            readonly property bool isSelected: {
                                if (!backend) return false
                                var sList = backend.selectedPaths
                                if (sList && sList.indexOf(model.path) !== -1) return true
                                return (backend.selectedItem && backend.selectedItem.path === model.path) ? true : false
                            }
                            readonly property bool isDropHovered: model.is_dir && root.hoveredSubfolderPath === model.path
                            color: isDropHovered ? "#350078d4" : (isSelected ? Theme.bgSelected : (itemArea.containsMouse ? Theme.bgHover : "transparent"))
                            border.color: isDropHovered || isSelected ? Theme.accent : "transparent"
                            border.width: isDropHovered ? 2 : (isSelected ? 1 : 0)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Item {
                                    readonly property bool hasVerticalPoster: rowContainer.isMovieRow && model.poster !== undefined && model.poster !== ""
                                    implicitWidth: Math.round((hasVerticalPoster ? 70 : (rowContainer.isMovieRow ? 110 : (rowContainer.isMediaVideoRow ? 92 : 24))) * Theme.scaleFactor)
                                    implicitHeight: Math.round((hasVerticalPoster ? 102 : (rowContainer.isMovieRow ? 76 : (rowContainer.isMediaVideoRow ? 54 : 24))) * Theme.scaleFactor)

                                    FolderPreviewIcon {
                                        anchors.fill: parent
                                        visible: model.is_dir && !parent.hasVerticalPoster
                                        previews: model.folder_previews
                                    }

                                    Item {
                                        id: listThumbFrame
                                        anchors.fill: parent
                                        visible: parent.hasVerticalPoster || (!model.is_dir && (model.thumb !== "" || (model.icon && (model.icon.indexOf("/") !== -1 || model.icon.indexOf(".") !== -1))))

                                        Image {
                                            anchors.fill: parent
                                            source: parent.visible
                                                    ? (parent.parent.hasVerticalPoster
                                                       ? ("file://" + model.poster)
                                                       : (model.thumb !== "" ? ("file://" + model.thumb) : ("file://" + model.icon)))
                                                    : ""
                                            fillMode: parent.parent.hasVerticalPoster ? Image.PreserveAspectFit : (rowContainer.isMediaVideoRow ? Image.PreserveAspectCrop : Image.PreserveAspectFit)
                                            asynchronous: true
                                            smooth: true
                                            mipmap: true
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !model.is_dir && !listThumbFrame.visible
                                        text: model.icon
                                        font.pixelSize: Theme.fontSizeIcon
                                    }
                                }

                                // Episode Number Badge (Shown before title in Series/Anime Media Library, hidden for Movies)
                                Rectangle {
                                    visible: rowContainer.isMediaVideoRow && !model.is_movie_item && model.episode_num !== ""
                                    implicitWidth: Math.max(Math.round(32 * Theme.scaleFactor), epNumTxt.implicitWidth + 12)
                                    implicitHeight: Math.round(22 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: model.is_watched ? "#1f10b981" : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                    border.color: model.is_watched ? "#4010b981" : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                                    border.width: 1
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        id: epNumTxt
                                        anchors.centerIn: parent
                                        text: model.episode_num
                                        color: model.is_watched ? "#34d399" : Theme.accent
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                    }
                                }

                                // Title + Sleek Thin Progress Bar Column
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: rowContainer.isMediaVideoRow ? 5 : 0

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: rowContainer.isMovieRow ? 3 : 1

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (rowContainer.isMediaVideoRow && model.episode_title && model.episode_title !== "")
                                                          ? model.episode_title
                                                          : model.name
                                                    color: (rowContainer.isMediaVideoRow && model.is_watched) ? Theme.textSecondary : Theme.textPrimary
                                                    font.pixelSize: rowContainer.isMovieRow ? Theme.fontSizeMedium : Theme.fontSizeNormal
                                                    font.bold: rowDelegate.isSelected || rowContainer.isMediaVideoRow
                                                    horizontalAlignment: Text.AlignLeft
                                                    elide: Text.ElideRight
                                                }

                                                // Movie / Episode Rating Pill (e.g. ⭐ 8.6)
                                                Rectangle {
                                                    visible: rowContainer.isMediaVideoRow && model.rating !== undefined && model.rating !== ""
                                                    implicitWidth: ratingBadgeTxt.implicitWidth + 10
                                                    implicitHeight: Math.round(17 * Theme.scaleFactor)
                                                    radius: Theme.radiusSmall
                                                    color: "#22fbbf24"
                                                    border.color: "#66fbbf24"
                                                    border.width: 1

                                                    Text {
                                                        id: ratingBadgeTxt
                                                        anchors.centerIn: parent
                                                        text: "⭐ " + model.rating
                                                        color: "#fbbf24"
                                                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                        font.bold: true
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: rowContainer.isMediaVideoRow && model.episode_title !== undefined && model.episode_title !== "" && model.episode_title !== model.name
                                                Layout.fillWidth: true
                                                text: model.name
                                                color: Theme.textTertiary
                                                font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                                horizontalAlignment: Text.AlignLeft
                                                elide: Text.ElideMiddle
                                            }

                                            // Movie Synopsis Preview directly inside the Movie Row
                                            Text {
                                                visible: rowContainer.isMovieRow && model.overview !== undefined && model.overview !== ""
                                                Layout.fillWidth: true
                                                text: model.overview || ""
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                                horizontalAlignment: Text.AlignLeft
                                                maximumLineCount: 2
                                                wrapMode: Text.WordWrap
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // "NEW" Badge (Added within last 7 days and not yet finished)
                                        Rectangle {
                                            visible: rowContainer.isMediaVideoRow && model.is_new && !model.is_watched
                                            implicitWidth: newLabel.implicitWidth + 10
                                            implicitHeight: Math.round(17 * Theme.scaleFactor)
                                            radius: Theme.radiusSmall
                                            color: "#22f59e0b"
                                            border.color: "#f59e0b"
                                            border.width: 1

                                            Text {
                                                id: newLabel
                                                anchors.centerIn: parent
                                                text: "NEW"
                                                color: "#fbbf24"
                                                font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                font.bold: true
                                            }
                                        }

                                        // Sleek Thin Silver Rectangle "HDR" Badge on the right side
                                        Rectangle {
                                            visible: rowContainer.isMediaVideoRow && model.is_hdr
                                            implicitWidth: hdrLabel.implicitWidth + Math.round(10 * Theme.scaleFactor)
                                            implicitHeight: Math.round(16 * Theme.scaleFactor)
                                            radius: Math.round(3 * Theme.scaleFactor)
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "#28e2e8f0" }
                                                GradientStop { position: 1.0; color: "#1294a3b8" }
                                            }
                                            border.color: "#e2e8f0"
                                            border.width: 1

                                            Text {
                                                id: hdrLabel
                                                anchors.centerIn: parent
                                                text: "HDR"
                                                color: "#f1f5f9"
                                                font.pixelSize: Math.round(8 * Theme.scaleFactor)
                                                font.bold: true
                                                font.letterSpacing: 0.8
                                            }
                                        }

                                        // Elegant Custom Vector Checkmark Badge (Not an emoji!)
                                        Rectangle {
                                            visible: rowContainer.isMediaVideoRow && model.is_watched
                                            width: Math.round(18 * Theme.scaleFactor)
                                            height: Math.round(18 * Theme.scaleFactor)
                                            radius: width / 2
                                            color: "#10b981"
                                            border.color: "#34d399"
                                            border.width: 1

                                            Canvas {
                                                anchors.fill: parent
                                                onPaint: {
                                                    var ctx = getContext("2d")
                                                    ctx.reset()
                                                    ctx.strokeStyle = "#ffffff"
                                                    ctx.lineWidth = Math.max(1.8, width * 0.12)
                                                    ctx.lineCap = "round"
                                                    ctx.lineJoin = "round"
                                                    ctx.beginPath()
                                                    ctx.moveTo(width * 0.27, height * 0.52)
                                                    ctx.lineTo(width * 0.44, height * 0.70)
                                                    ctx.lineTo(width * 0.75, height * 0.32)
                                                    ctx.stroke()
                                                }
                                            }
                                        }
                                    }

                                    // Sleek Thin Progress Bar right under the episode/movie name (hidden for folder items)
                                    Rectangle {
                                        visible: rowContainer.isMediaVideoRow && !model.is_dir
                                        Layout.fillWidth: true
                                        height: Math.max(3, Math.round(3.5 * Theme.scaleFactor))
                                        radius: height / 2
                                        color: "#28ffffff"
                                        clip: true

                                        Rectangle {
                                            width: parent.width * Math.min(1.0, Math.max(0.0, model.progress))
                                            height: parent.height
                                            radius: parent.radius
                                            color: model.is_watched ? "#10b981" : Theme.accent
                                        }
                                    }

                                    // Storage Analyzer Visual Usage Bar & Percentage
                                    RowLayout {
                                        visible: rowContainer.isAnalyzerRow
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Math.round(5 * Theme.scaleFactor)
                                            radius: height / 2
                                            color: "#22ffffff"
                                            clip: true

                                            Rectangle {
                                                width: parent.width * Math.min(1.0, Math.max(0.015, model.size_ratio !== undefined ? model.size_ratio : 0.0))
                                                height: parent.height
                                                radius: parent.radius
                                                color: (model.size_ratio !== undefined && model.size_ratio > 0.50)
                                                       ? "#f87171"
                                                       : ((model.size_ratio !== undefined && model.size_ratio > 0.20) ? "#f59e0b" : "#38bdf8")
                                            }
                                        }

                                        Text {
                                            text: model.percent_str !== undefined ? model.percent_str : ""
                                            color: Theme.textSecondary
                                            font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                            font.bold: true
                                            Layout.preferredWidth: Math.round(42 * Theme.scaleFactor)
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                Text {
                                    visible: root.showModifiedCol
                                    Layout.preferredWidth: Math.round(135 * Theme.scaleFactor)
                                    text: model.modified
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: root.showSizeCol
                                    Layout.preferredWidth: Math.round(80 * Theme.scaleFactor)
                                    text: model.size
                                    horizontalAlignment: Text.AlignRight
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                preventStealing: true

                                property point pressPos: Qt.point(0, 0)
                                property bool isHoldingDrag: false
                                property bool isReorderingFav: false

                                onPressed: function(mouse) {
                                    fileListView.cancelFlick()
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    isHoldingDrag = false
                                    isReorderingFav = false

                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)

                                    if (isPrimary && mouse.modifiers === Qt.NoModifier && !rowDelegate.isSelected) {
                                        backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                    }
                                }

                                onPositionChanged: function(mouse) {
                                    if (!backend) return
                                    var gPos = itemArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    var swapped = backend.swapMouseButtons
                                    var primaryBtn = swapped ? Qt.RightButton : Qt.LeftButton

                                    if ((mouse.buttons & primaryBtn) && backend.currentPath === "favorites://") {
                                        if (!isReorderingFav && Math.abs(dy) > 8) {
                                            isReorderingFav = true
                                        }
                                        if (isReorderingFav) {
                                            var listPt = fileListView.mapFromGlobal(gPos.x, gPos.y)
                                            var targetIdx = fileListView.indexAt(listPt.x + fileListView.contentX, listPt.y + fileListView.contentY)
                                            if (targetIdx >= 0 && targetIdx !== index) {
                                                backend.moveFavoriteItem(index, targetIdx)
                                            }
                                        }
                                    } else if (mouse.buttons & primaryBtn) {
                                        if (!isHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            isHoldingDrag = true
                                            if (!rowDelegate.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                            }
                                            backend.startSystemDrag(model.path, model.name, model.icon)
                                            isHoldingDrag = false
                                        }
                                    }
                                }

                                onReleased: function(mouse) {
                                    if (!backend) return
                                    if (mouse.button === Qt.MiddleButton && model.is_dir) {
                                        backend.addTab(model.path)
                                        return
                                    }

                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

                                    if (isPrimary) {
                                        if (!isReorderingFav && (mouse.modifiers !== Qt.NoModifier || backend.selectedPaths.length > 1 || !rowDelegate.isSelected)) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                        }
                                        isReorderingFav = false
                                    } else if (isSecondary) {
                                        if (!isHoldingDrag) {
                                            if (!rowDelegate.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                            }
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.isAiringItem = false
                                            dolphinMenu.airingId = ""
                                            dolphinMenu.airingLinkedPath = ""
                                            dolphinMenu.popupSafe(itemArea, mouse.x, mouse.y)
                                        }
                                        isHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isReorderingFav = false
                                    isHoldingDrag = false
                                }

                                onDoubleClicked: function(mouse) {
                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    if (isPrimary) {
                                        backend.openEntry(model.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Dynamic Adaptive Grid View (Supports "floating" and "cards" styles + File Explorer Folder Previews)
                GridView {
                    id: fileGridView
                    anchors.fill: parent
                    visible: backend ? (backend.viewMode === "grid" && !backend.isMediaHubView) : false
                    model: visible && backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.VerticalFlick
                    contentWidth: width
                    boundsBehavior: Flickable.StopAtBounds
                    pixelAligned: true
                    flickDeceleration: 4500
                    maximumFlickVelocity: 14000
                    focus: true

                    // Rubber-Band Marquee Selection + Empty Space Click Handler for GridView
                    Rectangle {
                        id: gridRubberBand
                        parent: fileGridView.contentItem
                        visible: false
                        z: 999
                        color: "#280078d4"
                        border.color: Theme.accent
                        border.width: 1
                        radius: 4
                    }

                    MouseArea {
                        id: gridBgMarqueeArea
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true

                        property real startContentX: 0
                        property real startContentY: 0
                        property bool isMarqueeActive: false

                        onPressed: function(mouse) {
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                            if (isPrimary) {
                                startContentX = mouse.x + fileGridView.contentX
                                startContentY = mouse.y + fileGridView.contentY
                                isMarqueeActive = false
                                if (!(mouse.modifiers & Qt.ControlModifier)) {
                                    backend.clearSelection()
                                }
                            }
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed || !backend) return
                            var swapped = backend.swapMouseButtons
                            var primaryBtn = swapped ? Qt.RightButton : Qt.LeftButton
                            if (!(mouse.buttons & primaryBtn)) return

                            var curX = mouse.x + fileGridView.contentX
                            var curY = mouse.y + fileGridView.contentY
                            if (!isMarqueeActive && (Math.abs(curX - startContentX) > 6 || Math.abs(curY - startContentY) > 6)) {
                                isMarqueeActive = true
                                gridRubberBand.visible = true
                            }
                            if (isMarqueeActive) {
                                if (mouse.y > fileGridView.height - 24) {
                                    fileGridView.contentY = Math.min(Math.max(0, fileGridView.contentHeight - fileGridView.height), fileGridView.contentY + 16)
                                } else if (mouse.y < 24) {
                                    fileGridView.contentY = Math.max(0, fileGridView.contentY - 16)
                                }
                                curY = mouse.y + fileGridView.contentY
                                var rx = Math.min(startContentX, curX)
                                var ry = Math.min(startContentY, curY)
                                var rw = Math.abs(curX - startContentX)
                                var rh = Math.abs(curY - startContentY)
                                gridRubberBand.x = rx
                                gridRubberBand.y = ry
                                gridRubberBand.width = rw
                                gridRubberBand.height = rh

                                var cols = Math.max(1, fileGridView.targetCols)
                                var cw = Math.max(1, fileGridView.cellWidth)
                                var ch = Math.max(1, fileGridView.cellHeight)
                                var cStart = Math.max(0, Math.floor(rx / cw))
                                var cEnd = Math.min(cols - 1, Math.floor((rx + rw) / cw))
                                var rStart = Math.max(0, Math.floor(ry / ch))
                                var rEnd = Math.floor((ry + rh) / ch)
                                var total = fileGridView.count
                                var indices = []
                                for (var r = rStart; r <= rEnd; r++) {
                                    for (var c = cStart; c <= cEnd; c++) {
                                        var idx = r * cols + c
                                        if (idx >= 0 && idx < total) {
                                            indices.push(idx)
                                        }
                                    }
                                }
                                backend.setRubberBandSelection(indices, Boolean(mouse.modifiers & Qt.ControlModifier))
                            }
                        }

                        onReleased: function(mouse) {
                            if (isMarqueeActive) {
                                isMarqueeActive = false
                                gridRubberBand.visible = false
                                return
                            }
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)
                            if (isSecondary) {
                                backgroundMenu.popup()
                            }
                        }

                        onCanceled: {
                            isMarqueeActive = false
                            gridRubberBand.visible = false
                        }
                    }

                    WheelHandler {
                        id: gridFastWheel
                        target: null
                        orientation: Qt.Vertical
                        onWheel: function(event) {
                            fileGridView.cancelFlick()
                            var step = (event.angleDelta.y / 120.0) * Math.round(1040 * Theme.scaleFactor)
                            var maxY = Math.max(0, fileGridView.contentHeight - fileGridView.height)
                            fileGridView.contentY = Math.max(0, Math.min(maxY, fileGridView.contentY - step))
                            event.accepted = true
                        }
                    }

                    readonly property bool isMoviePosterGrid: backend ? (backend.isMovieFolderView || (backend.isMediaLibraryView && backend.showSeriesPosters)) : false
                    readonly property int minCardSize: Math.round((isMoviePosterGrid ? 165 : 145) * Theme.scaleFactor)
                    readonly property int targetCols: (backend && backend.gridColumns > 0) ? backend.gridColumns : Math.max(1, Math.floor(fileGridView.width / minCardSize))
                    cellWidth: Math.max(Math.round(115 * Theme.scaleFactor), Math.floor(fileGridView.width / Math.max(1, targetCols)))
                    cellHeight: Math.round(cellWidth * (isMoviePosterGrid ? 1.44 : 1.02))

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }
                    ScrollBar.horizontal: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: gridContainer
                        width: fileGridView.cellWidth
                        height: fileGridView.cellHeight

                        readonly property string itemPath: model.path
                        readonly property bool itemIsDir: model.is_dir
                        readonly property bool isHiddenEntry: model.name !== undefined && model.name.startsWith(".")
                        opacity: isHiddenEntry ? 0.52 : 1.0
                        readonly property bool isSelected: {
                            if (!backend) return false
                            var sList = backend.selectedPaths
                            if (sList && sList.indexOf(model.path) !== -1) return true
                            return (backend.selectedItem && backend.selectedItem.path === model.path) ? true : false
                        }
                        readonly property bool isFloatingStyle: backend ? (backend.gridStyle === "floating") : true
                        readonly property bool hasMoviePoster: model.poster !== undefined && model.poster !== "" && (!model.is_dir || (backend && backend.showSeriesPosters))
                        readonly property bool hasMediaThumb: hasMoviePoster || (!model.is_dir && (model.thumb !== "" || (model.icon && (model.icon.indexOf("/") !== -1 || model.icon.indexOf(".") !== -1))))

                        Component.onCompleted: {
                            if (!backend) return
                            if (model.is_dir) {
                                backend.requestFolderPreview(model.path)
                            } else if (model.thumb === "") {
                                backend.requestItemThumbnail(model.path)
                            }
                        }

                        // Card Frame (In "floating" mode, background is transparent and hugs the actual preview!)
                        Rectangle {
                            id: gridDelegate
                            width: fileGridView.cellWidth - 10
                            height: fileGridView.cellHeight - 10
                            anchors.centerIn: parent
                            radius: Theme.radiusLarge

                            readonly property bool isDropHovered: model.is_dir && root.hoveredSubfolderPath === model.path

                            color: isDropHovered
                                   ? "#380078d4"
                                   : (gridContainer.isFloatingStyle
                                      ? (gridContainer.isSelected ? "#280078d4" : (gridMouseArea.containsMouse ? "#1affffff" : "transparent"))
                                      : (gridContainer.isSelected ? Theme.bgSelected : (gridMouseArea.containsMouse ? Theme.bgHover : Theme.bgCard)))
                            border.color: isDropHovered || gridContainer.isSelected
                                          ? Theme.accent
                                          : (gridContainer.isFloatingStyle ? (gridMouseArea.containsMouse ? "#35ffffff" : "transparent") : Theme.borderDim)
                            border.width: isDropHovered || gridContainer.isSelected ? 2 : 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: gridContainer.isFloatingStyle ? 6 : 8
                                spacing: 6

                                // Preview Viewport Area
                                Item {
                                    id: previewSlot
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    // A) File Explorer Style Folder Preview (Videos -> Images -> Texts)
                                    FolderPreviewIcon {
                                        visible: model.is_dir && !gridContainer.hasMoviePoster
                                        width: Math.min(parent.width * 0.88, parent.height * 0.96)
                                        height: width * 0.88
                                        anchors.centerIn: parent
                                        previews: model.folder_previews
                                        isSelected: gridContainer.isSelected
                                    }

                                    // B) Image / Video Thumbnail or Vertical Movie Poster with Dynamic Aspect-Ratio Wrapping Frame
                                    Item {
                                        visible: gridContainer.hasMoviePoster || (!model.is_dir && gridContainer.hasMediaThumb)
                                        anchors.fill: parent

                                        Image {
                                            id: thumbImg
                                            anchors.centerIn: parent
                                            width: parent.width
                                            height: parent.height
                                            source: parent.visible
                                                    ? (gridContainer.hasMoviePoster
                                                       ? ("file://" + model.poster)
                                                       : (model.thumb !== "" ? ("file://" + model.thumb) : ("file://" + model.icon)))
                                                    : ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            mipmap: true
                                        }

                                        // Tightly hugs the actual painted image dimensions (no border around pre-rounded posters unless selected!)
                                        Rectangle {
                                            anchors.centerIn: thumbImg
                                            width: thumbImg.paintedWidth > 0 ? thumbImg.paintedWidth : 0
                                            height: thumbImg.paintedHeight > 0 ? thumbImg.paintedHeight : 0
                                            radius: Math.round(8 * Theme.scaleFactor)
                                            color: "transparent"
                                            border.color: gridContainer.isSelected ? Theme.accent : "transparent"
                                            border.width: gridContainer.isSelected ? 2 : 0
                                            visible: thumbImg.status === Image.Ready

                                            // Sleek Thin Silver HDR Badge on Grid Thumbnail
                                            Rectangle {
                                                visible: model.type === "Video" && model.is_hdr
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 5
                                                implicitWidth: gridHdrTxt.implicitWidth + Math.round(8 * Theme.scaleFactor)
                                                implicitHeight: Math.round(15 * Theme.scaleFactor)
                                                radius: Math.round(3 * Theme.scaleFactor)
                                                color: "#cc1e293b"
                                                border.color: "#e2e8f0"
                                                border.width: 1

                                                Text {
                                                    id: gridHdrTxt
                                                    anchors.centerIn: parent
                                                    text: "HDR"
                                                    color: "#f8fafc"
                                                    font.pixelSize: Math.round(7.5 * Theme.scaleFactor)
                                                    font.bold: true
                                                    font.letterSpacing: 0.7
                                                }
                                            }

                                            // Video Indicator Pill on Thumbnail
                                            Rectangle {
                                                visible: model.type === "Video"
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.margins: 5
                                                width: Math.round(22 * Theme.scaleFactor)
                                                height: Math.round(22 * Theme.scaleFactor)
                                                radius: width / 2
                                                color: "#cc000000"
                                                border.color: "#60ffffff"
                                                border.width: 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "▶"
                                                    color: "#ffffff"
                                                    font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                                }
                                            }
                                        }
                                    }

                                    // C) Generic File Icon Card
                                    Rectangle {
                                        visible: !model.is_dir && !gridContainer.hasMediaThumb
                                        width: Math.min(parent.width * 0.72, parent.height * 0.82)
                                        height: width * 1.12
                                        anchors.centerIn: parent
                                        radius: Theme.radiusMedium
                                        color: Theme.bgSurface
                                        border.color: Theme.borderDim
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: model.icon
                                            font.pixelSize: Math.round(32 * Theme.scaleFactor)
                                        }
                                    }
                                }

                                // Label Pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: nameLabel.implicitHeight + 6
                                    color: gridContainer.isFloatingStyle && gridContainer.isSelected ? Theme.accent : "transparent"
                                    radius: Theme.radiusSmall

                                    Text {
                                        id: nameLabel
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        text: (model.episode_title !== undefined && model.episode_title !== "") ? model.episode_title : model.name
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: gridContainer.isSelected || gridContainer.hasMoviePoster
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                        maximumLineCount: 2
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                            }

                            MouseArea {
                                id: gridMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                preventStealing: true

                                property point pressPos: Qt.point(0, 0)
                                property bool isHoldingDrag: false
                                property bool isReorderingFav: false

                                onPressed: function(mouse) {
                                    fileGridView.cancelFlick()
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    isHoldingDrag = false
                                    isReorderingFav = false

                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)

                                    if (isPrimary && mouse.modifiers === Qt.NoModifier && !gridContainer.isSelected) {
                                        backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                    }
                                }

                                onPositionChanged: function(mouse) {
                                    if (!backend) return
                                    var gPos = gridMouseArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    var swapped = backend.swapMouseButtons
                                    var primaryBtn = swapped ? Qt.RightButton : Qt.LeftButton

                                    if ((mouse.buttons & primaryBtn) && backend.currentPath === "favorites://") {
                                        if (!isReorderingFav && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                                            isReorderingFav = true
                                        }
                                        if (isReorderingFav) {
                                            var gridPt = fileGridView.mapFromGlobal(gPos.x, gPos.y)
                                            var targetGridIdx = fileGridView.indexAt(gridPt.x + fileGridView.contentX, gridPt.y + fileGridView.contentY)
                                            if (targetGridIdx >= 0 && targetGridIdx !== index) {
                                                backend.moveFavoriteItem(index, targetGridIdx)
                                            }
                                        }
                                    } else if (mouse.buttons & primaryBtn) {
                                        if (!isHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            isHoldingDrag = true
                                            if (!gridContainer.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                            }
                                            backend.startSystemDrag(model.path, model.name, model.icon)
                                            isHoldingDrag = false
                                        }
                                    }
                                }

                                onReleased: function(mouse) {
                                    if (!backend) return
                                    if (mouse.button === Qt.MiddleButton && model.is_dir) {
                                        backend.addTab(model.path)
                                        return
                                    }

                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

                                    if (isPrimary) {
                                        if (!isReorderingFav && (mouse.modifiers !== Qt.NoModifier || backend.selectedPaths.length > 1 || !gridContainer.isSelected)) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                        }
                                        isReorderingFav = false
                                    } else if (isSecondary) {
                                        if (!isHoldingDrag) {
                                            if (!gridContainer.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                            }
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.isAiringItem = false
                                            dolphinMenu.airingId = ""
                                            dolphinMenu.airingLinkedPath = ""
                                            dolphinMenu.popupSafe(gridMouseArea, mouse.x, mouse.y)
                                        }
                                        isHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isReorderingFav = false
                                    isHoldingDrag = false
                                }

                                onDoubleClicked: function(mouse) {
                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    if (isPrimary) {
                                        backend.openEntry(model.path)
                                    }
                                }
                            }
                        }
                    }
                }
                    // Loading Overlay for Recently Added (recent://) or Storage Analyzer (analyzer://)
                    Rectangle {
                        anchors.fill: parent
                        visible: backend ? ((backend.currentPath === "recent://" && backend.isLoadingRecent) || (backend.isStorageAnalyzerView && backend.isAnalyzingStorage)) : false
                        color: Theme.bgBase
                        z: 50

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "⏳"
                                font.pixelSize: Math.round(34 * Theme.scaleFactor)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: (backend && backend.isStorageAnalyzerView) ? "📊 Analyzing Disk Usage..." : "Loading Recently Added Files..."
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeTitle
                                font.bold: true
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: (backend && backend.isStorageAnalyzerView)
                                      ? "Calculating recursive folder sizes and sorting largest first"
                                      : "Scanning monitored folders for the latest files"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
