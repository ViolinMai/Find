import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Find — Settings"
    width: Overlay.overlay ? Math.min(Math.round(880 * Theme.scaleFactor), Overlay.overlay.width - 20) : 900
    height: Overlay.overlay ? Math.min(Math.round(580 * Theme.scaleFactor), Overlay.overlay.height - 20) : 600
    modal: true
    anchors.centerIn: Overlay.overlay
    padding: 0

    property int currentCategory: 0
    property var hiddenItemsList: backend ? backend.getHiddenSidebarItems() : []
    property var customQAList: backend ? backend.getAllCustomQuickAccess() : []
    property var favoritesList: backend ? backend.getFavorites() : []
    property var mediaLibsList: backend ? backend.getMediaLibraries() : []
    property var savedDesktopList: backend ? backend.getSavedDesktopApps() : []
    property var defaultIconsMap: backend ? backend.getDefaultTypeIcons() : ({})
    property int selectedQAIndex: -1
    property string activePickerTarget: ""
    property string activeIconKeyTarget: ""

    IconBrowserDialog {
        id: settingsIconBrowser
        onIconChosen: function(chosenPath) {
            if (root.activeIconKeyTarget === "qa_icon") {
                iconInput.text = chosenPath
                if (root.selectedQAIndex >= 0 && root.selectedQAIndex < root.customQAList.length) {
                    var list = root.customQAList.slice()
                    list[root.selectedQAIndex] = {
                        "name": nameInput.text || list[root.selectedQAIndex].name,
                        "path": pathInput.text || list[root.selectedQAIndex].path,
                        "icon": chosenPath
                    }
                    root.customQAList = list
                    backend.saveCustomQuickAccess(list)
                }
            } else if (root.activeIconKeyTarget.startsWith("def_icon_")) {
                var key = root.activeIconKeyTarget.replace("def_icon_", "")
                backend.setDefaultTypeIcon(key, chosenPath)
                root.defaultIconsMap = backend.getDefaultTypeIcons()
            }
            root.activeIconKeyTarget = ""
        }
    }

    Connections {
        target: backend
        function onPickerCompleted(paths) {
            if (paths.length > 0 && root.activePickerTarget !== "") {
                var selected = paths[0]
                if (root.activePickerTarget === "qa_path") {
                    pathInput.text = selected
                } else if (root.activePickerTarget === "qa_icon") {
                    iconInput.text = selected
                } else if (root.activePickerTarget === "fav_add") {
                    backend.addToFavorites(selected)
                    root.favoritesList = backend.getFavorites()
                } else if (root.activePickerTarget === "fonts_dir") {
                    backend.setFontsInstallDir(selected)
                } else if (root.activePickerTarget === "startup_path") {
                    backend.setStartupPath(selected)
                } else if (root.activePickerTarget === "media_lib_series") {
                    backend.addMediaLibrary(selected, "series")
                    root.mediaLibsList = backend.getMediaLibraries()
                } else if (root.activePickerTarget === "media_lib_movies") {
                    backend.addMediaLibrary(selected, "movies")
                    root.mediaLibsList = backend.getMediaLibraries()
                } else if (root.activePickerTarget.startsWith("def_icon_")) {
                    var key = root.activePickerTarget.replace("def_icon_", "")
                    backend.setDefaultTypeIcon(key, selected)
                    root.defaultIconsMap = backend.getDefaultTypeIcons()
                }
                root.activePickerTarget = ""
            }
        }
        function onMediaLibraryStateChanged() {
            if (backend) root.mediaLibsList = backend.getMediaLibraries()
        }
        function onFavoritesUpdated() {
            if (backend) root.favoritesList = backend.getFavorites()
        }
        function onSidebarUpdated() {
            if (backend) root.customQAList = backend.getAllCustomQuickAccess()
        }
        function onDesktopAppsUpdated() {
            if (backend) root.savedDesktopList = backend.getSavedDesktopApps()
        }
    }

    // Reusable UI Building Blocks for Modern Settings
    component SectionCard: Rectangle {
        default property alias cardContent: innerCol.data
        property string sectionTitle: ""
        property string sectionSubtitle: ""
        Layout.fillWidth: true
        implicitHeight: innerCol.implicitHeight + Math.round(28 * Theme.scaleFactor)
        color: Theme.bgCard
        radius: Theme.radiusLarge
        border.color: Theme.borderDim
        border.width: 1

        ColumnLayout {
            id: innerCol
            anchors.fill: parent
            anchors.margins: Math.round(14 * Theme.scaleFactor)
            spacing: Math.round(10 * Theme.scaleFactor)

            ColumnLayout {
                visible: sectionTitle !== ""
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: sectionTitle
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }
                Text {
                    visible: sectionSubtitle !== ""
                    Layout.fillWidth: true
                    text: sectionSubtitle
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    height: 1
                    color: Theme.borderDim
                }
            }
        }
    }

    component ActionBtn: Button {
        property bool isPrimary: false
        property bool isDanger: false
        contentItem: Text {
            text: parent.text
            color: parent.isDanger ? Theme.textDanger : (parent.isPrimary ? "#ffffff" : Theme.textPrimary)
            font.bold: parent.isPrimary || parent.isDanger
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: Math.max(Math.round(88 * Theme.scaleFactor), parent.contentItem.implicitWidth + 22)
            implicitHeight: Math.round(30 * Theme.scaleFactor)
            radius: Theme.radiusMedium
            color: parent.isPrimary
                   ? (parent.hovered ? Theme.accentHover : Theme.accent)
                   : (parent.hovered ? Theme.bgHover : Theme.bgSurface)
            border.color: parent.isPrimary ? Theme.accentHover : (parent.isDanger ? "#55f87171" : Theme.borderDim)
            border.width: 1
        }
    }

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.borderDim
        border.width: 1
        radius: Theme.radiusLarge
        clip: true
    }

    header: Rectangle {
        height: Math.round(48 * Theme.scaleFactor)
        color: "#16161b"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 12

            Text {
                text: "⚙️  Find Preferences & System Integration"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: Math.round(28 * Theme.scaleFactor)
                height: Math.round(28 * Theme.scaleFactor)
                radius: Theme.radiusMedium
                color: closeSetMouse.containsMouse ? "#35f87171" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: closeSetMouse.containsMouse ? Theme.textDanger : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }
                MouseArea {
                    id: closeSetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // LEFT NAVIGATION SIDEBAR
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.round(195 * Theme.scaleFactor)
            color: "#15151a"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                Repeater {
                    model: [
                        { icon: "🎨", title: "Appearance & UI" },
                        { icon: "⭐", title: "Quick Access & Favs" },
                        { icon: "📺", title: "Media Library & HDR" },
                        { icon: "🎬", title: "MPV Profiles" },
                        { icon: "🚀", title: "System & .desktop" },
                        { icon: "🔤", title: "Fonts & Icons" }
                    ]

                    delegate: Rectangle {
                        readonly property bool activeCat: root.currentCategory === index
                        Layout.fillWidth: true
                        height: Math.round(36 * Theme.scaleFactor)
                        radius: Theme.radiusMedium
                        color: activeCat ? Theme.accent : (navMouse.containsMouse ? Theme.bgHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: modelData.icon
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: parent.parent.activeCat ? "#ffffff" : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: parent.parent.activeCat
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentCategory = index
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.round(44 * Theme.scaleFactor)
                    radius: Theme.radiusMedium
                    color: Theme.bgCard
                    border.color: Theme.borderDim

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            text: "Cache: " + (backend ? backend.currentCacheSize : "0 B")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "Wayland Native Engine"
                            color: Theme.textTertiary
                            font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                height: parent.height
                width: 1
                color: Theme.borderDim
            }
        }

        // RIGHT CONTENT PAGES
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentCategory

            // =================================================================
            // PAGE 0: APPEARANCE, LAYOUT & CACHE
            // =================================================================
            ScrollView {
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width - 28
                    x: 14
                    y: 14
                    spacing: 14

                    SectionCard {
                        sectionTitle: "Visual Layout & Grid Presentation"
                        sectionSubtitle: "Configure how folders, thumbnails, and sidebars adapt across Hyprland tiles."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Grid Item Style:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            ActionBtn {
                                text: "✨ Floating Preview"
                                isPrimary: backend ? backend.gridStyle === "floating" : true
                                onClicked: if (backend) backend.setGridStyle("floating")
                            }
                            ActionBtn {
                                text: "🃏 Framed Cards"
                                isPrimary: backend ? backend.gridStyle === "cards" : false
                                onClicked: if (backend) backend.setGridStyle("cards")
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "Sidebar Mode:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Repeater {
                                model: [
                                    { key: "auto", label: "Auto" },
                                    { key: "full", label: "Full" },
                                    { key: "rail", label: "Icon Rail" },
                                    { key: "topbar", label: "Top Bar" }
                                ]
                                delegate: ActionBtn {
                                    text: modelData.label
                                    isPrimary: backend ? backend.sidebarMode === modelData.key : false
                                    onClicked: if (backend) backend.setSidebarMode(modelData.key)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Translucent Window Background (Hyprland Blur):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.transparentBlur : false
                                onToggled: if (backend) backend.transparentBlur = checked
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Show Hidden Dotfiles (Ctrl+H):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.showHidden : false
                                onToggled: if (backend) backend.setShowHidden(checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Swap Left & Right Mouse Button Roles:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.swapMouseButtons : false
                                onToggled: if (backend) backend.setSwapMouseButtons(checked)
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "Thumbnail Cache & Storage"
                        sectionSubtitle: "High-speed rounded thumbnails are cached on disk and automatically pruned."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Allocated Cache Limit: " + Math.round(cacheSlider.value) + " MB"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            ActionBtn {
                                text: "🗑️ Clear Cache (" + (backend ? backend.currentCacheSize : "0 B") + ")"
                                isDanger: true
                                onClicked: if (backend) backend.clearCache()
                            }
                        }

                        Slider {
                            id: cacheSlider
                            Layout.fillWidth: true
                            from: 100
                            to: 4000
                            stepSize: 50
                            value: backend ? backend.maxCacheMb : 500
                            onMoved: if (backend) backend.setMaxCacheMb(Math.round(value))
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 1: QUICK ACCESS & FAVORITES ORDERING
            // =================================================================
            ScrollView {
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width - 28
                    x: 14
                    y: 14
                    spacing: 14

                    SectionCard {
                        sectionTitle: "⭐ Favorites (Pinned Files & Folders)"
                        sectionSubtitle: "Pin any file or folder from anywhere for 1-click access and reorder them freely."

                        RowLayout {
                            Layout.fillWidth: true
                            ActionBtn {
                                text: "＋ Pin Folder to Favorites..."
                                isPrimary: true
                                onClicked: {
                                    root.activePickerTarget = "fav_add"
                                    backend.openInternalPicker("folder", "", "Select Folder to Pin to Favorites")
                                }
                            }
                            ActionBtn {
                                text: "📄 Pin File to Favorites..."
                                onClicked: {
                                    root.activePickerTarget = "fav_add"
                                    backend.openInternalPicker("file", "", "Select File to Pin to Favorites")
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.favoritesList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(36 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text { text: modelData.icon || "⭐"; font.pixelSize: Theme.fontSizeNormal }
                                        Text {
                                            text: modelData.name
                                            color: Theme.textPrimary
                                            font.bold: true
                                            font.pixelSize: Theme.fontSizeNormal
                                            Layout.preferredWidth: 130
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.path
                                            color: Theme.textTertiary
                                            font.pixelSize: Theme.fontSizeSmall
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }
                                        ActionBtn {
                                            text: "▲"
                                            enabled: index > 0
                                            onClicked: if (backend) backend.moveFavoriteItem(index, index - 1)
                                        }
                                        ActionBtn {
                                            text: "▼"
                                            enabled: index < root.favoritesList.length - 1
                                            onClicked: if (backend) backend.moveFavoriteItem(index, index + 1)
                                        }
                                        ActionBtn {
                                            text: "✕"
                                            isDanger: true
                                            onClicked: if (backend) backend.removeFromFavorites(modelData.path)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "⚡ Quick Access Locations & Ordering"
                        sectionSubtitle: "Reorder, customize, or add standard Quick Access folders in the sidebar."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.customQAList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(36 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: root.selectedQAIndex === index ? Theme.bgSelected : Theme.bgSurface
                                    border.color: root.selectedQAIndex === index ? Theme.accent : Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Item {
                                            width: Math.round(22 * Theme.scaleFactor)
                                            height: Math.round(22 * Theme.scaleFactor)
                                            readonly property bool isImgIcon: modelData.icon && (modelData.icon.indexOf("/") !== -1 || modelData.icon.indexOf(".") !== -1)
                                            Image {
                                                anchors.fill: parent
                                                visible: parent.isImgIcon
                                                source: visible ? ("file://" + modelData.icon) : ""
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 48
                                                sourceSize.height: 48
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                visible: !parent.isImgIcon
                                                text: modelData.icon || "📁"
                                                font.pixelSize: Theme.fontSizeNormal
                                            }
                                        }
                                        Text {
                                            text: modelData.name
                                            color: Theme.textPrimary
                                            font.bold: true
                                            Layout.preferredWidth: 110
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.path
                                            color: Theme.textTertiary
                                            font.pixelSize: Theme.fontSizeSmall
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }
                                        ActionBtn {
                                            text: "✎"
                                            onClicked: {
                                                root.selectedQAIndex = index
                                                nameInput.text = modelData.name
                                                pathInput.text = modelData.path
                                                iconInput.text = modelData.icon
                                            }
                                        }
                                        ActionBtn {
                                            text: "▲"
                                            enabled: index > 0
                                            onClicked: if (backend) backend.moveQuickAccessItem(index, index - 1)
                                        }
                                        ActionBtn {
                                            text: "▼"
                                            enabled: index < root.customQAList.length - 1
                                            onClicked: if (backend) backend.moveQuickAccessItem(index, index + 1)
                                        }
                                        ActionBtn {
                                            text: "✕"
                                            isDanger: true
                                            onClicked: {
                                                var list = root.customQAList.slice()
                                                list.splice(index, 1)
                                                root.customQAList = list
                                                backend.saveCustomQuickAccess(list)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        GridLayout {
                            columns: 3
                            Layout.fillWidth: true
                            rowSpacing: 6
                            columnSpacing: 8

                            Text { text: "Label:"; color: Theme.textSecondary }
                            TextField {
                                id: nameInput
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                placeholderText: "Shortcut Name"
                                color: Theme.textPrimary
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "Folder:"; color: Theme.textSecondary }
                            TextField {
                                id: pathInput
                                Layout.fillWidth: true
                                placeholderText: "/path/to/folder"
                                color: Theme.textPrimary
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                            ActionBtn {
                                text: "Browse..."
                                onClicked: {
                                    root.activePickerTarget = "qa_path"
                                    backend.openInternalPicker("folder", "", "Select Quick Access Folder")
                                }
                            }

                            Text { text: "Icon:"; color: Theme.textSecondary }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    width: Math.round(28 * Theme.scaleFactor)
                                    height: Math.round(28 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim
                                    readonly property bool isImg: iconInput.text.indexOf("/") !== -1 || iconInput.text.indexOf(".") !== -1
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        visible: parent.isImg
                                        source: visible ? ("file://" + iconInput.text) : ""
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 48
                                        sourceSize.height: 48
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !parent.isImg
                                        text: iconInput.text !== "" ? iconInput.text : "📁"
                                        font.pixelSize: Theme.fontSizeNormal
                                    }
                                }
                                TextField {
                                    id: iconInput
                                    Layout.fillWidth: true
                                    placeholderText: "Emoji or pick an icon..."
                                    color: Theme.textPrimary
                                    background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                                }
                            }
                            ActionBtn {
                                text: "🖼️ Pick Icon..."
                                onClicked: {
                                    root.activeIconKeyTarget = "qa_icon"
                                    settingsIconBrowser.openIconBrowser("")
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            ActionBtn {
                                text: "💾 Update Selected"
                                isPrimary: true
                                enabled: root.selectedQAIndex >= 0
                                onClicked: {
                                    if (root.selectedQAIndex >= 0 && root.selectedQAIndex < root.customQAList.length) {
                                        var list = root.customQAList.slice()
                                        list[root.selectedQAIndex] = {
                                            "name": nameInput.text,
                                            "path": pathInput.text,
                                            "icon": iconInput.text || "📁"
                                        }
                                        root.customQAList = list
                                        backend.saveCustomQuickAccess(list)
                                    }
                                }
                            }
                            ActionBtn {
                                text: "＋ Add New Shortcut"
                                onClicked: {
                                    var list = root.customQAList.slice()
                                    list.push({
                                        "name": nameInput.text || "Shortcut",
                                        "path": pathInput.text || backend.currentPath,
                                        "icon": iconInput.text || "📁"
                                    })
                                    root.customQAList = list
                                    backend.saveCustomQuickAccess(list)
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 2: MEDIA LIBRARY, ANIME RESUME & HDR DAEMON
            // =================================================================
            ScrollView {
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width - 28
                    x: 14
                    y: 14
                    spacing: 14

                    SectionCard {
                        sectionTitle: "Jellyfin Server Integration (Optional Sync & Chapters)"
                        sectionSubtitle: "Syncs watch progress, official episode titles, synopsis, and injects chapter segments into MPV for your Skipper. Automatically falls back to local mode if token is empty or server is unreachable."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Enable Jellyfin Integration:"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                id: jfEnabledSwitch
                                checked: backend ? backend.jellyfinEnabled : true
                            }
                        }

                        GridLayout {
                            columns: 2
                            Layout.fillWidth: true
                            rowSpacing: 8
                            columnSpacing: 10

                            Text { text: "Server URL:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: jfUrlInput
                                Layout.fillWidth: true
                                text: backend ? backend.jellyfinUrl : "http://localhost:8096"
                                placeholderText: "http://localhost:8096"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "API Token:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: jfTokenInput
                                Layout.fillWidth: true
                                text: backend ? backend.jellyfinToken : ""
                                placeholderText: "Paste Jellyfin API Key here (Leave empty for 100% local mode)"
                                echoMode: TextInput.PasswordEchoOnEdit
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Show Official Vertical Poster on Series / Anime Folders (Level 2 Folders):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch {
                                checked: backend ? backend.showSeriesPosters : true
                                onToggled: if (backend) backend.setShowSeriesPosters(checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Stream Video via Jellyfin HTTP URL (Instead of Local Path + IPC Chapter Injection):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch {
                                id: jfStreamSwitch
                                checked: backend ? backend.jellyfinStreamMode : false
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionBtn {
                                text: "💾 Save Jellyfin Config"
                                isPrimary: true
                                onClicked: {
                                    if (backend) {
                                        backend.saveJellyfinConfig(
                                            jfEnabledSwitch.checked,
                                            jfUrlInput.text,
                                            jfTokenInput.text,
                                            jfStreamSwitch.checked
                                        )
                                    }
                                }
                            }
                            ActionBtn {
                                text: "🔌 Test Connection"
                                onClicked: {
                                    if (backend) {
                                        backend.testJellyfinConnection(jfUrlInput.text, jfTokenInput.text)
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "HDR Auto-Switching & MPV Background Daemon"
                        sectionSubtitle: "Tracks episode progress in real time, enables direct folder resume, and switches HDR on/off."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Auto-Play HDR Videos with toggle-hdr.sh:"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.autoPlayHdr : true
                                onToggled: if (backend) backend.setAutoPlayHdr(checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: (backend && backend.isDaemonRunning) ? "#10b981" : "#f87171"
                            }
                            Text {
                                text: (backend && backend.isDaemonRunning) ? "Daemon Status: Active" : "Daemon Status: Stopped"
                                color: Theme.textPrimary
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            ActionBtn {
                                text: (backend && backend.isDaemonInstalled) ? "🔄 Reinstall Service" : "⚡ Install systemd Service"
                                isPrimary: true
                                onClicked: if (backend) backend.installOrSaveDaemonService("")
                            }
                            ActionBtn {
                                text: "↻ Restart"
                                onClicked: if (backend) backend.restartMediaDaemon()
                            }
                            ActionBtn {
                                text: "⏹ Stop"
                                onClicked: if (backend) backend.stopMediaDaemon()
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "Registered Media Libraries (Series / Anime / Movies)"
                        sectionSubtitle: "Right-click any anime folder to 'Resume' directly from where you left off."

                        RowLayout {
                            spacing: 8
                            ActionBtn {
                                text: "＋ Add Series / Anime Folder..."
                                isPrimary: true
                                onClicked: {
                                    root.activePickerTarget = "media_lib_series"
                                    backend.openInternalPicker("folder", "", "Select Series / Anime Root Folder")
                                }
                            }
                            ActionBtn {
                                text: "🎬 Add Movies Folder..."
                                onClicked: {
                                    root.activePickerTarget = "media_lib_movies"
                                    backend.openInternalPicker("folder", "", "Select Movies Root Folder")
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.mediaLibsList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(40 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text { text: modelData.mode === "movies" ? "🎬" : "📺"; font.pixelSize: Theme.fontSizeMedium }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { text: modelData.name; color: Theme.textPrimary; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: modelData.path; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                        }
                                        ActionBtn {
                                            text: modelData.mode === "movies" ? "Movies" : "Series"
                                            onClicked: {
                                                var nextMode = modelData.mode === "movies" ? "series" : "movies"
                                                backend.setMediaLibraryMode(modelData.path, nextMode)
                                            }
                                        }
                                        ActionBtn {
                                            text: "Remove"
                                            isDanger: true
                                            onClicked: backend.removeMediaLibrary(modelData.path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 3: MPV PROFILES (BOTH / SDR / HDR)
            // =================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                SectionCard {
                    Layout.fillHeight: true
                    sectionTitle: "MPV Configuration Profiles (~/.config/mpv/mpv.conf)"
                    sectionSubtitle: "Settings in 'SDR' or 'HDR' automatically override keys in 'Both'."

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text { text: "1. Both (Shared Base & Subs)"; color: Theme.accent; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                TextArea {
                                    id: mpvBothEditor
                                    text: backend ? backend.getMpvBothConfig() : ""
                                    color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall
                                    selectByMouse: true; wrapMode: TextEdit.NoWrap
                                    background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text { text: "2. SDR Overrides"; color: "#34d399"; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                TextArea {
                                    id: mpvSdrEditor
                                    text: backend ? backend.getMpvSdrConfig() : ""
                                    color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall
                                    selectByMouse: true; wrapMode: TextEdit.NoWrap
                                    background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text { text: "3. HDR Overrides"; color: "#fbbf24"; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                TextArea {
                                    id: mpvHdrEditor
                                    text: backend ? backend.getMpvHdrConfig() : ""
                                    color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall
                                    selectByMouse: true; wrapMode: TextEdit.NoWrap
                                    background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionBtn {
                            text: "💾 Save MPV Profiles"
                            isPrimary: true
                            onClicked: {
                                if (backend) {
                                    backend.saveMpvConfigs(mpvBothEditor.text, mpvSdrEditor.text, mpvHdrEditor.text)
                                    mpvSavedLabel.text = "✔ Updated ~/.config/mpv/mpv.conf"
                                }
                            }
                        }
                        ActionBtn {
                            text: "↺ Reset Defaults"
                            onClicked: {
                                if (backend) {
                                    backend.resetMpvConfigsToDefault()
                                    mpvBothEditor.text = backend.getMpvBothConfig()
                                    mpvSdrEditor.text = backend.getMpvSdrConfig()
                                    mpvHdrEditor.text = backend.getMpvHdrConfig()
                                }
                            }
                        }
                        Text {
                            id: mpvSavedLabel
                            text: ""
                            color: "#34d399"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 4: SYSTEM DEFAULT FILE MANAGER & SAVED .DESKTOP APPS
            // =================================================================
            ScrollView {
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width - 28
                    x: 14
                    y: 14
                    spacing: 14

                    SectionCard {
                        sectionTitle: "Startup Behavior & Session Persistence"
                        sectionSubtitle: "Continue right where you left off across tabs, or boot into a dedicated starting folder."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Restore Last Open Tabs & Session on Startup:"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.restoreLastSession : true
                                onToggled: if (backend) backend.setRestoreLastSession(checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Fresh Boot Starting Location:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                            }
                            TextField {
                                Layout.fillWidth: true
                                text: backend ? backend.startupPath : ""
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                onEditingFinished: if (backend) backend.setStartupPath(text)
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                            ActionBtn {
                                text: "⭐ Favorites"
                                isPrimary: backend ? (backend.startupPath === "favorites://") : false
                                onClicked: if (backend) backend.setStartupPath("favorites://")
                            }
                            ActionBtn {
                                text: "📂 Browse..."
                                onClicked: {
                                    root.activePickerTarget = "startup_path"
                                    backend.openInternalPicker("folder", "", "Select Default Startup Folder")
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "System Default File Manager & Browser Integration"
                        sectionSubtitle: "Registers Find with xdg-mime (inode/directory) and org.freedesktop.FileManager1 D-Bus service so Firefox downloads, 'Open Containing Folder', and file pickers route directly to Find."

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: (backend && backend.isDefaultFileManager) ? "#10b981" : "#f59e0b"
                            }
                            Text {
                                text: (backend && backend.isDefaultFileManager)
                                      ? "Find is registered as your Default File Manager (find.desktop)"
                                      : "Find is not currently set as the default inode/directory handler"
                                color: Theme.textPrimary
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            ActionBtn {
                                text: "⚡ Set as Default File Manager"
                                isPrimary: true
                                onClicked: if (backend) backend.setAsDefaultFileManager()
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "Automated .desktop Applications Registry"
                        sectionSubtitle: "All applications created via Right-Click → 'Add to Applications (.desktop)' are saved here for reuse."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                visible: root.savedDesktopList.length === 0
                                text: "No custom .desktop applications created yet. Right-click any executable file to create one."
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Repeater {
                                model: root.savedDesktopList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(42 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text { text: "🚀"; font.pixelSize: Theme.fontSizeMedium }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text { text: modelData.name; color: Theme.textPrimary; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: modelData.exec_cmd; color: Theme.textTertiary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                        }
                                        ActionBtn {
                                            text: "🗑️ Remove"
                                            isDanger: true
                                            onClicked: if (backend) backend.removeSavedDesktopApp(modelData.desktop_file)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "Hidden Sidebar Items"
                        sectionSubtitle: "Restore any sidebar drives or shortcuts you previously hid."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: root.hiddenItemsList
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: modelData; color: Theme.textSecondary; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                    ActionBtn {
                                        text: "Restore"
                                        onClicked: {
                                            backend.restoreSidebarItem(modelData)
                                            root.hiddenItemsList = backend.getHiddenSidebarItems()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 5: FONTS DIRECTORY & DEFAULT FILE ICONS
            // =================================================================
            ScrollView {
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width - 28
                    x: 14
                    y: 14
                    spacing: 14

                    SectionCard {
                        sectionTitle: "🔤 Font Installation / Download Target Directory"
                        sectionSubtitle: "When clicking 'Install / Download Font(s)' in the context menu, font files (.ttf, .otf, .woff) are copied here and indexed with fc-cache."

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                id: fontsDirField
                                Layout.fillWidth: true
                                text: backend ? backend.fontsInstallDir : ""
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                onEditingFinished: if (backend) backend.setFontsInstallDir(text)
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                            ActionBtn {
                                text: "Browse Folder..."
                                isPrimary: true
                                onClicked: {
                                    root.activePickerTarget = "fonts_dir"
                                    backend.openInternalPicker("folder", "", "Select Fonts Installation Directory")
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "Default File & Folder Icons"
                        sectionSubtitle: "Customize fallback glyphs or custom image icons for file types."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: [
                                    { key: "folder", label: "Folder Icon" },
                                    { key: "file", label: "Generic File Icon" },
                                    { key: "image", label: "Image Files Icon" },
                                    { key: "video", label: "Video Files Icon" },
                                    { key: "audio", label: "Audio Files Icon" },
                                    { key: "py", label: "Python Script Icon" },
                                    { key: "rs", label: "Rust Source Icon" },
                                    { key: "json", label: "JSON Document Icon" },
                                    { key: "archive", label: "Archive Files Icon" }
                                ]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(36 * Theme.scaleFactor)
                                    color: Theme.bgSurface
                                    radius: Theme.radiusSmall
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text {
                                            Layout.preferredWidth: 150
                                            text: modelData.label
                                            color: Theme.textPrimary
                                            font.bold: true
                                        }

                                        // Visual Icon Preview Box (Renders actual SVG/PNG/ICO image instead of raw path string!)
                                        Rectangle {
                                            width: Math.round(28 * Theme.scaleFactor)
                                            height: Math.round(28 * Theme.scaleFactor)
                                            radius: Theme.radiusSmall
                                            color: Theme.bgCard
                                            border.color: Theme.borderDim
                                            readonly property string rawIconVal: root.defaultIconsMap[modelData.key] || ""
                                            readonly property bool isImageFile: rawIconVal.indexOf("/") !== -1 || rawIconVal.indexOf(".") !== -1

                                            Image {
                                                anchors.fill: parent
                                                anchors.margins: 3
                                                visible: parent.isImageFile
                                                source: visible ? ("file://" + parent.rawIconVal) : ""
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 64
                                                sourceSize.height: 64
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                visible: !parent.isImageFile
                                                text: parent.rawIconVal !== "" ? parent.rawIconVal : "📄"
                                                font.pixelSize: Theme.fontSizeMedium
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: {
                                                var v = root.defaultIconsMap[modelData.key] || "-"
                                                if (v.indexOf("/") !== -1) {
                                                    var parts = v.split("/")
                                                    return parts[parts.length - 1]
                                                }
                                                return v
                                            }
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideMiddle
                                        }

                                        ActionBtn {
                                            text: "🖼️ Pick Icon..."
                                            isPrimary: true
                                            onClicked: {
                                                root.activeIconKeyTarget = "def_icon_" + modelData.key
                                                settingsIconBrowser.openIconBrowser("")
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
