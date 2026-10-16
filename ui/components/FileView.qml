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

    DolphinContextMenu {
        id: dolphinMenu
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
            enabled: backend ? (backend.getClipboardPath() !== "" && backend.currentPath !== "recent://" && backend.currentPath !== "trash://") : false
            onTriggered: {
                if (root.appWindow) {
                    root.appWindow.triggerPasteInCurrentFolder()
                } else if (backend) {
                    backend.pasteToFolder(backend.currentPath)
                }
            }
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
            text: "Refresh"
            shortcutText: "F5"
            onTriggered: backend.refresh()
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
            updateDragTargetState(drag)
        }

        onPositionChanged: function(drag) {
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

            var targetFolder = subPath !== "" ? subPath : backend.currentPath
            if (targetFolder === "recent://" || targetFolder === "trash://") return

            var urls = root.extractDropUrls(drop)
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

        // Search Results Overlay
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: backend && backend.searchResults ? backend.searchResults.length > 0 : false
            color: Theme.bgBase

            ListView {
                anchors.fill: parent
                model: backend ? backend.searchResults : []
                clip: true

                delegate: Rectangle {
                    width: ListView.view.width
                    height: Math.round(36 * Theme.scaleFactor)
                    color: sHover.containsMouse ? Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text { text: "🔍"; font.pixelSize: Theme.fontSizeNormal }
                        Text {
                            text: modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                            Layout.preferredWidth: Math.min(200, root.width * 0.35)
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.path
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                    }

                    MouseArea {
                        id: sHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                dolphinMenu.targetPath = modelData.path
                                dolphinMenu.targetName = modelData.name
                                dolphinMenu.isDir = modelData.is_dir
                                dolphinMenu.popup()
                            }
                        }
                        onDoubleClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
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

                // Table Header
                Rectangle {
                    Layout.fillWidth: true
                    height: Math.round(32 * Theme.scaleFactor)
                    color: Theme.bgSurface
                    visible: backend ? backend.viewMode === "details" : true

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

                // 1. Details List View
                ListView {
                    id: fileListView
                    anchors.fill: parent
                    visible: backend ? backend.viewMode === "details" : true
                    model: visible && backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    contentWidth: Math.max(width, Math.round(260 * Theme.scaleFactor))
                    boundsBehavior: Flickable.DragOverBounds
                    pixelAligned: true
                    flickDeceleration: 3200
                    maximumFlickVelocity: 9500
                    focus: true

                    WheelHandler {
                        id: listFastWheel
                        target: null
                        orientation: Qt.Vertical
                        onWheel: function(event) {
                            var step = (event.angleDelta.y / 120.0) * Math.round(135 * Theme.scaleFactor)
                            var maxY = Math.max(0, fileListView.contentHeight - fileListView.height)
                            fileListView.contentY = Math.max(0, Math.min(maxY, fileListView.contentY - step))
                            event.accepted = true
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }
                    ScrollBar.horizontal: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: rowContainer
                        width: Math.max(fileListView.width, fileListView.contentWidth)
                        readonly property bool isMediaVideoRow: (backend ? backend.isMediaLibraryView : false) && !model.is_dir && model.type === "Video"
                        readonly property bool showMovieSeparator: isMediaVideoRow && model.is_movie_item
                        height: Math.round((isMediaVideoRow ? (showMovieSeparator ? 84 : 72) : 38) * Theme.scaleFactor)

                        readonly property string itemPath: model.path
                        readonly property bool itemIsDir: model.is_dir

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
                                    implicitWidth: Math.round((rowContainer.isMediaVideoRow ? 92 : 24) * Theme.scaleFactor)
                                    implicitHeight: Math.round((rowContainer.isMediaVideoRow ? 54 : 24) * Theme.scaleFactor)

                                    FolderPreviewIcon {
                                        anchors.fill: parent
                                        visible: model.is_dir
                                        previews: model.folder_previews
                                    }

                                    Rectangle {
                                        id: listThumbFrame
                                        anchors.fill: parent
                                        radius: rowContainer.isMediaVideoRow ? Math.round(6 * Theme.scaleFactor) : 0
                                        color: rowContainer.isMediaVideoRow ? "#141418" : "transparent"
                                        border.color: rowContainer.isMediaVideoRow ? "#30ffffff" : "transparent"
                                        border.width: rowContainer.isMediaVideoRow ? 1 : 0
                                        clip: true
                                        visible: !model.is_dir && (model.thumb !== "" || (model.icon && (model.icon.indexOf("/") !== -1 || model.icon.indexOf(".") !== -1)))

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: rowContainer.isMediaVideoRow ? 1 : 0
                                            source: parent.visible ? (model.thumb !== "" ? ("file://" + model.thumb) : ("file://" + model.icon)) : ""
                                            fillMode: rowContainer.isMediaVideoRow ? Image.PreserveAspectCrop : Image.PreserveAspectFit
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
                                    color: model.is_watched ? "#1f10b981" : "#260078d4"
                                    border.color: model.is_watched ? "#4010b981" : "#550078d4"
                                    border.width: 1
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        id: epNumTxt
                                        anchors.centerIn: parent
                                        text: model.episode_num
                                        color: model.is_watched ? "#34d399" : "#38bdf8"
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

                                        Text {
                                            Layout.fillWidth: true
                                            text: model.name
                                            color: (rowContainer.isMediaVideoRow && model.is_watched) ? Theme.textSecondary : Theme.textPrimary
                                            font.pixelSize: Theme.fontSizeNormal
                                            font.bold: rowDelegate.isSelected || rowContainer.isMediaVideoRow
                                            elide: Text.ElideRight
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

                                    // Sleek Thin Progress Bar right under the episode/movie name
                                    Rectangle {
                                        visible: rowContainer.isMediaVideoRow
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
                                preventStealing: isHoldingDrag || isPanning

                                property point pressPos: Qt.point(0, 0)
                                property point lastGlobalPos: Qt.point(0, 0)
                                property bool isHoldingDrag: false
                                property bool isPanning: false

                                onPressed: function(mouse) {
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    lastGlobalPos = itemArea.mapToGlobal(mouse.x, mouse.y)
                                    isHoldingDrag = false
                                    isPanning = false
                                }

                                onPositionChanged: function(mouse) {
                                    if (!backend) return
                                    var gPos = itemArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    var swapped = backend.swapMouseButtons
                                    var panBtn = swapped ? Qt.RightButton : Qt.LeftButton
                                    var dragBtn = swapped ? Qt.LeftButton : Qt.RightButton

                                    if (mouse.buttons & panBtn) {
                                        if (!isPanning && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
                                            isPanning = true
                                        }
                                        if (isPanning) {
                                            var stepX = gPos.x - lastGlobalPos.x
                                            var stepY = gPos.y - lastGlobalPos.y
                                            var maxY = Math.max(0, fileListView.contentHeight - fileListView.height)
                                            var maxX = Math.max(0, fileListView.contentWidth - fileListView.width)
                                            fileListView.contentY = Math.max(0, Math.min(maxY, fileListView.contentY - stepY))
                                            fileListView.contentX = Math.max(0, Math.min(maxX, fileListView.contentX - stepX))
                                        }
                                    } else if (mouse.buttons & dragBtn) {
                                        if (!isHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            isHoldingDrag = true
                                            if (!rowDelegate.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                            }
                                            backend.startSystemDrag(model.path, model.name, model.icon)
                                            isHoldingDrag = false
                                        }
                                    }
                                    lastGlobalPos = gPos
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
                                        if (!isPanning) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                        }
                                        isPanning = false
                                    } else if (isSecondary) {
                                        if (!isHoldingDrag) {
                                            if (!rowDelegate.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                            }
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.popup()
                                        }
                                        isHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isPanning = false
                                    isHoldingDrag = false
                                }

                                onDoubleClicked: function(mouse) {
                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    if (isPrimary && !isPanning) {
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
                    visible: backend ? backend.viewMode === "grid" : false
                    model: visible && backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    boundsBehavior: Flickable.DragOverBounds
                    pixelAligned: true
                    flickDeceleration: 3200
                    maximumFlickVelocity: 9500
                    focus: true

                    WheelHandler {
                        id: gridFastWheel
                        target: null
                        orientation: Qt.Vertical
                        onWheel: function(event) {
                            var step = (event.angleDelta.y / 120.0) * Math.round(155 * Theme.scaleFactor)
                            var maxY = Math.max(0, fileGridView.contentHeight - fileGridView.height)
                            fileGridView.contentY = Math.max(0, Math.min(maxY, fileGridView.contentY - step))
                            event.accepted = true
                        }
                    }

                    readonly property int minCardSize: Math.round(145 * Theme.scaleFactor)
                    readonly property int targetCols: (backend && backend.gridColumns > 0) ? backend.gridColumns : Math.max(1, Math.floor(fileGridView.width / minCardSize))
                    cellWidth: Math.max(Math.round(115 * Theme.scaleFactor), Math.floor(fileGridView.width / Math.max(1, targetCols)))
                    cellHeight: Math.round(cellWidth * 1.02)

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
                        readonly property bool isSelected: {
                            if (!backend) return false
                            var sList = backend.selectedPaths
                            if (sList && sList.indexOf(model.path) !== -1) return true
                            return (backend.selectedItem && backend.selectedItem.path === model.path) ? true : false
                        }
                        readonly property bool isFloatingStyle: backend ? (backend.gridStyle === "floating") : true
                        readonly property bool hasMediaThumb: !model.is_dir && (model.thumb !== "" || (model.icon && (model.icon.indexOf("/") !== -1 || model.icon.indexOf(".") !== -1)))

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
                                        visible: model.is_dir
                                        width: Math.min(parent.width * 0.88, parent.height * 0.96)
                                        height: width * 0.88
                                        anchors.centerIn: parent
                                        previews: model.folder_previews
                                        isSelected: gridContainer.isSelected
                                    }

                                    // B) Image / Video Thumbnail with Dynamic Aspect-Ratio Wrapping Frame
                                    Item {
                                        visible: !model.is_dir && gridContainer.hasMediaThumb
                                        anchors.fill: parent

                                        Image {
                                            id: thumbImg
                                            anchors.centerIn: parent
                                            width: parent.width
                                            height: parent.height
                                            source: parent.visible ? (model.thumb !== "" ? ("file://" + model.thumb) : ("file://" + model.icon)) : ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            mipmap: true
                                        }

                                        // Tightly hugs the actual painted image dimensions (no ugly empty square box!)
                                        Rectangle {
                                            anchors.centerIn: thumbImg
                                            width: thumbImg.paintedWidth > 0 ? thumbImg.paintedWidth + 4 : 0
                                            height: thumbImg.paintedHeight > 0 ? thumbImg.paintedHeight + 4 : 0
                                            radius: Theme.radiusSmall
                                            color: "transparent"
                                            border.color: gridContainer.isSelected ? Theme.accent : "#40ffffff"
                                            border.width: gridContainer.isSelected ? 2 : 1
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
                                        text: model.name
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: gridContainer.isSelected
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
                                preventStealing: isHoldingDrag || isPanning

                                property point pressPos: Qt.point(0, 0)
                                property point lastGlobalPos: Qt.point(0, 0)
                                property bool isHoldingDrag: false
                                property bool isPanning: false

                                onPressed: function(mouse) {
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    lastGlobalPos = gridMouseArea.mapToGlobal(mouse.x, mouse.y)
                                    isHoldingDrag = false
                                    isPanning = false
                                }

                                onPositionChanged: function(mouse) {
                                    if (!backend) return
                                    var gPos = gridMouseArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    var swapped = backend.swapMouseButtons
                                    var panBtn = swapped ? Qt.RightButton : Qt.LeftButton
                                    var dragBtn = swapped ? Qt.LeftButton : Qt.RightButton

                                    if (mouse.buttons & panBtn) {
                                        if (!isPanning && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
                                            isPanning = true
                                        }
                                        if (isPanning) {
                                            var stepX = gPos.x - lastGlobalPos.x
                                            var stepY = gPos.y - lastGlobalPos.y
                                            var maxY = Math.max(0, fileGridView.contentHeight - fileGridView.height)
                                            var maxX = Math.max(0, fileGridView.contentWidth - fileGridView.width)
                                            fileGridView.contentY = Math.max(0, Math.min(maxY, fileGridView.contentY - stepY))
                                            fileGridView.contentX = Math.max(0, Math.min(maxX, fileGridView.contentX - stepX))
                                        }
                                    } else if (mouse.buttons & dragBtn) {
                                        if (!isHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            isHoldingDrag = true
                                            if (!gridContainer.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                            }
                                            backend.startSystemDrag(model.path, model.name, model.icon)
                                            isHoldingDrag = false
                                        }
                                    }
                                    lastGlobalPos = gPos
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
                                        if (!isPanning) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, mouse.modifiers)
                                        }
                                        isPanning = false
                                    } else if (isSecondary) {
                                        if (!isHoldingDrag) {
                                            if (!gridContainer.isSelected) {
                                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type, 0)
                                            }
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.popup()
                                        }
                                        isHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isPanning = false
                                    isHoldingDrag = false
                                }

                                onDoubleClicked: function(mouse) {
                                    if (!backend) return
                                    var swapped = backend.swapMouseButtons
                                    var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                                    if (isPrimary && !isPanning) {
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
