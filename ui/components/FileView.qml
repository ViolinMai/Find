import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgBase

    Menu {
        id: contextMenu
        property string targetPath: ""
        property string targetName: ""
        property bool isDir: false
        property bool isItemTarget: false

        MenuItem {
            text: contextMenu.isDir ? "Open Folder" : "Open File"
            visible: contextMenu.isItemTarget
            onTriggered: backend.openEntry(contextMenu.targetPath)
        }

        MenuItem {
            text: "Open Terminal Here"
            visible: contextMenu.isDir || !contextMenu.isItemTarget
            onTriggered: backend.openInTerminal(contextMenu.isItemTarget ? contextMenu.targetPath : backend.currentPath)
        }

        MenuSeparator {
            visible: contextMenu.isItemTarget
        }

        MenuItem {
            text: "Copy Path"
            visible: contextMenu.isItemTarget
            onTriggered: backend.copyToClipboard(contextMenu.targetPath)
        }

        MenuItem {
            text: "Refresh"
            visible: !contextMenu.isItemTarget
            onTriggered: backend.refresh()
        }

        MenuSeparator {
            visible: contextMenu.isItemTarget
        }

        MenuItem {
            text: "Move to Trash"
            visible: contextMenu.isItemTarget
            onTriggered: backend.moveToTrash(contextMenu.targetPath)
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
                contextMenu.targetPath = backend.currentPath
                contextMenu.targetName = ""
                contextMenu.isDir = true
                contextMenu.isItemTarget = false
                contextMenu.popup(mouse.x, mouse.y)
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
            visible: backend.searchResults.length > 0
            color: Theme.bgBase

            ListView {
                anchors.fill: parent
                model: backend.searchResults
                clip: true

                delegate: Rectangle {
                    width: parent.width
                    height: 38
                    color: sHover.containsMouse ? Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text { text: "🔍" }
                        Text {
                            text: modelData.name
                            color: Theme.textPrimary
                            font.bold: true
                            Layout.preferredWidth: 200
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
                        id: sHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onDoubleClicked: backend.openEntry(modelData.path)
                    }
                }
            }
        }

        // Normal View (Details / Grid)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: backend.searchResults.length === 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Table Header (Details view)
                Rectangle {
                    Layout.fillWidth: true
                    height: Math.round(34 * Theme.scaleFactor)
                    color: Theme.bgBase
                    visible: backend.viewMode === "details"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.borderDim
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(18 * Theme.scaleFactor)
                        anchors.rightMargin: Math.round(18 * Theme.scaleFactor)
                        spacing: Math.round(14 * Theme.scaleFactor)

                        Text {
                            Layout.fillWidth: true
                            text: "Name" + (backend.sortBy === "name" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setSort("name")
                            }
                        }

                        Text {
                            Layout.preferredWidth: Math.round(140 * Theme.scaleFactor)
                            text: "Date modified" + (backend.sortBy === "modified" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setSort("modified")
                            }
                        }

                        Text {
                            Layout.preferredWidth: Math.round(140 * Theme.scaleFactor)
                            text: "Date created" + (backend.sortBy === "created" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setSort("created")
                            }
                        }

                        Text {
                            Layout.preferredWidth: Math.round(85 * Theme.scaleFactor)
                            text: "Size" + (backend.sortBy === "size" ? (backend.sortAscending ? " ▲" : " ▼") : "")
                            horizontalAlignment: Text.AlignRight
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setSort("size")
                            }
                        }
                    }
                }

                // 1. Details List View (Faster Scrolling + Lazy Thumbnails)
                ListView {
                    id: fileListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: backend.viewMode === "details"
                    model: backend.files
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    pixelAligned: true
                    flickDeceleration: 1800
                    maximumFlickVelocity: 4500

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: rowDelegate
                        width: fileListView.width
                        height: Math.round(40 * Theme.scaleFactor)
                        radius: Theme.radiusSmall

                        readonly property bool isSelected: backend.selectedItem.path === model.path
                        color: isSelected ? Theme.bgSelected : (itemArea.containsMouse ? Theme.bgHover : "transparent")

                        // Lazy Loading trigger when item gets rendered near viewport
                        Component.onCompleted: {
                            if (!model.is_dir && model.thumb === "") {
                                backend.requestItemThumbnail(model.path)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Math.round(18 * Theme.scaleFactor)
                            anchors.rightMargin: Math.round(18 * Theme.scaleFactor)
                            spacing: Math.round(14 * Theme.scaleFactor)

                            Item {
                                implicitWidth: Math.round(22 * Theme.scaleFactor)
                                implicitHeight: Math.round(22 * Theme.scaleFactor)

                                Image {
                                    anchors.fill: parent
                                    visible: model.thumb !== ""
                                    source: model.thumb !== "" ? "file://" + model.thumb : ""
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: model.thumb === ""
                                    text: model.icon
                                    font.pixelSize: Theme.fontSizeIcon
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: model.name
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.preferredWidth: Math.round(140 * Theme.scaleFactor)
                                text: model.modified
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Text {
                                Layout.preferredWidth: Math.round(140 * Theme.scaleFactor)
                                text: model.created || "-"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Text {
                                Layout.preferredWidth: Math.round(85 * Theme.scaleFactor)
                                text: model.size
                                horizontalAlignment: Text.AlignRight
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            onClicked: function(mouse) {
                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu.targetPath = model.path
                                    contextMenu.targetName = model.name
                                    contextMenu.isDir = model.is_dir
                                    contextMenu.isItemTarget = true
                                    contextMenu.popup(rowDelegate, 30, rowDelegate.height)
                                }
                            }

                            onDoubleClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    backend.openEntry(model.path)
                                }
                            }
                        }
                    }
                }

                // 2. Dynamic Adaptive Grid View (Aspect Aware + Viewport Lazy Loading)
                GridView {
                    id: fileGridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: backend.viewMode === "grid"
                    model: backend.files
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    pixelAligned: true
                    flickDeceleration: 1800
                    maximumFlickVelocity: 4500

                    readonly property int targetCols: backend.gridColumns > 0 ? backend.gridColumns : Math.max(3, Math.floor(fileGridView.width / Math.round(160 * Theme.scaleFactor)))
                    cellWidth: Math.floor(fileGridView.width / Math.max(1, targetCols))
                    cellHeight: cellWidth * 1.05

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: gridDelegate
                        width: fileGridView.cellWidth - Math.round(10 * Theme.scaleFactor)
                        height: fileGridView.cellHeight - Math.round(10 * Theme.scaleFactor)
                        radius: Theme.radiusMedium

                        readonly property bool isSelected: backend.selectedItem.path === model.path
                        color: isSelected ? Theme.bgSelected : (gridMouseArea.containsMouse ? Theme.bgHover : Theme.bgCard)
                        border.color: isSelected ? Theme.accent : Theme.borderDim
                        border.width: 1

                        Component.onCompleted: {
                            if (!model.is_dir && model.thumb === "") {
                                backend.requestItemThumbnail(model.path)
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Math.round(8 * Theme.scaleFactor)
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Theme.bgBase
                                radius: Theme.radiusSmall
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    visible: model.thumb !== ""
                                    source: model.thumb !== "" ? "file://" + model.thumb : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    mipmap: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: model.thumb === ""
                                    text: model.icon
                                    font.pixelSize: Math.round(44 * Theme.scaleFactor)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: model.name
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: isSelected
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                maximumLineCount: 2
                                wrapMode: Text.WrapAnywhere
                            }
                        }

                        MouseArea {
                            id: gridMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            onClicked: function(mouse) {
                                backend.selectItem(model.path, model.name, model.is_dir, model.size, model.modified, model.type)
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu.targetPath = model.path
                                    contextMenu.targetName = model.name
                                    contextMenu.isDir = model.is_dir
                                    contextMenu.isItemTarget = true
                                    contextMenu.popup(gridDelegate, gridDelegate.width / 2, gridDelegate.height)
                                }
                            }

                            onDoubleClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
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
