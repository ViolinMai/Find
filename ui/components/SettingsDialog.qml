import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Find - Settings"
    width: Math.round(780 * Theme.scaleFactor)
    height: Math.round(540 * Theme.scaleFactor)
    modal: true
    anchors.centerIn: parent

    property var hiddenItemsList: backend.getHiddenSidebarItems()
    property var customQAList: backend.getAllCustomQuickAccess()
    property var defaultIconsMap: backend.getDefaultTypeIcons()
    property int selectedQAIndex: -1
    property string activePickerTarget: ""

    // Listen to internal picker return
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
                backend.picker.deactivate()
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
        height: Math.round(48 * Theme.scaleFactor)
        color: Theme.bgCard
        radius: Theme.radiusLarge

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Text {
                text: "⚙️ Find Settings"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            TabBar {
                id: settingsTabs
                background: Rectangle { color: "transparent" }

                TabButton { text: "General & Cache" }
                TabButton { text: "Quick Access" }
                TabButton { text: "Default Icons" }
                TabButton { text: "Hidden Items" }
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Math.round(16 * Theme.scaleFactor)
        currentIndex: settingsTabs.currentIndex

        // TAB 1: General & Cache
        ColumnLayout {
            spacing: Math.round(14 * Theme.scaleFactor)

            Text {
                text: "Storage & Cache Management"
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
                    text: backend.currentCacheSize
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
                    value: backend.maxCacheMb
                    onMoved: backend.setMaxCacheMb(Math.round(value))
                }
            }

            Button {
                text: "Clear Cache Now"
                onClicked: backend.clearCache()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textDanger
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    radius: Theme.radiusMedium
                    border.color: Theme.borderDim
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
            }

            Text {
                text: "Configuration: ~/.config/find/config.json"
                color: Theme.textTertiary
                font.pixelSize: Math.round(10 * Theme.scaleFactor)
            }
            Item { Layout.fillHeight: true }
        }

        // TAB 2: Quick Access Editor (Uses Main Unified In-App Picker)
        RowLayout {
            spacing: Math.round(16 * Theme.scaleFactor)

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

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: qaListView
                        model: root.customQAList
                        spacing: 4

                        delegate: Rectangle {
                            width: qaListView.width - 10
                            height: 34
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

            Rectangle {
                Layout.preferredWidth: Math.round(240 * Theme.scaleFactor)
                Layout.fillHeight: true
                color: Theme.bgSidebar
                radius: Theme.radiusMedium
                border.color: Theme.borderDim

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        text: "Live Sidebar Preview"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: Theme.radiusMedium
                        color: Theme.bgSelected

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Item {
                                implicitWidth: 20
                                implicitHeight: 20
                                Image {
                                    anchors.fill: parent
                                    visible: iconInput.text.indexOf("/") !== -1 || iconInput.text.indexOf(".") !== -1
                                    source: visible ? (iconInput.text.startsWith("/") ? "file://" + iconInput.text : iconInput.text) : ""
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !parent.children[0].visible
                                    text: iconInput.text !== "" ? iconInput.text : "🏠"
                                    font.pixelSize: Theme.fontSizeMedium
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: nameInput.text !== "" ? nameInput.text : "Sample"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        text: "Path: " + (pathInput.text !== "" ? pathInput.text : "-")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WrapAnywhere
                        Layout.fillWidth: true
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // TAB 3: Default Icons Configuration
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 10

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
                        height: 42
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 160
                                text: modelData.label
                                color: Theme.textPrimary
                                font.bold: true
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

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: hiddenListView
                    model: root.hiddenItemsList
                    spacing: 6

                    delegate: Rectangle {
                        width: hiddenListView.width - 10
                        height: 38
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
}
