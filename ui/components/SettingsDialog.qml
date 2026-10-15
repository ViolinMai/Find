import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Find - Settings"
    width: Overlay.overlay ? Math.min(Math.round(740 * Theme.scaleFactor), Overlay.overlay.width - 20) : 780
    height: Overlay.overlay ? Math.min(Math.round(520 * Theme.scaleFactor), Overlay.overlay.height - 20) : 550
    modal: true
    anchors.centerIn: Overlay.overlay

    property var hiddenItemsList: backend ? backend.getHiddenSidebarItems() : []
    property var customQAList: backend ? backend.getAllCustomQuickAccess() : []
    property var defaultIconsMap: backend ? backend.getDefaultTypeIcons() : ({})
    property int selectedQAIndex: -1
    property string activePickerTarget: ""

    Connections {
        target: backend
        function onPickerCompleted(paths) {
            if (paths.length > 0) {
                var selected = paths[0]
                if (root.activePickerTarget === "qa_path") {
                    pathInput.text = selected
                } else if (root.activePickerTarget === "qa_icon") {
                    iconInput.text = selected
                } else if (root.activePickerTarget.startsWith("def_icon_")) {
                    var key = root.activePickerTarget.replace("def_icon_", "")
                    backend.setDefaultTypeIcon(key, selected)
                    root.defaultIconsMap = backend.getDefaultTypeIcons()
                }
                backend.cancelPicker()
                root.open()
            }
        }
    }

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.borderDim
        border.width: 1
        radius: Theme.radiusLarge
    }

    header: Rectangle {
        height: Math.round(46 * Theme.scaleFactor)
        color: Theme.bgCard
        radius: Theme.radiusLarge

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10

            Text {
                text: "⚙️ Find Settings"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                visible: root.width > Math.round(460 * Theme.scaleFactor)
            }

            Item { Layout.fillWidth: true }

            TabBar {
                id: settingsTabs
                background: Rectangle { color: "transparent" }

                TabButton { text: "General & UI" }
                TabButton { text: "Quick Access" }
                TabButton { text: "Icons" }
                TabButton { text: "Hidden" }
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Math.round(14 * Theme.scaleFactor)
        currentIndex: settingsTabs.currentIndex

        // TAB 1: General, Grid Style & Hyprland Layout
        ColumnLayout {
            spacing: Math.round(12 * Theme.scaleFactor)

            Text {
                text: "Grid Preview & Layout Style"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Media & Folder Display Mode:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                }

                Button {
                    text: "✨ Floating Preview"
                    onClicked: if (backend) backend.setGridStyle("floating")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: backend ? backend.gridStyle === "floating" : true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(135 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: (backend && backend.gridStyle === "floating") ? Theme.accent : Theme.bgCard
                        border.color: (backend && backend.gridStyle === "floating") ? Theme.accentHover : Theme.borderDim
                    }
                }

                Button {
                    text: "🃏 Framed Cards"
                    onClicked: if (backend) backend.setGridStyle("cards")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: backend ? backend.gridStyle === "cards" : false
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(125 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: (backend && backend.gridStyle === "cards") ? Theme.accent : Theme.bgCard
                        border.color: (backend && backend.gridStyle === "cards") ? Theme.accentHover : Theme.borderDim
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Quick Access Sidebar Layout:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                }

                Repeater {
                    model: [
                        { key: "auto", label: "Auto (Hyprland)" },
                        { key: "full", label: "Full Sidebar" },
                        { key: "rail", label: "Icon Rail" },
                        { key: "topbar", label: "Top Strip" }
                    ]
                    delegate: Button {
                        text: modelData.label
                        onClicked: if (backend) backend.setSidebarMode(modelData.key)
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.bold: backend ? backend.sidebarMode === modelData.key : false
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                        }
                        background: Rectangle {
                            implicitWidth: Math.round(96 * Theme.scaleFactor)
                            implicitHeight: Math.round(28 * Theme.scaleFactor)
                            radius: Theme.radiusSmall
                            color: (backend && backend.sidebarMode === modelData.key) ? Theme.accent : Theme.bgCard
                            border.color: (backend && backend.sidebarMode === modelData.key) ? Theme.accentHover : Theme.borderDim
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Transparent Window (Hyprland Blur Ready):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.transparentBlur : false
                    onToggled: if (backend) backend.transparentBlur = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Show Hidden Files & Folders (Ctrl+H):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.showHidden : false
                    onToggled: if (backend) backend.setShowHidden(checked)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Swap Left & Right Mouse Button Roles (Select/Drag):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.swapMouseButtons : false
                    onToggled: if (backend) backend.setSwapMouseButtons(checked)
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

            Text {
                text: "Storage & Thumbnail Cache"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Current Cache Usage:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: backend ? backend.currentCacheSize : "0 B"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Max Cache Limit:"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                    }
                    Text {
                        text: Math.round(cacheSlider.value) + " MB"
                        color: Theme.textPrimary
                        font.bold: true
                        font.pixelSize: Theme.fontSizeNormal
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

            Button {
                text: "Clear Cache Now"
                onClicked: backend.clearCache()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textDanger
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(140 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    radius: Theme.radiusMedium
                    border.color: Theme.borderDim
                }
            }

            Item { Layout.fillHeight: true }
        }

        // TAB 2: Quick Access Editor
        RowLayout {
            spacing: Math.round(14 * Theme.scaleFactor)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Text {
                    text: "Configure Shortcuts"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }

                ListView {
                    id: qaListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.customQAList
                    spacing: 4

                    delegate: Rectangle {
                        width: qaListView.width
                        height: Math.round(34 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: root.selectedQAIndex === index ? Theme.bgSelected : (itemHover.containsMouse ? Theme.bgHover : Theme.bgCard)
                        border.color: Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text { text: modelData.icon; font.pixelSize: Theme.fontSizeNormal }
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.bold: true
                                Layout.preferredWidth: 90
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.path
                                color: Theme.textTertiary
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }
                        }

                        MouseArea {
                            id: itemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedQAIndex = index
                                nameInput.text = modelData.name
                                pathInput.text = modelData.path
                                iconInput.text = modelData.icon
                            }
                        }
                    }
                }

                GridLayout {
                    columns: 3
                    Layout.fillWidth: true
                    rowSpacing: 6
                    columnSpacing: 8

                    Text { text: "Name:"; color: Theme.textSecondary }
                    TextField {
                        id: nameInput
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }

                    Text { text: "Target Path:"; color: Theme.textSecondary }
                    TextField {
                        id: pathInput
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }
                    Button {
                        text: "Browse..."
                        onClicked: {
                            root.activePickerTarget = "qa_path"
                            root.close()
                            backend.openInternalPicker("folder", "", "Select Target Folder")
                        }
                    }

                    Text { text: "Icon / Image:"; color: Theme.textSecondary }
                    TextField {
                        id: iconInput
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }
                    Button {
                        text: "Pick Icon..."
                        onClicked: {
                            root.activePickerTarget = "qa_icon"
                            root.close()
                            backend.openInternalPicker("file", "*.png;*.ico;*.svg", "Select Icon File")
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    Button {
                        text: "Save / Update"
                        onClicked: {
                            if (root.selectedQAIndex >= 0 && root.selectedQAIndex < root.customQAList.length) {
                                var list = root.customQAList.slice()
                                list[root.selectedQAIndex] = {
                                    "name": nameInput.text,
                                    "path": pathInput.text,
                                    "icon": iconInput.text
                                }
                                root.customQAList = list
                                backend.saveCustomQuickAccess(list)
                            }
                        }
                    }
                    Button {
                        text: "Add New"
                        onClicked: {
                            var list = root.customQAList.slice()
                            list.push({
                                "name": nameInput.text || "New Shortcut",
                                "path": pathInput.text || backend.currentPath,
                                "icon": iconInput.text || "⭐"
                            })
                            root.customQAList = list
                            backend.saveCustomQuickAccess(list)
                        }
                    }
                    Button {
                        text: "Delete"
                        enabled: root.selectedQAIndex >= 0
                        onClicked: {
                            var list = root.customQAList.slice()
                            list.splice(root.selectedQAIndex, 1)
                            root.customQAList = list
                            root.selectedQAIndex = -1
                            backend.saveCustomQuickAccess(list)
                        }
                    }
                }
            }
        }

        // TAB 3: Default Icons Configuration
        Flickable {
            id: iconFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: iconCol.implicitHeight + 16
            clip: true

            ColumnLayout {
                id: iconCol
                width: iconFlick.width
                spacing: 8

                Text {
                    text: "Customize Default File & Folder Icons"
                    color: Theme.textPrimary
                    font.bold: true
                    font.pixelSize: Theme.fontSizeMedium
                }

                Repeater {
                    model: [
                        { key: "folder", label: "Folder Icon" },
                        { key: "file", label: "Generic File Icon" },
                        { key: "image", label: "Image Files Icon" },
                        { key: "video", label: "Video Files Icon" },
                        { key: "audio", label: "Audio Files Icon" },
                        { key: "py", label: "Python Files Icon" },
                        { key: "rs", label: "Rust Files Icon" },
                        { key: "json", label: "JSON Files Icon" },
                        { key: "archive", label: "Archive Files Icon" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Math.round(38 * Theme.scaleFactor)
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 150
                                text: modelData.label
                                color: Theme.textPrimary
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: root.defaultIconsMap[modelData.key] || "-"
                                color: Theme.textSecondary
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }

                            Button {
                                text: "Select Icon..."
                                onClicked: {
                                    root.activePickerTarget = "def_icon_" + modelData.key
                                    root.close()
                                    backend.openInternalPicker("file", "*.png;*.ico;*.svg", "Select Default Icon")
                                }
                            }
                        }
                    }
                }
            }
        }

        // TAB 4: Hidden Items
        ColumnLayout {
            spacing: 10

            Text {
                text: "Hidden Sidebar Items"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            ListView {
                id: hiddenListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.hiddenItemsList
                spacing: 6

                delegate: Rectangle {
                    width: hiddenListView.width
                    height: Math.round(36 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: Theme.bgCard
                    border.color: Theme.borderDim

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            elide: Text.ElideMiddle
                        }

                        Button {
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
