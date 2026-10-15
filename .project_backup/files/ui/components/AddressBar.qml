import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    spacing: Math.round(6 * Theme.scaleFactor)

    property var appWindow: null
    property bool isEditingPath: false
    property bool isSearchActive: false
    readonly property bool isCompactBar: width < Math.round(620 * Theme.scaleFactor)
    readonly property bool isUltraCompactBar: width < Math.round(380 * Theme.scaleFactor)

    function focusPathInput() {
        root.isEditingPath = true
        pathInput.forceActiveFocus()
        pathInput.selectAll()
    }

    function toggleSearch() {
        root.isSearchActive = !root.isSearchActive
        if (root.isSearchActive) {
            searchInput.forceActiveFocus()
        } else {
            backend.searchFast("")
        }
    }

    component ToolBtn: Rectangle {
        property string iconText: ""
        property string btnText: ""
        property bool isEnabled: true
        property bool isActiveToggle: false
        signal clicked()
        signal rightClicked()

        readonly property bool showText: btnText !== "" && !root.isCompactBar
        implicitWidth: showText ? Math.round(74 * Theme.scaleFactor) : Math.round(34 * Theme.scaleFactor)
        implicitHeight: Math.round(34 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: !isEnabled ? "transparent" : (isActiveToggle ? Theme.bgSelected : (btnMouse.containsMouse ? Theme.bgHover : "transparent"))
        border.color: isActiveToggle ? Theme.accent : "transparent"
        border.width: isActiveToggle ? 1 : 0
        opacity: isEnabled ? 1.0 : 0.35

        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: iconText
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
            }
            Text {
                visible: parent.parent.showText
                text: btnText
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                font.bold: true
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            enabled: parent.isEnabled
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: parent.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton) {
                    parent.clicked()
                } else if (mouse.button === Qt.RightButton) {
                    parent.rightClicked()
                }
            }
        }
    }

    // Left Navigation & Panel Controls
    RowLayout {
        spacing: 2
        Layout.alignment: Qt.AlignVCenter

        ToolBtn {
            iconText: "◧"
            isActiveToggle: root.appWindow ? root.appWindow.userShowSidebar : true
            onClicked: {
                if (root.appWindow) {
                    if (root.appWindow.isSidebarCompactRail) {
                        root.appWindow.railExpandedOverride = true
                    } else if (root.appWindow.railExpandedOverride) {
                        root.appWindow.railExpandedOverride = false
                    } else {
                        root.appWindow.userShowSidebar = !root.appWindow.userShowSidebar
                    }
                }
            }
        }

        ToolBtn {
            iconText: "←"
            isEnabled: backend ? backend.canGoBack : false
            onClicked: if (backend) backend.goBack()
        }
        ToolBtn {
            visible: !root.isUltraCompactBar
            iconText: "→"
            isEnabled: backend ? backend.canGoForward : false
            onClicked: if (backend) backend.goForward()
        }
        ToolBtn {
            iconText: "↑"
            isEnabled: true
            onClicked: backend.goUp()
        }
        ToolBtn {
            visible: !root.isCompactBar
            iconText: "⟳"
            isEnabled: true
            onClicked: backend.refresh()
        }
    }

    // Center Address Bar
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.round(36 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: Theme.bgSurface
        border.color: (pathInput.activeFocus || searchInput.activeFocus) ? Theme.borderFocus : Theme.borderDim
        border.width: 1
        Layout.alignment: Qt.AlignVCenter

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Math.round(8 * Theme.scaleFactor)
            anchors.rightMargin: Math.round(6 * Theme.scaleFactor)
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.isSearchActive ? "🔍" : "📁"
                font.pixelSize: Theme.fontSizeMedium
            }

            Flickable {
                id: crumbFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.isEditingPath && !root.isSearchActive
                contentWidth: crumbRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                onContentWidthChanged: {
                    if (contentWidth > width) {
                        contentX = contentWidth - width
                    } else {
                        contentX = 0
                    }
                }

                RowLayout {
                    id: crumbRow
                    height: parent.height
                    spacing: 2

                    Repeater {
                        model: backend ? backend.breadcrumbs : []
                        delegate: RowLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                implicitHeight: Math.round(24 * Theme.scaleFactor)
                                implicitWidth: crumbText.implicitWidth + Math.round(10 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: crumbMouse.containsMouse ? Theme.bgHover : "transparent"

                                Text {
                                    id: crumbText
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: crumbMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeNormal
                                    font.bold: true
                                }

                                MouseArea {
                                    id: crumbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.navigateTo(modelData.path)
                                }
                            }

                            Text {
                                text: "›"
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeTitle
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitWidth: 32
                        implicitHeight: 24
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.focusPathInput()
                        }
                    }
                }
            }

            TextInput {
                id: pathInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.isEditingPath && !root.isSearchActive
                text: backend ? backend.currentPath : ""
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                selectionColor: Theme.accent
                clip: true

                Keys.onEscapePressed: {
                    root.isEditingPath = false
                }

                onAccepted: {
                    backend.navigateTo(text)
                    root.isEditingPath = false
                }
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        root.isEditingPath = false
                    }
                }
            }

            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.isSearchActive
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                selectionColor: Theme.accent
                clip: true

                Keys.onEscapePressed: {
                    root.isSearchActive = false
                    backend.searchFast("")
                }

                onTextChanged: {
                    backend.searchFast(text)
                }
            }

            ToolBtn {
                visible: !root.isUltraCompactBar
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(26 * Theme.scaleFactor)
                implicitHeight: Math.round(26 * Theme.scaleFactor)
                iconText: "📋"
                onClicked: backend.copyToClipboard(backend.currentPath)
            }

            ToolBtn {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(26 * Theme.scaleFactor)
                implicitHeight: Math.round(26 * Theme.scaleFactor)
                iconText: root.isEditingPath ? "✔" : "✎"
                onClicked: {
                    if (root.isEditingPath) {
                        backend.navigateTo(pathInput.text)
                        root.isEditingPath = false
                    } else {
                        root.focusPathInput()
                    }
                }
            }
        }
    }

    // Right Action Panel
    RowLayout {
        spacing: 3
        Layout.alignment: Qt.AlignVCenter

        ToolBtn {
            iconText: root.isSearchActive ? "✕" : "🔍"
            onClicked: root.toggleSearch()
        }

        ToolBtn {
            iconText: "＋"
            btnText: "New"
            onClicked: newMenu.popup()

            StyledMenu {
                id: newMenu
                StyledMenuItem {
                    iconGlyph: "📁"
                    text: "Folder"
                    font.bold: true
                    onTriggered: backend.createItem("folder", "")
                }
                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }
                StyledMenuItem {
                    iconGlyph: "📄"
                    text: "Text Document (.txt)"
                    onTriggered: backend.createItem("txt", "")
                }
                StyledMenuItem {
                    iconGlyph: "🐍"
                    text: "Python Script (.py)"
                    onTriggered: backend.createItem("py", "")
                }
                StyledMenuItem {
                    iconGlyph: "🦀"
                    text: "Rust Source (.rs)"
                    onTriggered: backend.createItem("rs", "")
                }
                StyledMenuItem {
                    iconGlyph: "📋"
                    text: "JSON File (.json)"
                    onTriggered: backend.createItem("json", "")
                }
                StyledMenuItem {
                    iconGlyph: "🔗"
                    text: "Symbolic Link"
                    onTriggered: backend.createItem("link", "")
                }
                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }
                StyledMenuItem {
                    iconGlyph: "◻️"
                    text: "Empty File"
                    onTriggered: backend.createItem("empty", "")
                }
            }
        }

        ToolBtn {
            iconText: "⇅"
            btnText: "Sort"
            onClicked: sortMenu.popup()

            StyledMenu {
                id: sortMenu
                StyledMenuItem {
                    iconGlyph: (backend && backend.sortBy === "name") ? (backend.sortAscending ? "▲" : "▼") : ""
                    text: "Name"
                    onTriggered: if (backend) backend.setSort("name")
                }
                StyledMenuItem {
                    iconGlyph: (backend && backend.sortBy === "modified") ? (backend.sortAscending ? "▲" : "▼") : ""
                    text: "Date Modified"
                    onTriggered: if (backend) backend.setSort("modified")
                }
                StyledMenuItem {
                    iconGlyph: (backend && backend.sortBy === "created") ? (backend.sortAscending ? "▲" : "▼") : ""
                    text: "Date Created"
                    onTriggered: if (backend) backend.setSort("created")
                }
                StyledMenuItem {
                    iconGlyph: (backend && backend.sortBy === "size") ? (backend.sortAscending ? "▲" : "▼") : ""
                    text: "Size"
                    onTriggered: if (backend) backend.setSort("size")
                }
            }
        }

        ToolBtn {
            id: viewModeBtn
            iconText: (backend && backend.viewMode === "details") ? "☰" : "☵"
            onClicked: if (backend) backend.setViewMode(backend.viewMode === "details" ? "grid" : "details")
            onRightClicked: layoutSettingsMenu.popup(viewModeBtn, 0, viewModeBtn.height)

            StyledMenu {
                id: layoutSettingsMenu

                StyledMenuItem {
                    text: "View: Details List"
                    checkable: true
                    checked: backend ? backend.viewMode === "details" : true
                    onTriggered: if (backend) backend.setViewMode("details")
                }
                StyledMenuItem {
                    text: "View: Grid Mode"
                    checkable: true
                    checked: backend ? backend.viewMode === "grid" : false
                    onTriggered: if (backend) backend.setViewMode("grid")
                }

                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }

                StyledMenuItem {
                    text: "Grid Style: Floating Preview"
                    checkable: true
                    checked: backend ? backend.gridStyle === "floating" : true
                    onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridStyle("floating"); }
                }
                StyledMenuItem {
                    text: "Grid Style: Framed Cards"
                    checkable: true
                    checked: backend ? backend.gridStyle === "cards" : false
                    onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridStyle("cards"); }
                }

                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }

                StyledMenu {
                    title: "Grid Columns"
                    iconGlyph: "🔢"

                    StyledMenuItem {
                        text: "Auto Fit (Responsive)"
                        checkable: true
                        checked: backend ? backend.gridColumns === 0 : true
                        onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridColumns(0); }
                    }
                    StyledMenuItem {
                        text: "3 Columns"
                        checkable: true
                        checked: backend ? backend.gridColumns === 3 : false
                        onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridColumns(3); }
                    }
                    StyledMenuItem {
                        text: "4 Columns"
                        checkable: true
                        checked: backend ? backend.gridColumns === 4 : false
                        onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridColumns(4); }
                    }
                    StyledMenuItem {
                        text: "5 Columns"
                        checkable: true
                        checked: backend ? backend.gridColumns === 5 : false
                        onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridColumns(5); }
                    }
                    StyledMenuItem {
                        text: "6 Columns"
                        checkable: true
                        checked: backend ? backend.gridColumns === 6 : false
                        onTriggered: if (backend) { backend.setViewMode("grid"); backend.setGridColumns(6); }
                    }
                }

                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }

                StyledMenuItem {
                    text: "Show Hidden Files (Dotfiles)"
                    shortcutText: "Ctrl+H"
                    checkable: true
                    checked: backend ? backend.showHidden : false
                    onTriggered: if (backend) backend.toggleShowHidden()
                }

                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }

                StyledMenuItem {
                    iconGlyph: "📂"
                    text: "Apply to All Subfolders"
                    onTriggered: if (backend) backend.applyCurrentLayoutToSubfolders()
                }
            }
        }

        ToolBtn {
            visible: !root.isUltraCompactBar
            iconText: "◨"
            isActiveToggle: root.appWindow ? root.appWindow.effectiveShowPreview : false
            onClicked: {
                if (root.appWindow) {
                    root.appWindow.userShowPreview = !root.appWindow.userShowPreview
                }
            }
        }

        ToolBtn {
            iconText: "⚙️"
            onClicked: settingsDialog.open()
        }
    }

    SettingsDialog {
        id: settingsDialog
    }
}
