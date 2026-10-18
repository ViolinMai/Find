import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    spacing: isUltraCompactBar ? 2 : Math.round(5 * Theme.scaleFactor)

    property var appWindow: null
    property bool isEditingPath: false
    property bool isSearchActive: false

    // Strict Priority Visibility Thresholds (Least Important hides first -> Most Important hides last):
    // Priority Order: 1. Path (Always) > 2. Search > 3. Settings > 4. Refresh > 5. New > 6. Toggle Columns (Sidebar/Preview)
    readonly property bool showColumnToggles: width >= Math.round(740 * Theme.scaleFactor)
    readonly property bool showNewBtn: width >= Math.round(580 * Theme.scaleFactor)
    readonly property bool showRefreshBtn: width >= Math.round(450 * Theme.scaleFactor)
    readonly property bool showSettingsBtn: width >= Math.round(340 * Theme.scaleFactor)
    readonly property bool showSearchBtn: width >= Math.round(220 * Theme.scaleFactor)

    readonly property bool isCompactBar: width < Math.round(720 * Theme.scaleFactor)
    readonly property bool isNarrowBar: !showColumnToggles
    readonly property bool isUltraCompactBar: !showNewBtn

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
        implicitWidth: showText ? Math.round(70 * Theme.scaleFactor) : Math.round((root.isNarrowBar ? 28 : 32) * Theme.scaleFactor)
        implicitHeight: Math.round((root.isNarrowBar ? 28 : 32) * Theme.scaleFactor)
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
            visible: root.showColumnToggles
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
            visible: root.showNewBtn
            iconText: "←"
            isEnabled: backend ? backend.canGoBack : false
            onClicked: if (backend) backend.goBack()
        }
        ToolBtn {
            visible: root.showColumnToggles
            iconText: "→"
            isEnabled: backend ? backend.canGoForward : false
            onClicked: if (backend) backend.goForward()
        }
        ToolBtn {
            visible: root.showColumnToggles
            iconText: "↑"
            isEnabled: true
            onClicked: if (backend) backend.goUp()
        }
        ToolBtn {
            visible: root.showRefreshBtn
            iconText: "⟳"
            isEnabled: true
            onClicked: if (backend) backend.syncJellyfinAndRefresh()
        }
    }

    // Center Address Bar (Protected minimum width so icons never collide!)
    Rectangle {
        Layout.fillWidth: true
        Layout.minimumWidth: Math.round(95 * Theme.scaleFactor)
        implicitHeight: Math.round((root.isNarrowBar ? 30 : 35) * Theme.scaleFactor)
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
                focus: visible
                enabled: visible
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
                focus: visible
                enabled: visible
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

            // Unified Search Filters Button + Rich Filter Popup
            Rectangle {
                id: searchFiltersBtn
                visible: root.isSearchActive
                Layout.alignment: Qt.AlignVCenter
                readonly property int filterCount: backend ? backend.activeSearchFilterCount : 0
                implicitWidth: filterBtnRow.implicitWidth + Math.round(14 * Theme.scaleFactor)
                implicitHeight: Math.round(24 * Theme.scaleFactor)
                radius: Theme.radiusSmall
                color: (searchFiltersPopup.visible || filterCount > 0) ? Theme.accent : (filterBtnMouse.containsMouse ? Theme.bgHover : Theme.bgCard)
                border.color: (searchFiltersPopup.visible || filterCount > 0) ? Theme.accentHover : Theme.borderDim
                border.width: 1

                RowLayout {
                    id: filterBtnRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "⚙️ Filters" + (searchFiltersBtn.filterCount > 0 ? (" (" + searchFiltersBtn.filterCount + ")") : " ▾")
                        color: (searchFiltersPopup.visible || searchFiltersBtn.filterCount > 0) ? "#ffffff" : Theme.textPrimary
                        font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                        font.bold: true
                    }
                }

                MouseArea {
                    id: filterBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (searchFiltersPopup.visible) {
                            searchFiltersPopup.close()
                        } else {
                            searchFiltersPopup.open()
                        }
                    }
                }

                Popup {
                    id: searchFiltersPopup
                    y: searchFiltersBtn.height + 6
                    x: Math.min(0, searchFiltersBtn.width - width)
                    width: Math.round(350 * Theme.scaleFactor)
                    padding: Math.round(12 * Theme.scaleFactor)
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                    background: Rectangle {
                        color: "#1e1e26"
                        radius: Theme.radiusLarge
                        border.color: Theme.accent
                        border.width: 1
                    }

                    contentItem: ColumnLayout {
                        spacing: Math.round(10 * Theme.scaleFactor)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "🔍 Search Filters & Match Options"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                visible: backend ? (backend.activeSearchFilterCount > 0) : false
                                implicitWidth: resetFltrTxt.implicitWidth + 12
                                implicitHeight: Math.round(20 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: resetFltrMouse.containsMouse ? "#35f87171" : Theme.bgCard
                                border.color: "#55f87171"
                                Text {
                                    id: resetFltrTxt
                                    anchors.centerIn: parent
                                    text: "↺ Reset"
                                    color: Theme.textDanger
                                    font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                    font.bold: true
                                }
                                MouseArea {
                                    id: resetFltrMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) backend.resetSearchFilters()
                                        extFilterInput.text = ""
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

                        // 1. Search Scope
                        Text {
                            text: "1. Search Scope (Location)"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { key: "current_only", icon: "📂", label: "Current Folder Only (No Subfolders)" },
                                    { key: "recursive", icon: "🗂️", label: "Current Folder & Subfolders" },
                                    { key: "everywhere", icon: "🌐", label: "Everywhere (All Indexed Drives)" }
                                ]
                                delegate: Rectangle {
                                    readonly property bool isChosen: backend ? (backend.searchScope === modelData.key) : (modelData.key === "recursive")
                                    Layout.fillWidth: true
                                    height: Math.round(28 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: isChosen ? "#300078d4" : (scopeOptMouse.containsMouse ? Theme.bgHover : Theme.bgCard)
                                    border.color: isChosen ? Theme.accent : Theme.borderDim
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        Text { text: modelData.icon; font.pixelSize: Theme.fontSizeSmall }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            color: parent.parent.isChosen ? Theme.textPrimary : Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: parent.parent.isChosen
                                        }
                                        Text {
                                            visible: parent.parent.isChosen
                                            text: "✔"
                                            color: Theme.accent
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        id: scopeOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend) backend.setSearchScope(modelData.key)
                                    }
                                }
                            }
                        }

                        // 2. Item Type Filter
                        Text {
                            text: "2. Target Type"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [
                                    { key: "all", label: "All Items" },
                                    { key: "folders", label: "📁 Folders Only" },
                                    { key: "files", label: "📄 Files Only" }
                                ]
                                delegate: Rectangle {
                                    readonly property bool isChosen: backend ? (backend.searchTargetType === modelData.key) : (modelData.key === "all")
                                    Layout.fillWidth: true
                                    height: Math.round(26 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: isChosen ? Theme.accent : (typeOptMouse.containsMouse ? Theme.bgHover : Theme.bgCard)
                                    border.color: isChosen ? Theme.accentHover : Theme.borderDim

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: parent.isChosen ? "#ffffff" : Theme.textSecondary
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: parent.isChosen
                                    }
                                    MouseArea {
                                        id: typeOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend) backend.setSearchTargetType(modelData.key)
                                    }
                                }
                            }
                        }

                        // 3. Matching Mode
                        Text {
                            text: "3. Matching Method"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: [
                                    { key: "contains", label: "Contains" },
                                    { key: "starts_with", label: "Starts With" },
                                    { key: "ends_with", label: "Ends With" },
                                    { key: "exact", label: "Exact Name" },
                                    { key: "regex", label: "Regex (.*)" }
                                ]
                                delegate: Rectangle {
                                    readonly property bool isChosen: backend ? (backend.searchMatchMode === modelData.key) : (modelData.key === "contains")
                                    implicitWidth: mLbl.implicitWidth + 14
                                    height: Math.round(25 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: isChosen ? Theme.accent : (mOptMouse.containsMouse ? Theme.bgHover : Theme.bgCard)
                                    border.color: isChosen ? Theme.accentHover : Theme.borderDim

                                    Text {
                                        id: mLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: parent.isChosen ? "#ffffff" : Theme.textSecondary
                                        font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                        font.bold: parent.isChosen
                                    }
                                    MouseArea {
                                        id: mOptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend) backend.setSearchMatchMode(modelData.key)
                                    }
                                }
                            }
                        }

                        // 4. File Extensions Filter
                        Text {
                            text: "4. Specific File Extension(s)"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        TextField {
                            id: extFilterInput
                            Layout.fillWidth: true
                            text: backend ? backend.searchExtFilter : ""
                            placeholderText: "e.g. mkv, mp4, py, rs, zip (Empty = All)"
                            color: Theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            selectByMouse: true
                            onTextChanged: if (backend) backend.setSearchExtFilter(text)
                            background: Rectangle {
                                implicitHeight: Math.round(28 * Theme.scaleFactor)
                                color: Theme.bgSurface
                                radius: Theme.radiusSmall
                                border.color: extFilterInput.activeFocus ? Theme.accent : Theme.borderDim
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: [
                                    { label: "🎬 Video", exts: "mkv,mp4,webm,avi,mov" },
                                    { label: "🖼️ Images", exts: "png,jpg,jpeg,webp,gif,svg" },
                                    { label: "🎵 Audio", exts: "mp3,flac,wav,ogg,m4a" },
                                    { label: "💻 Code", exts: "py,rs,qml,json,sh,c,cpp" },
                                    { label: "📦 Archives", exts: "zip,7z,rar,tar,gz,xz" }
                                ]
                                delegate: Rectangle {
                                    readonly property bool isPresetActive: extFilterInput.text === modelData.exts
                                    implicitWidth: prTxt.implicitWidth + 10
                                    height: Math.round(22 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: isPresetActive ? "#350078d4" : Theme.bgSurface
                                    border.color: isPresetActive ? Theme.accent : Theme.borderDim

                                    Text {
                                        id: prTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: parent.isPresetActive ? Theme.textPrimary : Theme.textTertiary
                                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                        font.bold: parent.isPresetActive
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (extFilterInput.text === modelData.exts) {
                                                extFilterInput.text = ""
                                            } else {
                                                extFilterInput.text = modelData.exts
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ToolBtn {
                visible: !root.isNarrowBar
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(26 * Theme.scaleFactor)
                implicitHeight: Math.round(26 * Theme.scaleFactor)
                iconText: "📋"
                onClicked: if (backend) backend.copyToClipboard(backend.currentPath)
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
            visible: root.showSearchBtn
            iconText: root.isSearchActive ? "✕" : "🔍"
            onClicked: root.toggleSearch()
        }

        ToolBtn {
            visible: root.showNewBtn
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
            visible: root.showColumnToggles
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
            visible: root.showNewBtn
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
            visible: root.showColumnToggles
            iconText: "◨"
            isActiveToggle: root.appWindow ? root.appWindow.effectiveShowPreview : false
            onClicked: {
                if (root.appWindow) {
                    root.appWindow.userShowPreview = !root.appWindow.userShowPreview
                }
            }
        }

        // Direct Resume Button inside Series/Anime Folder (Shows Episode Number + Time when space permits!)
        Rectangle {
            id: resumeBarBtn
            readonly property var resInfo: (backend && backend.currentPath && backend.isMediaLibraryView && !backend.isMovieFolderView)
                                           ? backend.getResumeFolderInfo(backend.currentPath)
                                           : ({ "has_resume": false, "ep_num": "", "time_str": "" })
            visible: resInfo && resInfo.has_resume === true
            implicitHeight: Math.round(28 * Theme.scaleFactor)
            implicitWidth: resumeRow.implicitWidth + 14
            radius: Theme.radiusMedium
            color: resumeMouse.containsMouse ? Theme.accentHover : Theme.accent
            Layout.alignment: Qt.AlignVCenter

            RowLayout {
                id: resumeRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                    text: {
                        if (!resumeBarBtn.resInfo || !resumeBarBtn.resInfo.has_resume) return "▶ Resume"
                        var base = "▶ Resume " + resumeBarBtn.resInfo.ep_num
                        if (!root.isCompactBar && resumeBarBtn.resInfo.time_str !== "") {
                            return base + " (" + resumeBarBtn.resInfo.time_str + ")"
                        }
                        return base
                    }
                    color: "#ffffff"
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }

            MouseArea {
                id: resumeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (backend) backend.resumeMediaFolder(backend.currentPath)
            }
        }

        // Anonymous Mode Indicator & Toggle Pill (Shift+A)
        Rectangle {
            visible: backend ? (backend.anonymousMode || backend.isMediaLibraryView || backend.isMediaHubView) : false
            implicitHeight: Math.round(28 * Theme.scaleFactor)
            implicitWidth: anonRow.implicitWidth + 14
            radius: Theme.radiusMedium
            color: (backend && backend.anonymousMode) ? "#35f59e0b" : Theme.bgCard
            border.color: (backend && backend.anonymousMode) ? "#f59e0b" : Theme.borderDim
            border.width: 1
            Layout.alignment: Qt.AlignVCenter

            RowLayout {
                id: anonRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: (backend && backend.anonymousMode) ? "🕵️ ANON: ON" : "🕵️ ANON"
                    color: (backend && backend.anonymousMode) ? "#fbbf24" : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Rectangle {
                    visible: !root.isUltraCompactBar
                    implicitWidth: anonKeyTxt.implicitWidth + 8
                    implicitHeight: Math.round(18 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: (backend && backend.anonymousMode) ? "#f59e0b" : Theme.bgSurface

                    Text {
                        id: anonKeyTxt
                        anchors.centerIn: parent
                        text: "Shift+A"
                        color: (backend && backend.anonymousMode) ? "#18181c" : Theme.textTertiary
                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                        font.bold: true
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (backend) backend.toggleAnonymousMode()
            }
        }

        // Media Library Active Pill & Subtitle ('C') Toggle Indicator
        Rectangle {
            visible: backend ? backend.isMediaLibraryView : false
            implicitHeight: Math.round(28 * Theme.scaleFactor)
            implicitWidth: mediaBadgeRow.implicitWidth + 14
            radius: Theme.radiusMedium
            color: (backend && backend.showSubtitlesInMedia) ? "#280078d4" : Theme.bgCard
            border.color: (backend && backend.showSubtitlesInMedia) ? Theme.accent : Theme.borderDim
            border.width: 1
            Layout.alignment: Qt.AlignVCenter

            RowLayout {
                id: mediaBadgeRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: (backend && backend.isMovieFolderView) ? "🎬 Movies" : "📺 Media"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Rectangle {
                    visible: !root.isUltraCompactBar
                    implicitWidth: subStateText.implicitWidth + 8
                    implicitHeight: Math.round(18 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: (backend && backend.showSubtitlesInMedia) ? Theme.accent : Theme.bgSurface

                    Text {
                        id: subStateText
                        anchors.centerIn: parent
                        text: (backend && backend.showSubtitlesInMedia) ? "SUB: ON (C)" : "SUB: HIDDEN (C)"
                        color: (backend && backend.showSubtitlesInMedia) ? "#ffffff" : Theme.textTertiary
                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                        font.bold: true
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (backend) backend.toggleSubtitlesInMedia()
            }
        }

        ToolBtn {
            visible: root.showSettingsBtn
            iconText: "⚙️"
            onClicked: settingsDialog.open()
        }

        // Compact Overflow Menu Button (Appears automatically as items hide in reverse priority order)
        ToolBtn {
            visible: !root.showColumnToggles
            iconText: "⋯"
            onClicked: overflowBarMenu.popup()

            StyledMenu {
                id: overflowBarMenu

                StyledMenuItem {
                    visible: !root.showRefreshBtn
                    iconGlyph: "⟳"
                    text: "Refresh & Sync Jellyfin (Ctrl+R)"
                    onTriggered: if (backend) backend.syncJellyfinAndRefresh()
                }
                StyledMenuItem {
                    visible: !root.showNewBtn
                    iconGlyph: "＋"
                    text: "New Item..."
                    onTriggered: newMenu.popup()
                }
                StyledMenuItem {
                    visible: !root.showColumnToggles
                    iconGlyph: "◧"
                    text: "Toggle Quick Access Sidebar"
                    checkable: true
                    checked: root.appWindow ? root.appWindow.userShowSidebar : true
                    onTriggered: if (root.appWindow) root.appWindow.userShowSidebar = !root.appWindow.userShowSidebar
                }
                StyledMenuItem {
                    visible: !root.showColumnToggles
                    iconGlyph: "📏"
                    text: "Icon-Only Quick Access Rail"
                    shortcutText: "Ctrl+I"
                    checkable: true
                    checked: root.appWindow ? root.appWindow.isSidebarCompactRail : false
                    onTriggered: {
                        if (!backend || !root.appWindow) return
                        if (root.appWindow.isSidebarCompactRail) {
                            backend.setSidebarMode("full")
                        } else {
                            backend.setSidebarMode("rail")
                        }
                    }
                }
                StyledMenuItem {
                    visible: !root.showColumnToggles
                    iconGlyph: "◨"
                    text: "Toggle Details Preview"
                    checkable: true
                    checked: root.appWindow ? root.appWindow.userShowPreview : false
                    onTriggered: if (root.appWindow) root.appWindow.userShowPreview = !root.appWindow.userShowPreview
                }
                StyledMenuItem {
                    visible: !root.showColumnToggles
                    iconGlyph: "↑"
                    text: "Go Up Folder"
                    onTriggered: if (backend) backend.goUp()
                }
                StyledMenuItem {
                    visible: !root.showColumnToggles
                    iconGlyph: "⇅"
                    text: "Sort By..."
                    onTriggered: sortMenu.popup()
                }
                StyledMenuItem {
                    iconGlyph: "📋"
                    text: "Copy Current Path"
                    onTriggered: if (backend) backend.copyToClipboard(backend.currentPath)
                }
                StyledMenuItem {
                    iconGlyph: "🕵️"
                    text: "Anonymous Mode (Local Only)"
                    shortcutText: "Shift+A"
                    checkable: true
                    checked: backend ? backend.anonymousMode : false
                    onTriggered: if (backend) backend.toggleAnonymousMode()
                }
                StyledMenuItem {
                    iconGlyph: "⟳"
                    text: "Sync Jellyfin & Refresh (Ctrl+R)"
                    onTriggered: if (backend) backend.syncJellyfinAndRefresh()
                }
                MenuSeparator {
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
                }
                StyledMenuItem {
                    iconGlyph: "⚙️"
                    text: "Settings"
                    onTriggered: settingsDialog.open()
                }
            }
        }
    }

    SettingsDialog {
        id: settingsDialog
    }
}
