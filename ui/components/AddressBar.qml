import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    spacing: Math.round(10 * Theme.scaleFactor)

    property bool isEditingPath: false
    property bool isSearchActive: false

    component ToolBtn: Rectangle {
        property string iconText: ""
        property string btnText: ""
        property bool isEnabled: true
        signal clicked()
        signal rightClicked()

        implicitWidth: btnText !== "" ? Math.round(80 * Theme.scaleFactor) : Math.round(38 * Theme.scaleFactor)
        implicitHeight: Math.round(38 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: !isEnabled ? "transparent" : (btnMouse.containsMouse ? Theme.bgHover : "transparent")
        opacity: isEnabled ? 1.0 : 0.35

        RowLayout {
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: iconText
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
            }
            Text {
                visible: btnText !== ""
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

    // Left Navigation Controls
    RowLayout {
        spacing: 4
        Layout.alignment: Qt.AlignVCenter

        ToolBtn {
            iconText: "←"
            isEnabled: backend.canGoBack
            onClicked: backend.goBack()
        }
        ToolBtn {
            iconText: "→"
            isEnabled: backend.canGoForward
            onClicked: backend.goForward()
        }
        ToolBtn {
            iconText: "↑"
            isEnabled: true
            onClicked: backend.goUp()
        }
        ToolBtn {
            iconText: "⟳"
            isEnabled: true
            onClicked: backend.refresh()
        }
    }

    // Center: Balanced Breadcrumbs & Search Area
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.round(40 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: Theme.bgSurface
        border.color: (pathInput.activeFocus || searchInput.activeFocus) ? Theme.borderFocus : Theme.borderDim
        border.width: 1
        Layout.alignment: Qt.AlignVCenter

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Math.round(12 * Theme.scaleFactor)
            anchors.rightMargin: Math.round(8 * Theme.scaleFactor)
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.isSearchActive ? "🔍" : "📁"
                font.pixelSize: Theme.fontSizeMedium
            }

            // Normal Breadcrumbs View
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.isEditingPath && !root.isSearchActive
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                RowLayout {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: backend.breadcrumbs
                        delegate: RowLayout {
                            spacing: 3
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                implicitHeight: Math.round(28 * Theme.scaleFactor)
                                implicitWidth: crumbText.implicitWidth + Math.round(14 * Theme.scaleFactor)
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
                        implicitHeight: 28
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                root.isEditingPath = true
                                pathInput.forceActiveFocus()
                                pathInput.selectAll()
                            }
                        }
                    }
                }
            }

            TextInput {
                id: pathInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.isEditingPath && !root.isSearchActive
                text: backend.currentPath
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                selectionColor: Theme.accent

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

                onTextChanged: {
                    backend.searchFast(text)
                }
            }

            ToolBtn {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(30 * Theme.scaleFactor)
                implicitHeight: Math.round(30 * Theme.scaleFactor)
                iconText: "📋"
                onClicked: backend.copyToClipboard(backend.currentPath)
            }

            ToolBtn {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(30 * Theme.scaleFactor)
                implicitHeight: Math.round(30 * Theme.scaleFactor)
                iconText: root.isEditingPath ? "✔" : "✎"
                onClicked: {
                    root.isEditingPath = !root.isEditingPath
                    if (root.isEditingPath) {
                        pathInput.forceActiveFocus()
                        pathInput.selectAll()
                    }
                }
            }
        }
    }

    // Right Action Panel
    RowLayout {
        spacing: 6
        Layout.alignment: Qt.AlignVCenter

        ToolBtn {
            iconText: root.isSearchActive ? "✕" : "🔍"
            onClicked: {
                root.isSearchActive = !root.isSearchActive
                if (root.isSearchActive) {
                    searchInput.forceActiveFocus()
                } else {
                    backend.searchFast("")
                }
            }
        }

        ToolBtn {
            iconText: "＋"
            btnText: "New"
            onClicked: newMenu.popup()

            Menu {
                id: newMenu
                MenuItem {
                    text: "📁 Folder"
                    onTriggered: backend.createItem("folder", "New Folder")
                }
                MenuSeparator {}
                MenuItem {
                    text: "📄 Text Document (.txt)"
                    onTriggered: backend.createItem("txt", "New Text Document.txt")
                }
                MenuItem {
                    text: "🐍 Python Script (.py)"
                    onTriggered: backend.createItem("py", "main.py")
                }
                MenuItem {
                    text: "🦀 Rust File (.rs)"
                    onTriggered: backend.createItem("rs", "main.rs")
                }
                MenuItem {
                    text: "📋 JSON File (.json)"
                    onTriggered: backend.createItem("json", "config.json")
                }
                MenuItem {
                    text: "🔗 Symbolic Link"
                    onTriggered: backend.createItem("link", "Shortcut")
                }
                MenuSeparator {}
                MenuItem {
                    text: "◻️ Empty File"
                    onTriggered: backend.createItem("empty", "file")
                }
            }
        }

        ToolBtn {
            iconText: "⇅"
            btnText: "Sort"
            onClicked: sortMenu.popup()

            Menu {
                id: sortMenu
                MenuItem {
                    text: "Name" + (backend.sortBy === "name" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                    onTriggered: backend.setSort("name")
                }
                MenuItem {
                    text: "Date Modified" + (backend.sortBy === "modified" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                    onTriggered: backend.setSort("modified")
                }
                MenuItem {
                    text: "Date Created" + (backend.sortBy === "created" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                    onTriggered: backend.setSort("created")
                }
                MenuItem {
                    text: "Size" + (backend.sortBy === "size" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                    onTriggered: backend.setSort("size")
                }
            }
        }

        // View Mode Switcher with Left Click (Toggle) and Right Click (Settings Menu)
        ToolBtn {
            id: viewModeBtn
            iconText: backend.viewMode === "details" ? "☰" : "☵"
            onClicked: backend.setViewMode(backend.viewMode === "details" ? "grid" : "details")
            onRightClicked: layoutSettingsMenu.popup(viewModeBtn, 0, viewModeBtn.height)

            Menu {
                id: layoutSettingsMenu

                MenuItem {
                    text: "View: Details List"
                    checkable: true
                    checked: backend.viewMode === "details"
                    onTriggered: backend.setViewMode("details")
                }
                MenuItem {
                    text: "View: Grid Cards"
                    checkable: true
                    checked: backend.viewMode === "grid"
                    onTriggered: backend.setViewMode("grid")
                }

                MenuSeparator {}

                Menu {
                    title: "Grid Columns"
                    MenuItem {
                        text: "Auto Fit (Responsive)"
                        checkable: true
                        checked: backend.gridColumns === 0
                        onTriggered: { backend.setViewMode("grid"); backend.setGridColumns(0); }
                    }
                    MenuItem {
                        text: "3 Columns"
                        checkable: true
                        checked: backend.gridColumns === 3
                        onTriggered: { backend.setViewMode("grid"); backend.setGridColumns(3); }
                    }
                    MenuItem {
                        text: "4 Columns"
                        checkable: true
                        checked: backend.gridColumns === 4
                        onTriggered: { backend.setViewMode("grid"); backend.setGridColumns(4); }
                    }
                    MenuItem {
                        text: "5 Columns"
                        checkable: true
                        checked: backend.gridColumns === 5
                        onTriggered: { backend.setViewMode("grid"); backend.setGridColumns(5); }
                    }
                    MenuItem {
                        text: "6 Columns"
                        checkable: true
                        checked: backend.gridColumns === 6
                        onTriggered: { backend.setViewMode("grid"); backend.setGridColumns(6); }
                    }
                }

                MenuSeparator {}

                MenuItem {
                    text: "Apply to All Subfolders"
                    onTriggered: backend.applyCurrentLayoutToSubfolders()
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
