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
            iconGlyph: "⟳"
            text: "Refresh"
            shortcutText: "F5"
            onTriggered: backend.refresh()
        }
    }

    // Main DropArea for external and internal drops onto the current folder
    DropArea {
        id: viewDropArea
        anchors.fill: parent
        z: 5

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Theme.radiusLarge
            color: "#180078d4"
            border.color: Theme.accent
            border.width: 2
            visible: viewDropArea.containsDrag
        }

        onPositionChanged: function(drag) {
            if (root.appWindow && root.appWindow.isRightDragging) {
                var gp = viewDropArea.mapToGlobal(drag.x, drag.y)
                root.appWindow.updateRightDragPos(gp)
            }
        }

        onDropped: function(drop) {
            if (root.appWindow) {
                root.appWindow.endRightDrag()
            }
            var targetFolder = backend.currentPath
            if (targetFolder === "recent://") return

            var activeView = backend.viewMode === "details" ? fileListView : fileGridView
            var viewPt = root.mapToItem(activeView, drop.x, drop.y)
            var hoveredItem = activeView.itemAt(viewPt.x + activeView.contentX, viewPt.y + activeView.contentY)
            if (hoveredItem && hoveredItem.itemIsDir && hoveredItem.itemPath !== "") {
                targetFolder = hoveredItem.itemPath
            }

            var urls = []
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    urls.push(drop.urls[i].toString())
                }
            } else if (drop.text && drop.text.trim() !== "") {
                urls = drop.text.trim().split(/\r?\n/)
            }

            if (urls.length > 0 && root.appWindow) {
                var winPt = root.mapToItem(root.appWindow.contentItem, drop.x, drop.y)
                root.appWindow.requestSmartDrop(urls, targetFolder, winPt.x, winPt.y)
                drop.acceptProposedAction()
            }
        }
    }

    MouseArea {
        id: backgroundArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                backend.clearSelection()
            } else if (mouse.button === Qt.RightButton) {
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

                // 1. Details List View
                ListView {
                    id: fileListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: backend ? backend.viewMode === "details" : true
                    model: backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    contentWidth: Math.max(width, Math.round(260 * Theme.scaleFactor))
                    boundsBehavior: Flickable.DragOverBounds
                    pixelAligned: true
                    flickDeceleration: 2200
                    maximumFlickVelocity: 4800
                    focus: true

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
                        height: Math.round(38 * Theme.scaleFactor)

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

                        Item {
                            id: dragProxy
                            width: 1
                            height: 1
                            Drag.active: itemArea.isRightHoldingDrag
                            Drag.source: rowContainer
                            Drag.hotSpot.x: 0
                            Drag.hotSpot.y: 0
                            Drag.mimeData: { "text/uri-list": "file://" + model.path + "\r\n" }
                            Drag.dragType: Drag.Automatic
                            Drag.onActiveChanged: {
                                if (!Drag.active && root.appWindow) {
                                    root.appWindow.endRightDrag()
                                }
                            }
                        }

                        Rectangle {
                            id: rowDelegate
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: Theme.radiusSmall

                            readonly property bool isSelected: (backend && backend.selectedItem) ? (backend.selectedItem.path === model.path) : false
                            color: isSelected ? Theme.bgSelected : (itemArea.containsMouse ? Theme.bgHover : "transparent")
                            border.color: isSelected ? Theme.accent : "transparent"
                            border.width: isSelected ? 1 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Item {
                                    implicitWidth: Math.round(24 * Theme.scaleFactor)
                                    implicitHeight: Math.round(24 * Theme.scaleFactor)

                                    FolderPreviewIcon {
                                        anchors.fill: parent
                                        visible: model.is_dir
                                        previews: model.folder_previews
                                    }

                                    Image {
                                        anchors.fill: parent
                                        visible: !model.is_dir && (model.thumb !== "" || (model.icon && (model.icon.indexOf("/") !== -1 || model.icon.indexOf(".") !== -1)))
                                        source: visible ? (model.thumb !== "" ? ("file://" + model.thumb) : ("file://" + model.icon)) : ""
                                        fillMode: Image.PreserveAspectFit
                                        mipmap: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !model.is_dir && !parent.children[1].visible
                                        text: model.icon
                                        font.pixelSize: Theme.fontSizeIcon
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.name
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: rowDelegate.isSelected
                                    elide: Text.ElideRight
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
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: isRightHoldingDrag || isLeftPanning

                                property point pressPos: Qt.point(0, 0)
                                property point lastGlobalPos: Qt.point(0, 0)
                                property bool isRightHoldingDrag: false
                                property bool isLeftPanning: false

                                onPressed: function(mouse) {
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    lastGlobalPos = itemArea.mapToGlobal(mouse.x, mouse.y)
                                    isRightHoldingDrag = false
                                    isLeftPanning = false
                                }

                                onPositionChanged: function(mouse) {
                                    var gPos = itemArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    if (mouse.buttons & Qt.LeftButton) {
                                        if (!isLeftPanning && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
                                            isLeftPanning = true
                                        }
                                        if (isLeftPanning) {
                                            var stepX = gPos.x - lastGlobalPos.x
                                            var stepY = gPos.y - lastGlobalPos.y
                                            var maxY = Math.max(0, fileListView.contentHeight - fileListView.height)
                                            var maxX = Math.max(0, fileListView.contentWidth - fileListView.width)
                                            fileListView.contentY = Math.max(0, Math.min(maxY, fileListView.contentY - stepY))
                                            fileListView.contentX = Math.max(0, Math.min(maxX, fileListView.contentX - stepX))
                                        }
                                    } else if (mouse.buttons & Qt.RightButton) {
                                        if (!isRightHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                            isRightHoldingDrag = true
                                            if (root.appWindow) {
                                                root.appWindow.beginRightDrag(model.path, model.name, model.icon, gPos)
                                            }
                                        } else if (isRightHoldingDrag && root.appWindow) {
                                            root.appWindow.updateRightDragPos(gPos)
                                        }
                                    }
                                    lastGlobalPos = gPos
                                }

                                onReleased: function(mouse) {
                                    if (mouse.button === Qt.LeftButton) {
                                        if (!isLeftPanning) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                        }
                                        isLeftPanning = false
                                    } else if (mouse.button === Qt.RightButton) {
                                        if (!isRightHoldingDrag) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.popup()
                                        } else if (root.appWindow) {
                                            root.appWindow.endRightDrag()
                                        }
                                        isRightHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isLeftPanning = false
                                    isRightHoldingDrag = false
                                    if (root.appWindow) {
                                        root.appWindow.endRightDrag()
                                    }
                                }

                                onDoubleClicked: function(mouse) {
                                    if (mouse.button === Qt.LeftButton && !isLeftPanning) {
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
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: backend ? backend.viewMode === "grid" : false
                    model: backend ? backend.files : null
                    clip: true
                    interactive: true
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    boundsBehavior: Flickable.DragOverBounds
                    pixelAligned: true
                    flickDeceleration: 2200
                    maximumFlickVelocity: 4800
                    focus: true

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
                        readonly property bool isSelected: (backend && backend.selectedItem) ? (backend.selectedItem.path === model.path) : false
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

                        Item {
                            id: gridDragProxy
                            width: 1
                            height: 1
                            Drag.active: gridMouseArea.isRightHoldingDrag
                            Drag.source: gridContainer
                            Drag.hotSpot.x: 0
                            Drag.hotSpot.y: 0
                            Drag.mimeData: { "text/uri-list": "file://" + model.path + "\r\n" }
                            Drag.dragType: Drag.Automatic
                            Drag.onActiveChanged: {
                                if (!Drag.active && root.appWindow) {
                                    root.appWindow.endRightDrag()
                                }
                            }
                        }

                        // Card Frame (In "floating" mode, background is transparent and hugs the actual preview!)
                        Rectangle {
                            id: gridDelegate
                            width: fileGridView.cellWidth - 10
                            height: fileGridView.cellHeight - 10
                            anchors.centerIn: parent
                            radius: Theme.radiusLarge

                            color: gridContainer.isFloatingStyle
                                   ? (gridContainer.isSelected ? "#280078d4" : (gridMouseArea.containsMouse ? "#1affffff" : "transparent"))
                                   : (gridContainer.isSelected ? Theme.bgSelected : (gridMouseArea.containsMouse ? Theme.bgHover : Theme.bgCard))
                            border.color: gridContainer.isSelected
                                          ? Theme.accent
                                          : (gridContainer.isFloatingStyle ? (gridMouseArea.containsMouse ? "#35ffffff" : "transparent") : Theme.borderDim)
                            border.width: gridContainer.isSelected ? 2 : 1

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
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: isRightHoldingDrag || isLeftPanning

                                property point pressPos: Qt.point(0, 0)
                                property point lastGlobalPos: Qt.point(0, 0)
                                property bool isRightHoldingDrag: false
                                property bool isLeftPanning: false

                                onPressed: function(mouse) {
                                    pressPos = Qt.point(mouse.x, mouse.y)
                                    lastGlobalPos = gridMouseArea.mapToGlobal(mouse.x, mouse.y)
                                    isRightHoldingDrag = false
                                    isLeftPanning = false
                                }

                                onPositionChanged: function(mouse) {
                                    var gPos = gridMouseArea.mapToGlobal(mouse.x, mouse.y)
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y

                                    if (mouse.buttons & Qt.LeftButton) {
                                        if (!isLeftPanning && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
                                            isLeftPanning = true
                                        }
                                        if (isLeftPanning) {
                                            var stepX = gPos.x - lastGlobalPos.x
                                            var stepY = gPos.y - lastGlobalPos.y
                                            var maxY = Math.max(0, fileGridView.contentHeight - fileGridView.height)
                                            var maxX = Math.max(0, fileGridView.contentWidth - fileGridView.width)
                                            fileGridView.contentY = Math.max(0, Math.min(maxY, fileGridView.contentY - stepY))
                                            fileGridView.contentX = Math.max(0, Math.min(maxX, fileGridView.contentX - stepX))
                                        }
                                    } else if (mouse.buttons & Qt.RightButton) {
                                        if (!isRightHoldingDrag && (Math.abs(dx) > 7 || Math.abs(dy) > 7)) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                            isRightHoldingDrag = true
                                            if (root.appWindow) {
                                                root.appWindow.beginRightDrag(model.path, model.name, model.icon, gPos)
                                            }
                                        } else if (isRightHoldingDrag && root.appWindow) {
                                            root.appWindow.updateRightDragPos(gPos)
                                        }
                                    }
                                    lastGlobalPos = gPos
                                }

                                onReleased: function(mouse) {
                                    if (mouse.button === Qt.LeftButton) {
                                        if (!isLeftPanning) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                        }
                                        isLeftPanning = false
                                    } else if (mouse.button === Qt.RightButton) {
                                        if (!isRightHoldingDrag) {
                                            backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                            dolphinMenu.targetPath = model.path
                                            dolphinMenu.targetName = model.name
                                            dolphinMenu.isDir = model.is_dir
                                            dolphinMenu.popup()
                                        } else if (root.appWindow) {
                                            root.appWindow.endRightDrag()
                                        }
                                        isRightHoldingDrag = false
                                    }
                                }

                                onCanceled: {
                                    isLeftPanning = false
                                    isRightHoldingDrag = false
                                    if (root.appWindow) {
                                        root.appWindow.endRightDrag()
                                    }
                                }

                                onDoubleClicked: function(mouse) {
                                    if (mouse.button === Qt.LeftButton && !isLeftPanning) {
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
