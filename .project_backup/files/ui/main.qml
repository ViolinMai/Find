import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
import "components"

ApplicationWindow {
    id: root
    width: 1400
    height: 840
    minimumWidth: 260
    minimumHeight: 240
    visible: true
    title: (backend && backend.picker && backend.picker.isActive) ? backend.picker.title : "Find"
    color: (backend && backend.transparentBlur) ? "transparent" : Theme.bgBase

    // Hyprland Multi-Tile Adaptive Layout Engine (Supports 1/2, 1/3, 1/4, 1/5 screen in any aspect ratio)
    readonly property real aspectRatio: height > 0 ? (width / height) : 1.0
    readonly property bool isPortraitTile: aspectRatio < 0.88

    // Tier 1: >= 680px (e.g. Half-screen 16:9 / 16:8 in Hyprland -> Full Sidebar with labels)
    // Tier 2: 430px..679px (e.g. Quarter-screen -> Compact Icon Rail on left so Quick Access stays 1-click accessible)
    // Tier 3: < 430px or Portrait Tile (e.g. Fifth-screen strip -> Horizontal Top Quick Access Pill Bar)
    property bool userShowSidebar: true
    property bool userShowPreview: true
    property bool railExpandedOverride: false

    readonly property string resolvedSidebarLayout: {
        if (!userShowSidebar) return "hidden"
        var mode = backend ? backend.sidebarMode : "auto"
        if (mode === "full") return "full"
        if (mode === "rail") return "rail"
        if (mode === "topbar") return "topbar"

        // "auto" smart Hyprland mode
        if (width < 460 || (isPortraitTile && width < 580)) return "topbar"
        if (width < 680 && !railExpandedOverride) return "rail"
        return "full"
    }

    readonly property bool showLeftSidebar: resolvedSidebarLayout === "full" || resolvedSidebarLayout === "rail"
    readonly property bool isSidebarCompactRail: resolvedSidebarLayout === "rail"
    readonly property bool showTopQuickAccessBar: resolvedSidebarLayout === "topbar"

    // Preview Panel automatically hides on small tiles unless toggled, and docks at bottom on narrow/portrait tiles
    readonly property bool effectiveShowPreview: userShowPreview && (width >= 960 || height >= 760)
    readonly property bool dockPreviewBottom: width < 920 || isPortraitTile

    // Global Drag & Drop state (Right-click hold drag + Smart Drop)
    property bool isRightDragging: false
    property string draggedFilePath: ""
    property string draggedFileName: ""
    property string draggedFileIcon: "📄"
    property real dragCursorX: 0
    property real dragCursorY: 0

    property var pendingDropUrls: []
    property int pendingDropIndex: 0
    property string pendingDropDestDir: ""
    property string pendingDropOperation: "copy"
    property string conflictSourcePath: ""
    property string conflictFileName: ""

    property var topQuickAccessModel: backend ? backend.getQuickAccessLocations() : []
    property var topDrivesModel: backend ? backend.getDrives() : []

    Connections {
        target: backend
        function onSidebarUpdated() {
            if (!backend) return
            root.topQuickAccessModel = backend.getQuickAccessLocations()
            root.topDrivesModel = backend.getDrives()
        }
    }

    function beginRightDrag(path, name, icon, globalPt) {
        draggedFilePath = path
        draggedFileName = name
        draggedFileIcon = icon || "📄"
        var localPt = mainContainer.mapFromGlobal(globalPt.x, globalPt.y)
        dragCursorX = localPt.x
        dragCursorY = localPt.y
        isRightDragging = true
    }

    function updateRightDragPos(globalPt) {
        var localPt = mainContainer.mapFromGlobal(globalPt.x, globalPt.y)
        dragCursorX = localPt.x
        dragCursorY = localPt.y
    }

    function endRightDrag() {
        isRightDragging = false
    }

    function requestSmartDrop(urlsList, destDir, dropPointX, dropPointY) {
        if (!backend || !destDir || destDir === "recent://" || destDir === "trash://") return
        var cleanPaths = backend.filterValidDropSources(urlsList, destDir)
        if (!cleanPaths || cleanPaths.length === 0) return

        pendingDropUrls = cleanPaths
        pendingDropDestDir = destDir

        if (dropPointX !== undefined && dropPointY !== undefined) {
            dropActionMenu.x = Math.max(8, Math.min(dropPointX, root.width - dropActionMenu.width - 12))
            dropActionMenu.y = Math.max(8, Math.min(dropPointY, root.height - dropActionMenu.height - 12))
            dropActionMenu.open()
        } else {
            dropActionMenu.popup()
        }
    }

    function startBatchTransfer(operation) {
        pendingDropOperation = operation
        pendingDropIndex = 0
        processNextPendingDrop()
    }

    function processNextPendingDrop() {
        if (pendingDropIndex >= pendingDropUrls.length) {
            pendingDropUrls = []
            pendingDropIndex = 0
            return
        }
        var currentSrc = pendingDropUrls[pendingDropIndex]
        var hasConflict = backend.checkTransferConflict(currentSrc, pendingDropDestDir)
        if (hasConflict) {
            conflictSourcePath = currentSrc
            var parts = currentSrc.split("/")
            conflictFileName = parts[parts.length - 1]
            conflictDialog.open()
        } else {
            backend.executeDropTransfer(currentSrc, pendingDropDestDir, pendingDropOperation, "replace")
            pendingDropIndex += 1
            processNextPendingDrop()
        }
    }

    function resolveCurrentConflict(resolution) {
        conflictDialog.close()
        if (resolution !== "cancel") {
            backend.executeDropTransfer(conflictSourcePath, pendingDropDestDir, pendingDropOperation, resolution)
            pendingDropIndex += 1
            processNextPendingDrop()
        } else {
            pendingDropUrls = []
            pendingDropIndex = 0
        }
    }

    function triggerPasteInCurrentFolder() {
        if (!backend) return
        var cur = backend.currentPath
        if (!cur || cur === "recent://" || cur === "trash://") return
        var clipPaths = backend.getClipboardPaths()
        if (clipPaths && clipPaths.length > 0) {
            var op = backend.isClipboardCut() ? "move" : "copy"
            root.pendingDropUrls = clipPaths
            root.pendingDropDestDir = cur
            root.startBatchTransfer(op)
            if (op === "move") {
                backend.clearClipboardStage()
            }
        }
    }

    onClosing: function(close) {
        if (backend && backend.picker && backend.picker.isActive) {
            backend.cancelPicker()
        }
    }

    // Global Window Shortcuts (Active regardless of child focus)
    Shortcut {
        sequence: "F5"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.refresh()
    }
    Shortcut {
        sequence: "Ctrl+H"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.toggleShowHidden()
    }
    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.WindowShortcut
        onActivated: addressBar.focusPathInput()
    }
    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.WindowShortcut
        onActivated: addressBar.toggleSearch()
    }
    Shortcut {
        sequence: "Ctrl+A"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: if (backend) backend.selectAll()
    }
    Shortcut {
        sequence: "Ctrl+C"
        context: Qt.WindowShortcut
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                backend.stageClipboard(backend.selectedItem.path, false)
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+X"
        context: Qt.WindowShortcut
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                backend.stageClipboard(backend.selectedItem.path, true)
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+V"
        context: Qt.WindowShortcut
        onActivated: root.triggerPasteInCurrentFolder()
    }
    Shortcut {
        sequence: "Ctrl+D"
        context: Qt.WindowShortcut
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                backend.duplicateItem(backend.selectedItem.path)
            }
        }
    }
    Shortcut {
        sequences: ["Delete", "Backspace"]
        context: Qt.WindowShortcut
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                backend.moveToTrash(backend.selectedItem.path)
            }
        }
    }
    Shortcut {
        sequence: "F2"
        context: Qt.WindowShortcut
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                centralFileView.openRenameForSelected()
            }
        }
    }
    Shortcut {
        sequence: "Alt+Left"
        context: Qt.WindowShortcut
        onActivated: if (backend && backend.canGoBack) backend.goBack()
    }
    Shortcut {
        sequence: "Alt+Right"
        context: Qt.WindowShortcut
        onActivated: if (backend && backend.canGoForward) backend.goForward()
    }
    Shortcut {
        sequence: "Alt+Up"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.goUp()
    }
    Shortcut {
        sequence: "Ctrl+T"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.addTab("")
    }
    Shortcut {
        sequence: "Ctrl+W"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.closeTab(backend.activeTabIndex)
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        context: Qt.WindowShortcut
        onActivated: if (backend) backend.nextTab()
    }
    Shortcut {
        sequence: "C"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive
        onActivated: if (backend && backend.isMediaLibraryView) backend.toggleSubtitlesInMedia()
    }
    Shortcut {
        sequences: ["Return", "Enter", "Space"]
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: {
            if (backend && backend.selectedItem && backend.selectedItem.path) {
                backend.openEntry(backend.selectedItem.path)
            } else if (backend) {
                backend.selectByIndex(0)
            }
        }
    }
    Shortcut {
        sequence: "Up"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: {
            if (!backend) return
            var step = backend.viewMode === "grid" ? -centralFileView.currentGridColumns() : -1
            backend.moveSelectionRelative(step, centralFileView.currentGridColumns())
            centralFileView.syncViewScrollToSelection()
        }
    }
    Shortcut {
        sequence: "Down"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: {
            if (!backend) return
            var step = backend.viewMode === "grid" ? centralFileView.currentGridColumns() : 1
            backend.moveSelectionRelative(step, centralFileView.currentGridColumns())
            centralFileView.syncViewScrollToSelection()
        }
    }
    Shortcut {
        sequence: "Left"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: {
            if (!backend) return
            backend.moveSelectionRelative(-1, centralFileView.currentGridColumns())
            centralFileView.syncViewScrollToSelection()
        }
    }
    Shortcut {
        sequence: "Right"
        context: Qt.WindowShortcut
        enabled: !addressBar.isEditingPath && !addressBar.isSearchActive && !conflictDialog.visible
        onActivated: {
            if (!backend) return
            backend.moveSelectionRelative(1, centralFileView.currentGridColumns())
            centralFileView.syncViewScrollToSelection()
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        propagateComposedEvents: true

        onClicked: function(mouse) {
            if (mouse.button === Qt.BackButton) {
                if (backend.canGoBack) {
                    backend.goBack()
                    mouse.accepted = true
                }
            } else if (mouse.button === Qt.ForwardButton) {
                if (backend.canGoForward) {
                    backend.goForward()
                    mouse.accepted = true
                }
            }
        }
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        color: Theme.bgBase

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // File Explorer Style Multi-Tab Bar
            Rectangle {
                id: tabBarContainer
                Layout.fillWidth: true
                height: Math.round(36 * Theme.scaleFactor)
                color: Theme.bgSidebar

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 4

                    ListView {
                        id: tabsListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        orientation: ListView.Horizontal
                        spacing: 4
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: backend ? backend.tabs : []

                        delegate: Rectangle {
                            id: tabPill
                            readonly property bool isCurrTab: modelData.active
                            width: Math.min(Math.round(195 * Theme.scaleFactor), Math.max(Math.round(92 * Theme.scaleFactor), tabRow.implicitWidth + 20))
                            height: Math.round(28 * Theme.scaleFactor)
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            radius: Theme.radiusMedium
                            color: tabDropArea.containsDrag
                                   ? "#380078d4"
                                   : (isCurrTab ? Theme.bgSurface : (tabMouse.containsMouse ? Theme.bgHover : "transparent"))
                            border.color: tabDropArea.containsDrag
                                          ? Theme.accent
                                          : (isCurrTab ? Theme.borderFocus : Theme.borderDim)
                            border.width: isCurrTab || tabDropArea.containsDrag ? 1 : 0

                            RowLayout {
                                id: tabRow
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 6

                                Text {
                                    text: modelData.path === "recent://" ? "🕒" : (modelData.path === "trash://" ? "🗑️" : "📁")
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: tabPill.isCurrTab ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: tabPill.isCurrTab
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    width: Math.round(18 * Theme.scaleFactor)
                                    height: Math.round(18 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: closeTabMouse.containsMouse ? Theme.bgHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: closeTabMouse.containsMouse ? Theme.textDanger : Theme.textTertiary
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: closeTabMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend) backend.closeTab(modelData.index)
                                    }
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                anchors.rightMargin: Math.round(22 * Theme.scaleFactor)
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (!backend) return
                                    if (mouse.button === Qt.MiddleButton) {
                                        backend.closeTab(modelData.index)
                                    } else {
                                        backend.switchTab(modelData.index)
                                    }
                                }
                            }

                            DropArea {
                                id: tabDropArea
                                anchors.fill: parent
                                onEntered: function(drag) {
                                    tabHoverSwitchTimer.targetIdx = modelData.index
                                    tabHoverSwitchTimer.restart()
                                }
                                onExited: {
                                    tabHoverSwitchTimer.stop()
                                }
                                onDropped: function(drop) {
                                    tabHoverSwitchTimer.stop()
                                    if (root.isRightDragging) root.endRightDrag()
                                    if (!modelData.path || modelData.path === "recent://" || modelData.path === "trash://") return
                                    var urls = []
                                    if (drop.hasUrls) {
                                        for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                                    } else if (drop.text && drop.text.trim() !== "") {
                                        urls = drop.text.trim().split(/\r?\n/)
                                    }
                                    if (urls.length > 0) {
                                        var winPt = tabPill.mapToItem(root.contentItem, drop.x, drop.y)
                                        root.requestSmartDrop(urls, modelData.path, winPt.x, winPt.y)
                                        drop.acceptProposedAction()
                                    }
                                }
                            }
                        }
                    }

                    Timer {
                        id: tabHoverSwitchTimer
                        interval: 550
                        repeat: false
                        property int targetIdx: -1
                        onTriggered: {
                            if (backend && targetIdx >= 0) {
                                backend.switchTab(targetIdx)
                            }
                        }
                    }

                    // Add Tab '+' Button
                    Rectangle {
                        implicitWidth: Math.round(28 * Theme.scaleFactor)
                        implicitHeight: Math.round(28 * Theme.scaleFactor)
                        radius: Theme.radiusMedium
                        color: addTabMouse.containsMouse ? Theme.bgHover : Theme.bgSurface
                        border.color: Theme.borderDim
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "＋"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        MouseArea {
                            id: addTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (backend) backend.addTab("")
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.borderDim
                }
            }

            // Top Address & Action Bar
            Rectangle {
                Layout.fillWidth: true
                height: Math.round(48 * Theme.scaleFactor)
                color: Theme.bgBase

                AddressBar {
                    id: addressBar
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(10 * Theme.scaleFactor)
                    anchors.rightMargin: Math.round(10 * Theme.scaleFactor)
                    appWindow: root
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
            }

            // Ultra-Compact Horizontal Quick Access Strip (Automatically active in 1/4, 1/5, or portrait tiles!)
            Rectangle {
                Layout.fillWidth: true
                height: Math.round(36 * Theme.scaleFactor)
                color: Theme.bgSidebar
                visible: root.showTopQuickAccessBar

                Flickable {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    contentWidth: pillRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    RowLayout {
                        id: pillRow
                        height: parent.height
                        spacing: 6

                        Repeater {
                            model: root.topQuickAccessModel
                            delegate: Rectangle {
                                readonly property bool isCurr: (backend ? backend.currentPath : "") === modelData.path
                                implicitHeight: Math.round(26 * Theme.scaleFactor)
                                implicitWidth: pRow.implicitWidth + 14
                                radius: Theme.radiusMedium
                                color: isCurr ? Theme.accent : (pMouse.containsMouse ? Theme.bgHover : Theme.bgSurface)
                                border.color: isCurr ? Theme.accentHover : Theme.borderDim
                                border.width: 1

                                RowLayout {
                                    id: pRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        text: (modelData.icon.indexOf("/") === -1 && modelData.icon.indexOf(".") === -1) ? modelData.icon : "📁"
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                    Text {
                                        text: modelData.name
                                        color: parent.parent.isCurr ? "#ffffff" : Theme.textPrimary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: parent.parent.isCurr
                                    }
                                }

                                MouseArea {
                                    id: pMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (!backend) return
                                        if (mouse.button === Qt.MiddleButton) {
                                            backend.addTab(modelData.path)
                                        } else if (mouse.button === Qt.RightButton) {
                                            topStripMenu.targetPath = modelData.path
                                            topStripMenu.popup()
                                        } else {
                                            backend.navigateTo(modelData.path)
                                        }
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: function(drop) {
                                        var urls = []
                                        if (drop.hasUrls) {
                                            for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                                        } else if (drop.text && drop.text.trim() !== "") {
                                            urls = drop.text.trim().split(/\r?\n/)
                                        }
                                        if (urls.length > 0) {
                                            var winPt = parent.mapToItem(root.contentItem, drop.x, drop.y)
                                            root.requestSmartDrop(urls, modelData.path, winPt.x, winPt.y)
                                            drop.acceptProposedAction()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: 1; height: 18; color: Theme.borderDim }

                        Repeater {
                            model: root.topDrivesModel
                            delegate: Rectangle {
                                readonly property bool isCurr: (backend ? backend.currentPath : "") === modelData.path
                                implicitHeight: Math.round(26 * Theme.scaleFactor)
                                implicitWidth: dRow.implicitWidth + 14
                                radius: Theme.radiusMedium
                                color: isCurr ? Theme.accent : (dMouse.containsMouse ? Theme.bgHover : Theme.bgSurface)
                                border.color: isCurr ? Theme.accentHover : Theme.borderDim
                                border.width: 1

                                RowLayout {
                                    id: dRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { text: modelData.icon; font.pixelSize: Theme.fontSizeSmall }
                                    Text {
                                        text: modelData.name
                                        color: parent.parent.isCurr ? "#ffffff" : Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: parent.parent.isCurr
                                    }
                                }

                                MouseArea {
                                    id: dMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (!backend) return
                                        if (mouse.button === Qt.MiddleButton) {
                                            backend.addTab(modelData.path)
                                        } else if (mouse.button === Qt.RightButton) {
                                            topStripMenu.targetPath = modelData.path
                                            topStripMenu.popup()
                                        } else {
                                            backend.navigateTo(modelData.path)
                                        }
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: function(drop) {
                                        var urls = []
                                        if (drop.hasUrls) {
                                            for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                                        } else if (drop.text && drop.text.trim() !== "") {
                                            urls = drop.text.trim().split(/\r?\n/)
                                        }
                                        if (urls.length > 0) {
                                            var winPt = parent.mapToItem(root.contentItem, drop.x, drop.y)
                                            root.requestSmartDrop(urls, modelData.path, winPt.x, winPt.y)
                                            drop.acceptProposedAction()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.borderDim
                }
            }

            // Main Workspace Area
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Left Sidebar (Full or Compact Icon Rail depending on window width)
                Sidebar {
                    id: sidebarPanel
                    visible: root.showLeftSidebar
                    compactMode: root.isSidebarCompactRail
                    appWindow: root
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.isSidebarCompactRail
                                           ? Math.round(52 * Theme.scaleFactor)
                                           : Math.min(Math.round(210 * Theme.scaleFactor), Math.max(Math.round(155 * Theme.scaleFactor), Math.round(root.width * 0.22)))
                }

                Rectangle {
                    visible: root.showLeftSidebar
                    Layout.fillHeight: true
                    width: 1
                    color: Theme.borderDim
                }

                // Center + Preview Adaptive Split (Horizontal on wide windows, Vertical on narrow/tall windows)
                SplitView {
                    id: workspaceSplit
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: root.dockPreviewBottom ? Qt.Vertical : Qt.Horizontal

                    handle: Rectangle {
                        implicitWidth: workspaceSplit.orientation === Qt.Horizontal ? Math.round(5 * Theme.scaleFactor) : workspaceSplit.width
                        implicitHeight: workspaceSplit.orientation === Qt.Vertical ? Math.round(5 * Theme.scaleFactor) : workspaceSplit.height
                        color: "transparent"

                        Rectangle {
                            anchors.centerIn: parent
                            width: workspaceSplit.orientation === Qt.Horizontal ? 1 : parent.width
                            height: workspaceSplit.orientation === Qt.Vertical ? 1 : parent.height
                            color: SplitHandle.hovered || SplitHandle.pressed ? Theme.accent : Theme.borderDim
                        }
                    }

                    FileView {
                        id: centralFileView
                        appWindow: root
                        SplitView.fillWidth: true
                        SplitView.fillHeight: true
                        SplitView.minimumWidth: Math.round(160 * Theme.scaleFactor)
                        SplitView.minimumHeight: Math.round(140 * Theme.scaleFactor)
                    }

                    PreviewPanel {
                        id: previewPanel
                        visible: root.effectiveShowPreview
                        SplitView.preferredWidth: root.dockPreviewBottom ? workspaceSplit.width : Math.min(Math.round(265 * Theme.scaleFactor), Math.round(root.width * 0.27))
                        SplitView.preferredHeight: root.dockPreviewBottom ? Math.min(Math.round(230 * Theme.scaleFactor), Math.round(root.height * 0.35)) : workspaceSplit.height
                        SplitView.minimumWidth: Math.round(170 * Theme.scaleFactor)
                        SplitView.minimumHeight: Math.round(130 * Theme.scaleFactor)
                    }
                }
            }

            PickerBottomBar {
                Layout.fillWidth: true
                visible: backend && backend.picker ? backend.picker.isActive : false
            }
        }

        // Floating Drag Ghost Preview (Follows cursor when holding Right Click)
        Rectangle {
            id: dragGhostBadge
            visible: root.isRightDragging
            x: root.dragCursorX + 14
            y: root.dragCursorY + 14
            z: 99999
            width: Math.min(Math.round(250 * Theme.scaleFactor), ghostRow.implicitWidth + Math.round(22 * Theme.scaleFactor))
            height: Math.round(40 * Theme.scaleFactor)
            radius: Theme.radiusLarge
            color: "#ee1e1e24"
            border.color: Theme.accent
            border.width: 2

            RowLayout {
                id: ghostRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: root.draggedFileIcon
                    font.pixelSize: Theme.fontSizeMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: root.draggedFileName
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "Drop to Copy or Move"
                        color: Theme.accent
                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                        font.bold: true
                    }
                }
            }
        }
    }

    StyledMenu {
        id: topStripMenu
        property string targetPath: ""
        StyledMenuItem {
            iconGlyph: "📂"
            text: "Open"
            font.bold: true
            onTriggered: if (backend) backend.navigateTo(topStripMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "➕"
            text: "Open in New Tab"
            onTriggered: if (backend) backend.addTab(topStripMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "💻"
            text: "Open in Terminal"
            onTriggered: if (backend) backend.openInTerminal(topStripMenu.targetPath)
        }
    }

    // Smart Drop Action Menu (Copy Here / Move Here / Cancel)
    StyledMenu {
        id: dropActionMenu
        title: "Drop Action"

        StyledMenuItem {
            iconGlyph: "📋"
            text: "Copy Here"
            font.bold: true
            onTriggered: root.startBatchTransfer("copy")
        }
        StyledMenuItem {
            iconGlyph: "✂️"
            text: "Move Here"
            font.bold: true
            onTriggered: root.startBatchTransfer("move")
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            iconGlyph: "✕"
            text: "Cancel"
            isDanger: true
            onTriggered: {
                root.pendingDropUrls = []
                root.pendingDropIndex = 0
            }
        }
    }

    // Smart File Conflict Resolution Dialog
    Dialog {
        id: conflictDialog
        title: "File Conflict Detected"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(450 * Theme.scaleFactor), root.width - 24)
        closePolicy: Popup.NoAutoClose

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.borderFocus
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
                spacing: 10

                Text {
                    text: "⚠️  File Already Exists"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Math.round(12 * Theme.scaleFactor)

            Text {
                Layout.fillWidth: true
                text: "An item named \"" + root.conflictFileName + "\" already exists in:\n" + root.pendingDropDestDir + "\n\nHow would you like to proceed?"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: "🔄 Replace"
                    onClicked: root.resolveCurrentConflict("replace")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitHeight: Math.round(34 * Theme.scaleFactor)
                        color: parent.hovered ? "#dc2626" : "#b91c1c"
                        radius: Theme.radiusMedium
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: "📑 Keep Both"
                    onClicked: root.resolveCurrentConflict("keep_both")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitHeight: Math.round(34 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.accentHover : Theme.accent
                        radius: Theme.radiusMedium
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: "⏭️ Skip"
                    onClicked: root.resolveCurrentConflict("skip")
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitHeight: Math.round(34 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : Theme.bgCard
                        border.color: Theme.borderDim
                        radius: Theme.radiusMedium
                    }
                }

                Button {
                    text: "Cancel"
                    onClicked: root.resolveCurrentConflict("cancel")
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(68 * Theme.scaleFactor)
                        implicitHeight: Math.round(34 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : "transparent"
                        border.color: Theme.borderDim
                        radius: Theme.radiusMedium
                    }
                }
            }
        }
    }
}
