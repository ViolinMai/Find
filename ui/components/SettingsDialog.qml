import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: root.mediaOnlyMode ? "Find — Media Settings" : "Find — Settings"
    width: Overlay.overlay ? Math.min(Math.round(880 * Theme.scaleFactor), Overlay.overlay.width - 20) : 900
    height: Overlay.overlay ? Math.min(Math.round(580 * Theme.scaleFactor), Overlay.overlay.height - 20) : 600
    modal: true
    anchors.centerIn: Overlay.overlay
    padding: 0

    property bool mediaOnlyMode: false
    property int currentCategory: mediaOnlyMode ? 2 : 0

    function openMediaSettings() {
        root.mediaOnlyMode = true
        root.currentCategory = 2
        root.open()
    }
    property var hiddenItemsList: backend ? backend.getHiddenSidebarItems() : []
    property var customQAList: backend ? backend.getAllCustomQuickAccess() : []
    property var favoritesList: backend ? backend.getFavorites() : []
    property var recentFoldersList: backend ? backend.getRecentWatchedFolders() : []
    property var mediaLibsList: backend ? backend.getMediaLibraries() : []
    property var mediaHubRowsList: backend ? backend.getMediaHubRowConfig() : []
    property int mediaHubHiddenCount: backend ? backend.getMediaHubHiddenCount() : 0
    property var ignoredAiringList: backend ? backend.getIgnoredAiringItems() : []
    property var savedDesktopList: backend ? backend.getSavedDesktopApps() : []
    property var defaultIconsMap: backend ? backend.getDefaultTypeIcons() : ({})
    property var notifConfig: backend ? backend.getNotificationSettings() : ({})
    property var trackedWorksNotifList: backend ? backend.getTrackedWorksNotificationList() : []
    property var groupOpenRulesList: backend ? backend.getExtensionGroupRules() : []
    property var extOpenRulesList: backend ? backend.getExtensionRulesAndIcons() : []
    property var installedDesktopAppsList: []
    property int selectedQAIndex: -1
    property string activePickerTarget: ""
    property string activeIconKeyTarget: ""
    property bool showCustomColorPicker: false
    property real pickerHue: 0.58
    property real pickerSat: 0.85
    property real pickerVal: 0.90

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
            } else if (root.activeIconKeyTarget.startsWith("ext_icon_")) {
                var extKey = root.activeIconKeyTarget.replace("ext_icon_", "")
                backend.setCustomExtensionIcon(extKey, chosenPath)
                root.extOpenRulesList = backend.getExtensionRulesAndIcons()
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
                } else if (root.activePickerTarget === "recent_folder_add") {
                    backend.addRecentWatchedFolder(selected)
                    root.recentFoldersList = backend.getRecentWatchedFolders()
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
        function onMediaHubConfigChanged() {
            if (backend) {
                root.mediaHubRowsList = backend.getMediaHubRowConfig()
                root.mediaHubHiddenCount = backend.getMediaHubHiddenCount()
                root.ignoredAiringList = backend.getIgnoredAiringItems()
            }
        }
        function onFavoritesUpdated() {
            if (backend) root.favoritesList = backend.getFavorites()
        }
        function onRecentFoldersChanged() {
            if (backend) root.recentFoldersList = backend.getRecentWatchedFolders()
        }
        function onSidebarUpdated() {
            if (backend) root.customQAList = backend.getAllCustomQuickAccess()
        }
        function onDesktopAppsUpdated() {
            if (backend) root.savedDesktopList = backend.getSavedDesktopApps()
        }
        function onNotificationSettingsChanged() {
            if (backend) {
                root.notifConfig = backend.getNotificationSettings()
                root.trackedWorksNotifList = backend.getTrackedWorksNotificationList()
            }
        }
        function onDefaultOpenRulesChanged() {
            if (backend) {
                root.groupOpenRulesList = backend.getExtensionGroupRules()
                root.extOpenRulesList = backend.getExtensionRulesAndIcons()
            }
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

    component StyledCheckChip: Rectangle {
        property string label: ""
        property bool checked: false
        signal toggled(bool isChecked)

        implicitWidth: chipRow.implicitWidth + Math.round(20 * Theme.scaleFactor)
        implicitHeight: Math.round(30 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: checked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : (chipMouse.containsMouse ? Theme.bgHover : Theme.bgSurface)
        border.color: checked ? Theme.accent : Theme.borderDim
        border.width: 1

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Math.round(7 * Theme.scaleFactor)

            Rectangle {
                width: Math.round(16 * Theme.scaleFactor)
                height: Math.round(16 * Theme.scaleFactor)
                radius: Math.round(4 * Theme.scaleFactor)
                color: parent.parent.checked ? Theme.accent : Theme.bgCard
                border.color: parent.parent.checked ? Theme.accentHover : Theme.textTertiary
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    visible: parent.parent.parent.checked
                    text: "✔"
                    color: "#ffffff"
                    font.pixelSize: Math.round(10 * Theme.scaleFactor)
                    font.bold: true
                }
            }

            Text {
                text: parent.parent.label
                color: parent.parent.checked ? Theme.textPrimary : Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: parent.parent.checked
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                parent.checked = !parent.checked
                parent.toggled(parent.checked)
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
                text: root.mediaOnlyMode ? "🎬  Media Hub & Playback Settings" : "⚙️  Find Preferences & System Integration"
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
                    model: root.mediaOnlyMode
                           ? [
                               { icon: "📺", title: "Media Hub & Rows", pageIdx: 2 },
                               { icon: "🔔", title: "Notification Center", pageIdx: 3 },
                               { icon: "🎬", title: "MPV Profiles", pageIdx: 4 }
                             ]
                           : [
                               { icon: "🎨", title: "Appearance & UI", pageIdx: 0 },
                               { icon: "⭐", title: "Quick Access & Favs", pageIdx: 1 },
                               { icon: "📺", title: "Media Hub & Rows", pageIdx: 2 },
                               { icon: "🔔", title: "Notification Center", pageIdx: 3 },
                               { icon: "🎬", title: "MPV Profiles", pageIdx: 4 },
                               { icon: "🚀", title: "System & .desktop", pageIdx: 5 },
                               { icon: "📂", title: "Default Open & Fonts", pageIdx: 6 },
                               { icon: "🐍", title: "Python Automations", pageIdx: 7 }
                             ]

                    delegate: Rectangle {
                        readonly property bool activeCat: root.currentCategory === modelData.pageIdx
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(36 * Theme.scaleFactor)
                        implicitHeight: Math.round(36 * Theme.scaleFactor)
                        radius: Theme.radiusMedium
                        color: activeCat ? (root.mediaOnlyMode ? Theme.mhAccent : Theme.accent) : (navMouse.containsMouse ? Theme.bgHover : "transparent")

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
                            onClicked: {
                                root.currentCategory = modelData.pageIdx
                                if (modelData.pageIdx === 6 && backend) {
                                    root.groupOpenRulesList = backend.getExtensionGroupRules()
                                    root.extOpenRulesList = backend.getExtensionRulesAndIcons()
                                }
                            }
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
                        sectionTitle: "🎨 Theme Accent Color & Custom Color Picker"
                        sectionSubtitle: "Choose any custom accent color for Find. Your last 5 chosen colors are automatically saved for 1-click switching."

                        // Row 1: Current Active Color + HEX Input + Toggle Color Picker Button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: Math.round(34 * Theme.scaleFactor)
                                height: Math.round(34 * Theme.scaleFactor)
                                radius: Theme.radiusMedium
                                color: Theme.accent
                                border.color: "#ffffff"
                                border.width: 1.5
                            }

                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: "Active Theme Color"
                                    color: Theme.textPrimary
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeNormal
                                }
                                Text {
                                    text: backend ? backend.accentColor.toUpperCase() : "#0078D4"
                                    color: Theme.textTertiary
                                    font.family: "monospace"
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            Item { Layout.fillWidth: true }

                            TextField {
                                id: customHexInput
                                implicitWidth: Math.round(105 * Theme.scaleFactor)
                                text: backend ? backend.accentColor : "#0078d4"
                                placeholderText: "#RRGGBB"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeNormal
                                selectByMouse: true
                                onAccepted: {
                                    if (backend && text.trim() !== "") {
                                        backend.setAccentColor(text.trim())
                                    }
                                }
                                background: Rectangle {
                                    implicitHeight: Math.round(30 * Theme.scaleFactor)
                                    color: Theme.bgSurface
                                    radius: Theme.radiusSmall
                                    border.color: customHexInput.activeFocus ? Theme.accent : Theme.borderDim
                                }
                            }

                            ActionBtn {
                                text: "✔ Apply HEX"
                                isPrimary: true
                                onClicked: {
                                    if (backend && customHexInput.text.trim() !== "") {
                                        backend.setAccentColor(customHexInput.text.trim())
                                    }
                                }
                            }

                            ActionBtn {
                                text: root.showCustomColorPicker ? "▲ Hide Color Picker" : "🌈 Open Color Picker"
                                onClicked: root.showCustomColorPicker = !root.showCustomColorPicker
                            }
                        }

                        // Interactive HSV Color Picker Panel
                        Rectangle {
                            visible: root.showCustomColorPicker
                            Layout.fillWidth: true
                            implicitHeight: hsvPickerCol.implicitHeight + 20
                            radius: Theme.radiusMedium
                            color: Theme.bgSurface
                            border.color: Theme.accent
                            border.width: 1

                            ColumnLayout {
                                id: hsvPickerCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                readonly property color livePreviewColor: Qt.hsva(root.pickerHue, root.pickerSat, root.pickerVal, 1.0)

                                // 2D Hue/Saturation Spectrum Canvas
                                Rectangle {
                                    id: spectrumBox
                                    Layout.fillWidth: true
                                    height: Math.round(125 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    border.color: Theme.borderDim
                                    clip: true

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.00; color: "#ff0000" }
                                        GradientStop { position: 0.17; color: "#ffff00" }
                                        GradientStop { position: 0.33; color: "#00ff00" }
                                        GradientStop { position: 0.50; color: "#00ffff" }
                                        GradientStop { position: 0.67; color: "#0000ff" }
                                        GradientStop { position: 0.83; color: "#ff00ff" }
                                        GradientStop { position: 1.00; color: "#ff0000" }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: "#00ffffff" }
                                            GradientStop { position: 1.0; color: "#ffffffff" }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#000000"
                                        opacity: 1.0 - root.pickerVal
                                    }

                                    // Crosshair Indicator
                                    Rectangle {
                                        x: Math.max(0, Math.min(spectrumBox.width - width, root.pickerHue * spectrumBox.width - width / 2))
                                        y: Math.max(0, Math.min(spectrumBox.height - height, (1.0 - root.pickerSat) * spectrumBox.height - height / 2))
                                        width: Math.round(16 * Theme.scaleFactor)
                                        height: width
                                        radius: width / 2
                                        color: hsvPickerCol.livePreviewColor
                                        border.color: "#ffffff"
                                        border.width: 2
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.CrossCursor
                                        function updateFromMouse(mx, my) {
                                            root.pickerHue = Math.max(0.0, Math.min(0.999, mx / Math.max(1, spectrumBox.width)))
                                            root.pickerSat = Math.max(0.0, Math.min(1.0, 1.0 - (my / Math.max(1, spectrumBox.height))))
                                            customHexInput.text = Qt.hsva(root.pickerHue, root.pickerSat, root.pickerVal, 1.0).toString()
                                        }
                                        onPressed: function(mouse) { updateFromMouse(mouse.x, mouse.y) }
                                        onPositionChanged: function(mouse) {
                                            if (pressed) updateFromMouse(mouse.x, mouse.y)
                                        }
                                    }
                                }

                                // Brightness / Value Slider
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "Brightness:"
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                    }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 0.15
                                        to: 1.0
                                        value: root.pickerVal
                                        onMoved: {
                                            root.pickerVal = value
                                            customHexInput.text = Qt.hsva(root.pickerHue, root.pickerSat, root.pickerVal, 1.0).toString()
                                        }
                                    }
                                    Rectangle {
                                        width: Math.round(28 * Theme.scaleFactor)
                                        height: Math.round(28 * Theme.scaleFactor)
                                        radius: Theme.radiusSmall
                                        color: hsvPickerCol.livePreviewColor
                                        border.color: "#ffffff"
                                        border.width: 1
                                    }
                                    ActionBtn {
                                        text: "✨ Apply Picked Color"
                                        isPrimary: true
                                        onClicked: {
                                            var cHex = hsvPickerCol.livePreviewColor.toString()
                                            customHexInput.text = cHex
                                            if (backend) backend.setAccentColor(cHex)
                                        }
                                    }
                                }
                            }
                        }

                        // Row 2: Last 5 Saved Colors (Recent History)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "🕒 Your Last 5 Saved Colors (Click to switch):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: backend ? backend.recentAccentColors : []
                                    delegate: Rectangle {
                                        readonly property bool isCurrentColor: (backend ? backend.accentColor.toLowerCase() : "") === String(modelData).toLowerCase()
                                        implicitWidth: swatchRow.implicitWidth + 16
                                        height: Math.round(30 * Theme.scaleFactor)
                                        radius: Theme.radiusMedium
                                        color: swatchMouse.containsMouse ? Theme.bgHover : Theme.bgSurface
                                        border.color: isCurrentColor ? modelData : Theme.borderDim
                                        border.width: isCurrentColor ? 2 : 1

                                        RowLayout {
                                            id: swatchRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Rectangle {
                                                width: Math.round(16 * Theme.scaleFactor)
                                                height: Math.round(16 * Theme.scaleFactor)
                                                radius: width / 2
                                                color: modelData
                                                border.color: "#66ffffff"
                                                border.width: 1
                                            }

                                            Text {
                                                text: String(modelData).toUpperCase()
                                                color: parent.parent.isCurrentColor ? Theme.textPrimary : Theme.textSecondary
                                                font.family: "monospace"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: parent.parent.isCurrentColor
                                            }
                                        }

                                        MouseArea {
                                            id: swatchMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                customHexInput.text = modelData
                                                if (backend) backend.setAccentColor(modelData)
                                            }
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        // Row 3: Curated Preset Palette
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Presets:"
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            Repeater {
                                model: ["#0078d4", "#38bdf8", "#8b5cf6", "#ec4899", "#ef4444", "#f59e0b", "#10b981", "#14b8a6", "#6366f1"]
                                delegate: Rectangle {
                                    width: Math.round(22 * Theme.scaleFactor)
                                    height: Math.round(22 * Theme.scaleFactor)
                                    radius: width / 2
                                    color: modelData
                                    border.color: (backend && backend.accentColor.toLowerCase() === modelData) ? "#ffffff" : "#40ffffff"
                                    border.width: (backend && backend.accentColor.toLowerCase() === modelData) ? 2 : 1

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            customHexInput.text = modelData
                                            if (backend) backend.setAccentColor(modelData)
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

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

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Mouse Wheel Scroll Speed Multiplier: " + (backend ? backend.scrollSpeedMultiplier.toFixed(2) + "x" : "1.25x")
                                    color: Theme.textPrimary
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeNormal
                                    Layout.fillWidth: true
                                }
                                ActionBtn {
                                    text: "Reset (1.25x)"
                                    onClicked: if (backend) backend.setScrollSpeedMultiplier(1.25)
                                }
                            }
                            Slider {
                                id: scrollSpeedSlider
                                Layout.fillWidth: true
                                from: 0.4
                                to: 3.5
                                stepSize: 0.05
                                value: backend ? backend.scrollSpeedMultiplier : 1.25
                                onPressedChanged: {
                                    if (!pressed && backend) {
                                        backend.setScrollSpeedMultiplier(value)
                                    }
                                }
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
                            onPressedChanged: {
                                if (!pressed && backend) {
                                    backend.setMaxCacheMb(Math.round(value))
                                }
                            }
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
                        sectionTitle: "🕒 Recently Added Monitored Folders"
                        sectionSubtitle: "Select specific folders to scan for 'Recently Added'. If no folders are added here, Find scans all standard folders and mounted drives across the system."

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionBtn {
                                text: "＋ Add Monitored Folder..."
                                isPrimary: true
                                onClicked: {
                                    root.activePickerTarget = "recent_folder_add"
                                    backend.openInternalPicker("folder", "", "Select Folder to Monitor for Recently Added")
                                }
                            }
                            ActionBtn {
                                text: "🌐 Reset to All System Drives"
                                enabled: root.recentFoldersList.length > 0
                                onClicked: if (backend) backend.clearRecentWatchedFolders()
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            visible: root.recentFoldersList.length === 0
                            text: "Currently monitoring: All System Drives & User Folders (Default)"
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: root.recentFoldersList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(34 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text { text: "🕒"; font.pixelSize: Theme.fontSizeNormal }
                                        Text {
                                            text: modelData
                                            color: Theme.textPrimary
                                            font.family: "monospace"
                                            font.pixelSize: Theme.fontSizeSmall
                                            horizontalAlignment: Text.AlignLeft
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }
                                        ActionBtn {
                                            text: "✕"
                                            isDanger: true
                                            onClicked: if (backend) backend.removeRecentWatchedFolder(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "⚡ Quick Access Locations & Ordering (All Sidebar Items)"
                        sectionSubtitle: "Toggle visibility, reorder (including Media Hub, Favorites, Recently Added, Trash), edit icons, or add custom folders."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.customQAList
                                delegate: Rectangle {
                                    readonly property bool isItemVisible: modelData.visible !== false
                                    readonly property bool isVirtualBuiltIn: modelData.path === "mediahub://" || modelData.path === "favorites://" || modelData.path === "recent://" || modelData.path === "trash://"
                                    Layout.fillWidth: true
                                    height: Math.round(38 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: root.selectedQAIndex === index ? Theme.bgSelected : Theme.bgSurface
                                    border.color: root.selectedQAIndex === index ? Theme.accent : (isItemVisible ? Theme.borderDim : "transparent")
                                    opacity: isItemVisible ? 1.0 : 0.55

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Switch {
                                            checked: parent.parent.isItemVisible
                                            onToggled: if (backend) backend.setQuickAccessItemVisible(index, checked)
                                        }

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
                                            Layout.preferredWidth: 115
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
                                            visible: !parent.parent.isVirtualBuiltIn
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
                                        var prevVis = list[root.selectedQAIndex].visible !== false
                                        list[root.selectedQAIndex] = {
                                            "name": nameInput.text,
                                            "path": pathInput.text,
                                            "icon": iconInput.text || "📁",
                                            "visible": prevVis
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
                                        "icon": iconInput.text || "📁",
                                        "visible": true
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
                            Text {
                                text: "Auto Fullscreen in MPV when playing Media:"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.mpvAutoFullscreen : true
                                onToggled: if (backend) backend.setMpvAutoFullscreen(checked)
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
                        sectionTitle: "🎨 Media Hub Exclusive Theme (--mh & Media Hub View)"
                        sectionSubtitle: "Changes background, card, and accent colors strictly inside Media Hub without modifying your primary file manager theme."

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "obsidian", name: "Obsidian Indigo", card: "#161924", acc: "#6366f1" },
                                    { id: "oled", name: "OLED Pitch Black", card: "#0f0f12", acc: "#38bdf8" },
                                    { id: "crimson", name: "Cinema Crimson", card: "#241117", acc: "#f43f5e" },
                                    { id: "violet", name: "Amethyst Night", card: "#1c1430", acc: "#a855f7" },
                                    { id: "emerald", name: "Emerald Matrix", card: "#102620", acc: "#10b981" },
                                    { id: "ocean", name: "Deep Ocean", card: "#102232", acc: "#0ea5e9" },
                                    { id: "match_app", name: "Match Main App", card: Theme.bgCard, acc: Theme.accent }
                                ]

                                delegate: Rectangle {
                                    width: Math.round(145 * Theme.scaleFactor)
                                    height: Math.round(38 * Theme.scaleFactor)
                                    radius: Theme.radiusMedium
                                    color: modelData.card
                                    border.color: (backend && backend.mediaHubTheme === modelData.id) ? modelData.acc : Theme.borderDim
                                    border.width: (backend && backend.mediaHubTheme === modelData.id) ? 2 : 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        Rectangle {
                                            width: Math.round(12 * Theme.scaleFactor)
                                            height: width
                                            radius: width / 2
                                            color: modelData.acc
                                        }
                                        Text {
                                            text: modelData.name
                                            color: Theme.textPrimary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: backend && backend.mediaHubTheme === modelData.id
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (backend) backend.setMediaHubTheme(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "🎬 Media Hub Rows & Anonymous Mode (Shift+A)"
                        sectionSubtitle: "Customize the order and visibility of rows inside Media Hub (mediahub://), and control Anonymous playback mode."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "🕵️ Anonymous Mode (Shift+A) — Play Locally Without Sending Progress to Jellyfin:"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch {
                                checked: backend ? backend.anonymousMode : false
                                onToggled: if (backend) backend.setAnonymousMode(checked)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.mediaHubRowsList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(38 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: modelData.visible ? Theme.borderDim : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Switch {
                                            checked: Boolean(modelData.visible)
                                            onToggled: if (backend) backend.setMediaHubRowVisible(modelData.id, checked)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            color: modelData.visible ? Theme.textPrimary : Theme.textTertiary
                                            font.bold: modelData.visible
                                            font.pixelSize: Theme.fontSizeNormal
                                            elide: Text.ElideRight
                                        }

                                        ActionBtn {
                                            text: "▲"
                                            enabled: index > 0
                                            onClicked: if (backend) backend.moveMediaHubRow(index, index - 1)
                                        }

                                        ActionBtn {
                                            text: "▼"
                                            enabled: index < root.mediaHubRowsList.length - 1
                                            onClicked: if (backend) backend.moveMediaHubRow(index, index + 1)
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: "Hidden Continue-Watching / Hub Items: " + root.mediaHubHiddenCount
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            ActionBtn {
                                text: "👁️ Unhide All Hub Items"
                                enabled: root.mediaHubHiddenCount > 0
                                onClicked: if (backend) backend.clearMediaHubHiddenItems()
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "📡 Weekly Airing Tracker (CriticalweebR18 MAL + AniList)"
                        sectionSubtitle: "Syncs MAL list every 30m and AniList schedules every 6h with rate-limit protection, caches posters locally, and sends desktop notifications via the daemon."

                        GridLayout {
                            columns: 2
                            Layout.fillWidth: true
                            rowSpacing: 8
                            columnSpacing: 10

                            Text { text: "MAL Username:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: malUserInput
                                Layout.fillWidth: true
                                text: backend ? backend.malUsername : ""
                                placeholderText: "Enter your MyAnimeList username"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "MAL Client ID:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: malClientIdInput
                                Layout.fillWidth: true
                                text: backend ? backend.malClientId : ""
                                placeholderText: "Optional MAL API v2 Client ID (Uses public fallback if empty)"
                                echoMode: TextInput.PasswordEchoOnEdit
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "MAL Access Token:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: malTokenInput
                                Layout.fillWidth: true
                                text: backend ? backend.malAccessToken : ""
                                placeholderText: "Optional OAuth2 Bearer Token"
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
                            spacing: 8
                            ActionBtn {
                                text: "💾 Save Airing Credentials"
                                isPrimary: true
                                onClicked: {
                                    if (backend) {
                                        backend.saveAiringConfig(malUserInput.text, malClientIdInput.text, malTokenInput.text)
                                    }
                                }
                            }
                            ActionBtn {
                                text: "🔄 Force Sync MAL & AniList Now"
                                onClicked: if (backend) backend.forceSyncAiringNow()
                            }
                            ActionBtn {
                                text: "⛓️‍💥 Clear All Folder Links"
                                isDanger: true
                                onClicked: if (backend) backend.clearAllAiringLinks()
                            }
                        }

                        Rectangle {
                            visible: root.ignoredAiringList.length > 0
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.borderDim
                        }

                        RowLayout {
                            visible: root.ignoredAiringList.length > 0
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Ignored Airing Anime (" + root.ignoredAiringList.length + "):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            ActionBtn {
                                text: "Restore All Ignored"
                                onClicked: if (backend) backend.clearAllIgnoredAiringItems()
                            }
                        }

                        ColumnLayout {
                            visible: root.ignoredAiringList.length > 0
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.ignoredAiringList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(32 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title + " (ID: " + modelData.id + ")"
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                        }
                                        ActionBtn {
                                            text: "↩ Restore"
                                            onClicked: if (backend) backend.restoreIgnoredAiringItem(modelData.id)
                                        }
                                    }
                                }
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
            // PAGE 3: NOTIFICATION CENTER (COMPREHENSIVE APP & MEDIA HUB ALERTS)
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
                        sectionTitle: "🔔 Global Notification Center"
                        sectionSubtitle: "Master controls for all OS Desktop notifications (notify-send) and in-app status toast banners across Find."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Enable All Notifications (Master Switch):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: root.notifConfig.master_enabled !== false
                                onToggled: if (backend) backend.updateNotificationSetting("master_enabled", checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Enable OS Desktop Notifications (System Tray / Dunst / SwayNC / Mako):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: root.notifConfig.os_notifications_enabled !== false
                                onToggled: if (backend) backend.updateNotificationSetting("os_notifications_enabled", checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Enable In-App Floating Toast Notifications:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: root.notifConfig.in_app_toasts_enabled !== false
                                onToggled: if (backend) backend.updateNotificationSetting("in_app_toasts_enabled", checked)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "OS Notification Urgency & Timeout:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                            }
                            Repeater {
                                model: [
                                    { k: "low", lbl: "Low" },
                                    { k: "normal", lbl: "Normal" },
                                    { k: "critical", lbl: "Critical" }
                                ]
                                delegate: ActionBtn {
                                    text: modelData.lbl
                                    isPrimary: (root.notifConfig.urgency || "normal") === modelData.k
                                    onClicked: if (backend) backend.updateNotificationSetting("urgency", modelData.k)
                                }
                            }
                            ActionBtn {
                                text: "🔔 Send Test Notification"
                                isPrimary: true
                                onClicked: if (backend) backend.sendTestNotification()
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "In-App Toast Categories:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                height: Math.round(30 * Theme.scaleFactor)
                                verticalAlignment: Text.AlignVCenter
                            }
                            StyledCheckChip {
                                label: "File Ops"
                                checked: root.notifConfig.toast_file_ops !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("toast_file_ops", val) }
                            }
                            StyledCheckChip {
                                label: "Archives"
                                checked: root.notifConfig.toast_archive_ops !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("toast_archive_ops", val) }
                            }
                            StyledCheckChip {
                                label: "Jellyfin Sync"
                                checked: root.notifConfig.toast_jellyfin_sync !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("toast_jellyfin_sync", val) }
                            }
                            StyledCheckChip {
                                label: "Clipboard"
                                checked: root.notifConfig.toast_clipboard !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("toast_clipboard", val) }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "⏰ Media Hub Timing & Reminder Rules"
                        sectionSubtitle: "Configure when notifications arrive: at episode release, a pre-airing reminder before it airs, and a follow-up reminder if you haven't watched it yet."

                        // 1. On Airing Release
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "📡 Notify Immediately When Episode Airs (On Release Time):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: root.notifConfig.airing_on_release !== false
                                onToggled: if (backend) backend.updateNotificationSetting("airing_on_release", checked)
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

                        // 2. Pre-Airing Reminder
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "⏳ Pre-Airing Reminder (Notify Before Episode Airs):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: Boolean(root.notifConfig.airing_pre_reminder_enabled)
                                onToggled: if (backend) backend.updateNotificationSetting("airing_pre_reminder_enabled", checked)
                            }
                        }

                        RowLayout {
                            visible: Boolean(root.notifConfig.airing_pre_reminder_enabled)
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "When to send Pre-Airing Reminder:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                            }
                            Repeater {
                                model: [
                                    { m: 15, lbl: "15m before" },
                                    { m: 30, lbl: "30m before" },
                                    { m: 60, lbl: "1h before" },
                                    { m: 120, lbl: "2h before" }
                                ]
                                delegate: ActionBtn {
                                    text: modelData.lbl
                                    isPrimary: Number(root.notifConfig.airing_pre_reminder_minutes || 30) === modelData.m
                                    onClicked: if (backend) backend.updateNotificationSetting("airing_pre_reminder_minutes", modelData.m)
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

                        // 3. Unwatched Follow-up Reminder
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "📌 Unwatched Episode Reminder (Notify if you haven't watched after release):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: root.notifConfig.airing_unwatched_reminder_enabled !== false
                                onToggled: if (backend) backend.updateNotificationSetting("airing_unwatched_reminder_enabled", checked)
                            }
                        }

                        RowLayout {
                            visible: root.notifConfig.airing_unwatched_reminder_enabled !== false
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "Remind me if still unwatched after:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                            }
                            Repeater {
                                model: [
                                    { h: 3, lbl: "3 Hours" },
                                    { h: 6, lbl: "6 Hours" },
                                    { h: 12, lbl: "12 Hours" },
                                    { h: 24, lbl: "24 Hours" },
                                    { h: 48, lbl: "2 Days" }
                                ]
                                delegate: ActionBtn {
                                    text: modelData.lbl
                                    isPrimary: Number(root.notifConfig.airing_unwatched_reminder_hours || 12) === modelData.h
                                    onClicked: if (backend) backend.updateNotificationSetting("airing_unwatched_reminder_hours", modelData.h)
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "📝 Notification Content & Template Customization"
                        sectionSubtitle: "Choose what details appear inside Media Hub notifications. Placeholders: {title}, {ep}, {watched}, {behind}, {status}, {event_label}"

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledCheckChip {
                                label: "🖼️ Show Anime Poster Icon"
                                checked: root.notifConfig.airing_content_show_poster !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("airing_content_show_poster", val) }
                            }
                            StyledCheckChip {
                                label: "🔢 Show Episode Number"
                                checked: root.notifConfig.airing_content_show_ep !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("airing_content_show_ep", val) }
                            }
                            StyledCheckChip {
                                label: "📊 Show Local Watched Progress"
                                checked: root.notifConfig.airing_content_show_progress !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("airing_content_show_progress", val) }
                            }
                            StyledCheckChip {
                                label: "⏳ Show Behind Status"
                                checked: root.notifConfig.airing_content_show_behind !== false
                                onToggled: function(val) { if (backend) backend.updateNotificationSetting("airing_content_show_behind", val) }
                            }
                        }

                        GridLayout {
                            columns: 2
                            Layout.fillWidth: true
                            rowSpacing: 8
                            columnSpacing: 10

                            Text { text: "Title Format:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: notifTitleTplInput
                                Layout.fillWidth: true
                                text: root.notifConfig.airing_title_template || "🎬 {title} — Episode {ep}"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                onEditingFinished: if (backend) backend.updateNotificationSetting("airing_title_template", text)
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "Body Format:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: notifBodyTplInput
                                Layout.fillWidth: true
                                text: root.notifConfig.airing_body_template || "{event_label}\\nLocal Progress: {watched} eps ({status})"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                onEditingFinished: if (backend) backend.updateNotificationSetting("airing_body_template", text)
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "📺 Per-Work Notification Selection (All ON by Default)"
                        sectionSubtitle: "Select which airing works in your Media Hub send notifications. All tracked works are enabled by default."

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionBtn {
                                text: "🔔 Enable All Works"
                                isPrimary: true
                                onClicked: if (backend) backend.setAllWorksNotificationsEnabled(true)
                            }
                            ActionBtn {
                                text: "🔕 Mute All Works"
                                onClicked: if (backend) backend.setAllWorksNotificationsEnabled(false)
                            }
                            ActionBtn {
                                text: "🔄 Refresh List"
                                onClicked: if (backend) root.trackedWorksNotifList = backend.getTrackedWorksNotificationList()
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            visible: root.trackedWorksNotifList.length === 0
                            text: "No active airing works found in local cache yet. Click 'Force Sync MAL & AniList' in the Media Library tab."
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.trackedWorksNotifList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(44 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: modelData.enabled ? Theme.borderDim : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Text {
                                            text: modelData.enabled ? "🔔" : "🔕"
                                            font.pixelSize: Theme.fontSizeMedium
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: modelData.enabled ? Theme.textPrimary : Theme.textTertiary
                                                font.bold: modelData.enabled
                                                font.pixelSize: Theme.fontSizeNormal
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Next: EP " + modelData.next_ep + "  •  Local Watched: " + modelData.watched_eps + " eps"
                                                color: Theme.textTertiary
                                                font.pixelSize: Theme.fontSizeSmall
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Switch {
                                            checked: Boolean(modelData.enabled)
                                            onToggled: if (backend) backend.setWorkNotificationEnabled(modelData.id, checked)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 4: MPV PROFILES (BOTH / SDR / HDR)
            // =================================================================
            Item {
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
                                    mpvSavedLabel.text = "✔ Updated ~/.config/find/mpv_find.conf"
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
                            Text {
                                text: "Keep Find Resident in Background on Window Close (Instant Re-open):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: backend ? backend.keepAliveInBackground : true
                                onToggled: if (backend) backend.setKeepAliveInBackground(checked)
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
                                text: "🎬 Media Hub"
                                isPrimary: backend ? (backend.startupPath === "mediahub://") : false
                                onClicked: if (backend) backend.setStartupPath("mediahub://")
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
            // PAGE 7: PYTHON AUTOMATIONS & SCRIPTING ENGINE
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
                        sectionTitle: "🐍 Deep Python Automation & Batch Scripts"
                        sectionSubtitle: "Create custom Python scripts to manipulate selected files, batch rename, transcode via FFmpeg, or fetch metadata. Scripts receive the current directory and selections via Environment Variables."

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: autoInfoCol.implicitHeight + 16
                            color: Theme.bgSurface
                            radius: Theme.radiusMedium
                            border.color: Theme.borderDim

                            ColumnLayout {
                                id: autoInfoCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4

                                Text {
                                    text: "Script Execution Context & Environment Variables:"
                                    color: Theme.accent
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Text {
                                    text: "• os.environ['FIND_CURRENT_PATH']   → Absolute path of active folder\n• os.environ['FIND_SELECTED_PATHS'] → Multi-line list of selected items\n• os.environ['FIND_SELECTED_FILE']  → Primary selected file path"
                                    color: Theme.textPrimary
                                    font.family: "monospace"
                                    font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                                }
                                Text {
                                    text: "Scripts Folder: " + (backend ? backend.getAutomationsDirectory() : "~/.config/find/scripts")
                                    color: Theme.textTertiary
                                    font.family: "monospace"
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        GridLayout {
                            columns: 3
                            Layout.fillWidth: true
                            rowSpacing: 8
                            columnSpacing: 10

                            Text { text: "Automation Name:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: autoNameInput
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                placeholderText: "e.g. Extract Subs & Audio / Batch WebP Convert"
                                color: Theme.textPrimary
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "Script Path (.py):"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: autoPathInput
                                Layout.fillWidth: true
                                placeholderText: "/home/user/.config/find/scripts/task.py"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                            ActionBtn {
                                text: "Browse Script..."
                                isPrimary: true
                                onClicked: {
                                    root.activePickerTarget = "custom_script_pick"
                                    backend.openInternalPicker("file", "*.py;*.sh", "Select Script File")
                                }
                            }

                            Text { text: "Shortcut Key:"; color: Theme.textSecondary; font.bold: true }
                            TextField {
                                id: autoShortcutInput
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                placeholderText: "e.g. Ctrl+Shift+E (Optional)"
                                color: Theme.textPrimary
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }

                            Text { text: "Description:"; color: Theme.textSecondary }
                            TextField {
                                id: autoDescInput
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                placeholderText: "Short description of what the automation does"
                                color: Theme.textPrimary
                                selectByMouse: true
                                background: Rectangle { color: Theme.bgSurface; radius: 4; border.color: Theme.borderDim }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Run in visible Terminal window (for interactive scripts / CLI prompts):"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                            }
                            Switch {
                                id: autoTermSwitch
                                checked: false
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionBtn {
                                text: "💾 Save Automation"
                                isPrimary: true
                                enabled: autoNameInput.text.trim() !== "" && autoPathInput.text.trim() !== ""
                                onClicked: {
                                    if (backend) {
                                        backend.saveCustomAutomation(
                                            autoNameInput.text,
                                            autoPathInput.text,
                                            autoShortcutInput.text,
                                            autoDescInput.text,
                                            autoTermSwitch.checked
                                        )
                                        autoNameInput.text = ""
                                        autoPathInput.text = ""
                                        autoShortcutInput.text = ""
                                        autoDescInput.text = ""
                                    }
                                }
                            }
                            ActionBtn {
                                text: "📂 Open Scripts Folder in Find"
                                onClicked: if (backend) backend.navigateTo(backend.getAutomationsDirectory())
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "⚡ Registered Automations"
                        sectionSubtitle: "Your installed automation tasks. Click Run to test on active directory/selection."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: backend ? backend.getCustomAutomations() : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(44 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text { text: "🐍"; font.pixelSize: Theme.fontSizeMedium }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            RowLayout {
                                                spacing: 8
                                                Text { text: modelData.name; color: Theme.textPrimary; font.bold: true; font.pixelSize: Theme.fontSizeNormal }
                                                Rectangle {
                                                    visible: modelData.shortcut !== ""
                                                    implicitWidth: scTxtAuto.implicitWidth + 8
                                                    implicitHeight: Math.round(18 * Theme.scaleFactor)
                                                    radius: Theme.radiusSmall
                                                    color: Theme.bgCard
                                                    border.color: Theme.borderDim
                                                    Text {
                                                        id: scTxtAuto
                                                        anchors.centerIn: parent
                                                        text: modelData.shortcut
                                                        color: Theme.accent
                                                        font.bold: true
                                                        font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                    }
                                                }
                                            }
                                            Text { text: modelData.description || modelData.script_path; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }

                                        ActionBtn {
                                            text: "▶ Run"
                                            isPrimary: true
                                            onClicked: if (backend) backend.runAutomationByName(modelData.name)
                                        }

                                        ActionBtn {
                                            text: "🗑️"
                                            isDanger: true
                                            onClicked: if (backend) backend.removeCustomAutomation(modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // PAGE 6: DEFAULT OPEN APPS, FONTS & PER-EXTENSION VECTOR ICONS
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
                        sectionTitle: "📂 Smart App Icon Fallback & Custom Openers"
                        sectionSubtitle: "Assign custom applications to open specific extension groups or individual extensions instead of the system default. Folders, Videos, and Images keep their native previews."

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Use Primary Application Icon when Extension has no Bundled Icon (Excludes Folders, Videos, Images):"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch {
                                checked: backend ? backend.useAppIconFallback : true
                                onToggled: if (backend) backend.setUseAppIconFallback(checked)
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "🗂️ Category / Group Default Openers"
                        sectionSubtitle: "Override the default application for an entire category of files (e.g., open all Coding files in VS Code or Zed)."

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.groupOpenRulesList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(46 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: modelData.app_cmd !== "" ? Theme.accent : Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: modelData.title
                                                color: Theme.textPrimary
                                                font.bold: true
                                                font.pixelSize: Theme.fontSizeNormal
                                            }
                                            Text {
                                                text: modelData.extensions_preview
                                                color: Theme.textTertiary
                                                font.family: "monospace"
                                                font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: grpAppTxt.implicitWidth + 14
                                            implicitHeight: Math.round(24 * Theme.scaleFactor)
                                            radius: Theme.radiusSmall
                                            color: modelData.app_cmd !== "" ? "#280078d4" : Theme.bgCard
                                            border.color: modelData.app_cmd !== "" ? Theme.accent : Theme.borderDim
                                            Text {
                                                id: grpAppTxt
                                                anchors.centerIn: parent
                                                text: modelData.app_name
                                                color: modelData.app_cmd !== "" ? Theme.accent : Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: modelData.app_cmd !== ""
                                            }
                                        }

                                        ActionBtn {
                                            text: "⚡ Choose App..."
                                            isPrimary: true
                                            onClicked: appChooserDialog.openForGroup(modelData.key, modelData.title, modelData.app_cmd)
                                        }

                                        ActionBtn {
                                            visible: modelData.app_cmd !== ""
                                            text: "↺ Reset"
                                            isDanger: true
                                            onClicked: if (backend) backend.setExtensionGroupRule(modelData.key, "", "")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        sectionTitle: "🧩 Per-Extension Vector Icons & Default Openers"
                        sectionSubtitle: "Customize the vector SVG/PNG icon or default application for any specific file extension."

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            TextField {
                                id: extSearchInput
                                Layout.fillWidth: true
                                placeholderText: "🔍 Filter extensions (e.g. .py, .rs, .json, .mkv, .srt)..."
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle {
                                    implicitHeight: Math.round(30 * Theme.scaleFactor)
                                    color: Theme.bgSurface
                                    radius: Theme.radiusSmall
                                    border.color: extSearchInput.activeFocus ? Theme.accent : Theme.borderDim
                                }
                            }

                            TextField {
                                id: newCustomExtInput
                                implicitWidth: Math.round(110 * Theme.scaleFactor)
                                placeholderText: "+ .custom"
                                color: Theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                selectByMouse: true
                                background: Rectangle {
                                    implicitHeight: Math.round(30 * Theme.scaleFactor)
                                    color: Theme.bgSurface
                                    radius: Theme.radiusSmall
                                    border.color: newCustomExtInput.activeFocus ? Theme.accent : Theme.borderDim
                                }
                            }

                            ActionBtn {
                                text: "＋ Add Ext Rule"
                                isPrimary: true
                                enabled: newCustomExtInput.text.trim() !== ""
                                onClicked: {
                                    var rawExt = newCustomExtInput.text.trim().toLowerCase()
                                    if (!rawExt.startsWith(".")) rawExt = "." + rawExt
                                    newCustomExtInput.text = ""
                                    appChooserDialog.openForExtension(rawExt, "")
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Repeater {
                                model: {
                                    var q = extSearchInput.text.trim().toLowerCase()
                                    var all = root.extOpenRulesList || []
                                    if (q === "") return all
                                    var filtered = []
                                    for (var i = 0; i < all.length; i++) {
                                        if (all[i].ext.toLowerCase().indexOf(q) !== -1 || all[i].desc.toLowerCase().indexOf(q) !== -1) {
                                            filtered.push(all[i])
                                        }
                                    }
                                    return filtered
                                }

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: Math.round(40 * Theme.scaleFactor)
                                    radius: Theme.radiusSmall
                                    color: Theme.bgSurface
                                    border.color: modelData.app_cmd !== "" ? Theme.accent : Theme.borderDim

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        Rectangle {
                                            width: Math.round(28 * Theme.scaleFactor)
                                            height: Math.round(28 * Theme.scaleFactor)
                                            radius: Theme.radiusSmall
                                            color: Theme.bgCard
                                            border.color: modelData.has_custom_icon ? Theme.accent : Theme.borderDim

                                            Image {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                visible: modelData.icon !== ""
                                                source: visible ? ("file://" + modelData.icon) : ""
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 48
                                                sourceSize.height: 48
                                                smooth: true
                                                mipmap: true
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                visible: modelData.icon === ""
                                                text: "📄"
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }

                                        Text {
                                            Layout.preferredWidth: Math.round(68 * Theme.scaleFactor)
                                            text: modelData.ext
                                            color: Theme.textPrimary
                                            font.family: "monospace"
                                            font.bold: true
                                            font.pixelSize: Theme.fontSizeNormal
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.desc
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.app_name
                                            color: modelData.app_cmd !== "" ? Theme.accent : Theme.textTertiary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: modelData.app_cmd !== ""
                                            Layout.preferredWidth: Math.round(130 * Theme.scaleFactor)
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                        }

                                        ActionBtn {
                                            text: "🖼️ Icon"
                                            onClicked: {
                                                root.activeIconKeyTarget = "ext_icon_" + modelData.ext
                                                settingsIconBrowser.openIconBrowser("")
                                            }
                                        }

                                        ActionBtn {
                                            visible: modelData.has_custom_icon
                                            text: "↺"
                                            onClicked: if (backend) backend.setCustomExtensionIcon(modelData.ext, "")
                                        }

                                        ActionBtn {
                                            text: "⚡ App"
                                            isPrimary: modelData.app_cmd !== ""
                                            onClicked: appChooserDialog.openForExtension(modelData.ext, modelData.app_cmd)
                                        }

                                        ActionBtn {
                                            visible: modelData.app_cmd !== ""
                                            text: "✕"
                                            isDanger: true
                                            onClicked: if (backend) backend.setSingleExtensionRule(modelData.ext, "", "")
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

    // Modal App Chooser Dialog for Extension & Group Rules
    Dialog {
        id: appChooserDialog
        title: "Choose Default Application"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(500 * Theme.scaleFactor), root.width - 28)
        height: Math.min(Math.round(440 * Theme.scaleFactor), root.height - 28)

        property bool isGroupTarget: false
        property string targetKey: ""
        property string targetLabel: ""

        function openForGroup(gKey, gTitle, curCmd) {
            isGroupTarget = true
            targetKey = gKey
            targetLabel = gTitle
            customAppCmdInput.text = curCmd || ""
            appFilterInput.text = ""
            if (backend && root.installedDesktopAppsList.length === 0) {
                root.installedDesktopAppsList = backend.getAllInstalledDesktopApps()
            }
            appChooserDialog.open()
            appFilterInput.forceActiveFocus()
        }

        function openForExtension(extKey, curCmd) {
            isGroupTarget = false
            targetKey = extKey
            targetLabel = extKey
            customAppCmdInput.text = curCmd || ""
            appFilterInput.text = ""
            if (backend && root.installedDesktopAppsList.length === 0) {
                root.installedDesktopAppsList = backend.getAllInstalledDesktopApps()
            }
            appChooserDialog.open()
            appFilterInput.forceActiveFocus()
        }

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.accent
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
                text: "⚡ Default Opener for " + appChooserDialog.targetLabel
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            TextField {
                id: appFilterInput
                Layout.fillWidth: true
                placeholderText: "🔍 Search installed applications (e.g. code, mpv, kitty, nvim)..."
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeSmall
                selectByMouse: true
                background: Rectangle {
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: appFilterInput.activeFocus ? Theme.accent : Theme.borderDim
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
                        var q = appFilterInput.text.trim().toLowerCase()
                        var all = root.installedDesktopAppsList || []
                        if (q === "") return all
                        var out = []
                        for (var i = 0; i < all.length; i++) {
                            if (all[i].name.toLowerCase().indexOf(q) !== -1 || all[i].cmd.toLowerCase().indexOf(q) !== -1) {
                                out.push(all[i])
                            }
                        }
                        return out
                    }

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Math.round(36 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: appRowMouse.containsMouse ? Theme.bgHover : Theme.bgCard
                        border.color: appRowMouse.containsMouse ? Theme.accent : Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Item {
                                Layout.preferredWidth: Math.round(22 * Theme.scaleFactor)
                                Layout.preferredHeight: Math.round(22 * Theme.scaleFactor)

                                Image {
                                    anchors.fill: parent
                                    visible: modelData.icon !== undefined && modelData.icon !== ""
                                    source: visible ? ("file://" + modelData.icon) : ""
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize.width: 44
                                    sourceSize.height: 44
                                    asynchronous: true
                                    smooth: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !modelData.icon || modelData.icon === ""
                                    text: "🚀"
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: Math.round(150 * Theme.scaleFactor)
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.cmd
                                color: Theme.textTertiary
                                font.family: "monospace"
                                font.pixelSize: Math.round(8.5 * Theme.scaleFactor)
                                elide: Text.ElideMiddle
                            }
                        }

                        MouseArea {
                            id: appRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend) {
                                    if (appChooserDialog.isGroupTarget) {
                                        backend.setExtensionGroupRule(appChooserDialog.targetKey, modelData.name, modelData.cmd)
                                    } else {
                                        backend.setSingleExtensionRule(appChooserDialog.targetKey, modelData.name, modelData.cmd)
                                    }
                                }
                                appChooserDialog.close()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: customAppCmdInput
                    Layout.fillWidth: true
                    placeholderText: "Or enter custom command (e.g. code, kitty -e nvim)..."
                    color: Theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: Theme.fontSizeSmall
                    selectByMouse: true
                    background: Rectangle {
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: customAppCmdInput.activeFocus ? Theme.accent : Theme.borderDim
                    }
                }
                ActionBtn {
                    text: "✔ Use Command"
                    isPrimary: true
                    enabled: customAppCmdInput.text.trim() !== ""
                    onClicked: {
                        var cmd = customAppCmdInput.text.trim()
                        if (backend && cmd !== "") {
                            if (appChooserDialog.isGroupTarget) {
                                backend.setExtensionGroupRule(appChooserDialog.targetKey, cmd, cmd)
                            } else {
                                backend.setSingleExtensionRule(appChooserDialog.targetKey, cmd, cmd)
                            }
                        }
                        appChooserDialog.close()
                    }
                }
                ActionBtn {
                    text: "Cancel"
                    onClicked: appChooserDialog.close()
                }
            }
        }
    }
}
