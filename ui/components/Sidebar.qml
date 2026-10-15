import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgSidebar

    property var appWindow: null
    property bool compactMode: false
    property var quickAccessList: backend ? backend.getQuickAccessLocations() : []
    property var drivesList: backend ? backend.getDrives() : []

    Connections {
        target: backend
        function onSidebarUpdated() {
            if (!backend) return
            root.quickAccessList = backend.getQuickAccessLocations()
            root.drivesList = backend.getDrives()
        }
    }

    StyledMenu {
        id: sideMenu
        property string targetPath: ""
        property string targetName: ""

        StyledMenuItem {
            iconGlyph: "📂"
            text: "Open"
            font.bold: true
            onTriggered: if (backend) backend.navigateTo(sideMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "➕"
            text: "Open in New Tab"
            onTriggered: if (backend) backend.addTab(sideMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "💻"
            text: "Open in Terminal"
            onTriggered: backend.openInTerminal(sideMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "🔗"
            text: "Copy Path"
            onTriggered: backend.copyToClipboard(sideMenu.targetPath)
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            iconGlyph: "👁️‍🗨️"
            text: "Hide from Sidebar"
            isDanger: true
            onTriggered: backend.hideSidebarItem(sideMenu.targetPath)
        }
    }

    Flickable {
        id: sideFlick
        anchors.fill: parent
        anchors.margins: root.compactMode ? 4 : 6
        contentWidth: width
        contentHeight: sideColumn.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: sideColumn
            width: sideFlick.width
            spacing: 4

            // Section 1: Quick Access
            Text {
                visible: !root.compactMode
                text: "Quick Access"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.leftMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 2
            }

            Repeater {
                model: root.quickAccessList
                delegate: Rectangle {
                    id: qaDelegate
                    Layout.fillWidth: true
                    implicitHeight: Math.round(36 * Theme.scaleFactor)
                    radius: Theme.radiusMedium

                    readonly property bool isCurrent: (backend ? backend.currentPath : "") === modelData.path
                    color: qaDrop.containsDrag ? "#2a0078d4" : (isCurrent ? Theme.bgSelected : (mouseArea.containsMouse ? Theme.bgHover : "transparent"))
                    border.color: qaDrop.containsDrag ? Theme.accent : "transparent"
                    border.width: qaDrop.containsDrag ? 1 : 0

                    Rectangle {
                        width: 3
                        height: Math.round(18 * Theme.scaleFactor)
                        radius: 2
                        color: Theme.accent
                        visible: qaDelegate.isCurrent
                        anchors.left: parent.left
                        anchors.leftMargin: root.compactMode ? 2 : 4
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.compactMode ? 0 : 14
                        anchors.rightMargin: root.compactMode ? 0 : 10
                        spacing: root.compactMode ? 0 : 10

                        Item {
                            implicitWidth: Math.round(22 * Theme.scaleFactor)
                            implicitHeight: Math.round(22 * Theme.scaleFactor)
                            Layout.alignment: root.compactMode ? Qt.AlignCenter : Qt.AlignVCenter

                            Image {
                                anchors.fill: parent
                                visible: modelData.icon.indexOf("/") !== -1 || modelData.icon.indexOf(".") !== -1
                                source: visible ? (modelData.icon.startsWith("/") ? "file://" + modelData.icon : modelData.icon) : ""
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !parent.children[0].visible
                                text: modelData.icon
                                font.pixelSize: Theme.fontSizeMedium
                            }
                        }

                        Text {
                            visible: !root.compactMode
                            Layout.fillWidth: true
                            text: modelData.name
                            color: qaDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: qaDelegate.isCurrent
                            elide: Text.ElideRight
                        }
                    }

                    ToolTip.visible: root.compactMode && mouseArea.containsMouse
                    ToolTip.text: modelData.name

                    DropArea {
                        id: qaDrop
                        anchors.fill: parent
                        onPositionChanged: function(drag) {
                            if (root.appWindow && root.appWindow.isRightDragging) {
                                var gp = qaDrop.mapToGlobal(drag.x, drag.y)
                                root.appWindow.updateRightDragPos(gp)
                            }
                        }
                        onDropped: function(drop) {
                            if (root.appWindow) root.appWindow.endRightDrag()
                            var urls = []
                            if (drop.hasUrls) {
                                for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                            } else if (drop.text && drop.text.trim() !== "") {
                                urls = drop.text.trim().split(/\r?\n/)
                            }
                            if (urls.length > 0 && root.appWindow) {
                                var winPt = qaDelegate.mapToItem(root.appWindow.contentItem, drop.x, drop.y)
                                root.appWindow.requestSmartDrop(urls, modelData.path, winPt.x, winPt.y)
                                drop.acceptProposedAction()
                            }
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function(mouse) {
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                            var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

                            if (mouse.button === Qt.MiddleButton) {
                                backend.addTab(modelData.path)
                            } else if (isPrimary) {
                                backend.navigateTo(modelData.path)
                            } else if (isSecondary) {
                                sideMenu.targetPath = modelData.path
                                sideMenu.targetName = modelData.name
                                sideMenu.popup()
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.borderDim; Layout.topMargin: 4; Layout.bottomMargin: 4 }

            // Section 2: Library & System
            Text {
                visible: !root.compactMode
                text: "Library & System"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.leftMargin: 10
                Layout.bottomMargin: 2
            }

            // Recently Added
            Rectangle {
                id: recentDelegate
                Layout.fillWidth: true
                implicitHeight: Math.round(36 * Theme.scaleFactor)
                radius: Theme.radiusMedium

                readonly property bool isCurrent: (backend ? backend.currentPath : "") === "recent://"
                color: isCurrent ? Theme.bgSelected : (rArea.containsMouse ? Theme.bgHover : "transparent")

                Rectangle {
                    width: 3
                    height: Math.round(18 * Theme.scaleFactor)
                    radius: 2
                    color: Theme.accent
                    visible: recentDelegate.isCurrent
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? 2 : 4
                    anchors.verticalCenter: parent.verticalCenter
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.compactMode ? 0 : 14
                    anchors.rightMargin: root.compactMode ? 0 : 10
                    spacing: root.compactMode ? 0 : 10

                    Text {
                        text: "🕒"
                        font.pixelSize: Theme.fontSizeMedium
                        Layout.alignment: root.compactMode ? Qt.AlignCenter : Qt.AlignVCenter
                    }
                    Text {
                        visible: !root.compactMode
                        text: "Recently Added"
                        color: recentDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: recentDelegate.isCurrent
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                ToolTip.visible: root.compactMode && rArea.containsMouse
                ToolTip.text: "Recently Added"

                MouseArea {
                    id: rArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.navigateTo("recent://")
                }
            }

            // Trash Location
            Rectangle {
                id: trashDelegate
                Layout.fillWidth: true
                implicitHeight: Math.round(36 * Theme.scaleFactor)
                radius: Theme.radiusMedium

                readonly property bool isCurrent: (backend ? backend.currentPath : "") === (backend ? backend.trashPath : "trash://")
                color: isCurrent ? Theme.bgSelected : (tArea.containsMouse ? Theme.bgHover : "transparent")

                Rectangle {
                    width: 3
                    height: Math.round(18 * Theme.scaleFactor)
                    radius: 2
                    color: Theme.accent
                    visible: trashDelegate.isCurrent
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? 2 : 4
                    anchors.verticalCenter: parent.verticalCenter
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.compactMode ? 0 : 14
                    anchors.rightMargin: root.compactMode ? 0 : 10
                    spacing: root.compactMode ? 0 : 10

                    Text {
                        text: "🗑️"
                        font.pixelSize: Theme.fontSizeMedium
                        Layout.alignment: root.compactMode ? Qt.AlignCenter : Qt.AlignVCenter
                    }
                    Text {
                        visible: !root.compactMode
                        text: "Trash"
                        color: trashDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: trashDelegate.isCurrent
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                ToolTip.visible: root.compactMode && tArea.containsMouse
                ToolTip.text: "Trash"

                MouseArea {
                    id: tArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.navigateTo(backend.trashPath)
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.borderDim; Layout.topMargin: 4; Layout.bottomMargin: 4 }

            // Section 3: Drives & Storage
            Text {
                visible: !root.compactMode
                text: "Drives & Storage"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.leftMargin: 10
                Layout.bottomMargin: 2
            }

            Repeater {
                model: root.drivesList
                delegate: Rectangle {
                    id: driveDelegate
                    Layout.fillWidth: true
                    implicitHeight: root.compactMode ? Math.round(36 * Theme.scaleFactor) : Math.round(42 * Theme.scaleFactor)
                    radius: Theme.radiusMedium

                    readonly property bool isCurrent: (backend ? backend.currentPath : "") === modelData.path
                    color: driveDrop.containsDrag ? "#2a0078d4" : (isCurrent ? Theme.bgSelected : (driveMouse.containsMouse ? Theme.bgHover : "transparent"))
                    border.color: driveDrop.containsDrag ? Theme.accent : "transparent"
                    border.width: driveDrop.containsDrag ? 1 : 0

                    Rectangle {
                        width: 3
                        height: Math.round(18 * Theme.scaleFactor)
                        radius: 2
                        color: Theme.accent
                        visible: driveDelegate.isCurrent
                        anchors.left: parent.left
                        anchors.leftMargin: root.compactMode ? 2 : 4
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.compactMode ? 0 : 14
                        anchors.rightMargin: root.compactMode ? 0 : 10
                        spacing: root.compactMode ? 0 : 10

                        Text {
                            text: modelData.icon
                            font.pixelSize: Theme.fontSizeMedium
                            Layout.alignment: root.compactMode ? Qt.AlignCenter : Qt.AlignVCenter
                        }

                        ColumnLayout {
                            visible: !root.compactMode
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: driveDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: driveDelegate.isCurrent
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.device
                                color: Theme.textTertiary
                                font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    ToolTip.visible: root.compactMode && driveMouse.containsMouse
                    ToolTip.text: modelData.name + " (" + modelData.device + ")"

                    DropArea {
                        id: driveDrop
                        anchors.fill: parent
                        onPositionChanged: function(drag) {
                            if (root.appWindow && root.appWindow.isRightDragging) {
                                var gp = driveDrop.mapToGlobal(drag.x, drag.y)
                                root.appWindow.updateRightDragPos(gp)
                            }
                        }
                        onDropped: function(drop) {
                            if (root.appWindow) root.appWindow.endRightDrag()
                            var urls = []
                            if (drop.hasUrls) {
                                for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                            } else if (drop.text && drop.text.trim() !== "") {
                                urls = drop.text.trim().split(/\r?\n/)
                            }
                            if (urls.length > 0 && root.appWindow) {
                                var winPt = driveDelegate.mapToItem(root.appWindow.contentItem, drop.x, drop.y)
                                root.appWindow.requestSmartDrop(urls, modelData.path, winPt.x, winPt.y)
                                drop.acceptProposedAction()
                            }
                        }
                    }

                    MouseArea {
                        id: driveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function(mouse) {
                            if (!backend) return
                            var swapped = backend.swapMouseButtons
                            var isPrimary = swapped ? (mouse.button === Qt.RightButton) : (mouse.button === Qt.LeftButton)
                            var isSecondary = swapped ? (mouse.button === Qt.LeftButton) : (mouse.button === Qt.RightButton)

                            if (mouse.button === Qt.MiddleButton) {
                                backend.addTab(modelData.path)
                            } else if (isPrimary) {
                                backend.navigateTo(modelData.path)
                            } else if (isSecondary) {
                                sideMenu.targetPath = modelData.path
                                sideMenu.targetName = modelData.name
                                sideMenu.popup()
                            }
                        }
                    }
                }
            }
        }
    }
}
