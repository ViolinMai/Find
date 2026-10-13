import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgSidebar

    property var quickAccessList: backend.getQuickAccessLocations()
    property var drivesList: backend.getDrives()

    Connections {
        target: backend
        function onSidebarUpdated() {
            root.quickAccessList = backend.getQuickAccessLocations()
            root.drivesList = backend.getDrives()
        }
    }

    Menu {
        id: sideMenu
        property string targetPath: ""
        property string targetName: ""

        MenuItem {
            text: "Open"
            onTriggered: backend.navigateTo(sideMenu.targetPath)
        }
        MenuItem {
            text: "Open in Terminal"
            onTriggered: backend.openInTerminal(sideMenu.targetPath)
        }
        MenuItem {
            text: "Copy Path"
            onTriggered: backend.copyToClipboard(sideMenu.targetPath)
        }
        MenuSeparator {}
        MenuItem {
            text: "Hide from Sidebar"
            onTriggered: backend.hideSidebarItem(sideMenu.targetPath)
        }
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: root.width
            spacing: Math.round(6 * Theme.scaleFactor)

            // Section 1: Quick Access
            Text {
                text: "Quick Access"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.leftMargin: Math.round(14 * Theme.scaleFactor)
                Layout.topMargin: Math.round(8 * Theme.scaleFactor)
            }

            Repeater {
                model: root.quickAccessList
                delegate: Rectangle {
                    id: qaDelegate
                    Layout.fillWidth: true
                    height: Math.round(36 * Theme.scaleFactor)
                    radius: Theme.radiusMedium

                    readonly property bool isCurrent: backend.currentPath === modelData.path
                    color: isCurrent ? Theme.bgSelected : (mouseArea.containsMouse ? Theme.bgHover : "transparent")

                    Rectangle {
                        width: Math.round(3 * Theme.scaleFactor)
                        height: Math.round(18 * Theme.scaleFactor)
                        radius: 2
                        color: Theme.accent
                        visible: qaDelegate.isCurrent
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(14 * Theme.scaleFactor)
                        anchors.rightMargin: Math.round(12 * Theme.scaleFactor)
                        spacing: Math.round(10 * Theme.scaleFactor)

                        Item {
                            implicitWidth: Theme.fontSizeMedium + 4
                            implicitHeight: Theme.fontSizeMedium + 4
                            Layout.alignment: Qt.AlignVCenter

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
                            Layout.fillWidth: true
                            text: modelData.name
                            color: qaDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: qaDelegate.isCurrent
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                backend.navigateTo(modelData.path)
                            } else if (mouse.button === Qt.RightButton) {
                                sideMenu.targetPath = modelData.path
                                sideMenu.targetName = modelData.name
                                sideMenu.popup(qaDelegate, 10, qaDelegate.height)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
                Layout.topMargin: 8
                Layout.bottomMargin: 4
            }

            // Section 2: Drives & Storage
            Text {
                text: "Drives & Storage"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.leftMargin: Math.round(14 * Theme.scaleFactor)
                Layout.topMargin: Math.round(4 * Theme.scaleFactor)
            }

            Repeater {
                model: root.drivesList
                delegate: Rectangle {
                    id: driveDelegate
                    Layout.fillWidth: true
                    height: Math.round(40 * Theme.scaleFactor)
                    radius: Theme.radiusMedium

                    readonly property bool isCurrent: backend.currentPath === modelData.path
                    color: isCurrent ? Theme.bgSelected : (driveMouse.containsMouse ? Theme.bgHover : "transparent")

                    Rectangle {
                        width: Math.round(3 * Theme.scaleFactor)
                        height: Math.round(18 * Theme.scaleFactor)
                        radius: 2
                        color: Theme.accent
                        visible: driveDelegate.isCurrent
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(14 * Theme.scaleFactor)
                        anchors.rightMargin: Math.round(12 * Theme.scaleFactor)
                        spacing: Math.round(10 * Theme.scaleFactor)

                        Text {
                            text: modelData.icon
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: driveDelegate.isCurrent ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: driveDelegate.isCurrent
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.total !== "" ? modelData.total : modelData.device
                                color: Theme.textTertiary
                                font.pixelSize: Math.round(10 * Theme.scaleFactor)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: driveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                backend.navigateTo(modelData.path)
                            } else if (mouse.button === Qt.RightButton) {
                                sideMenu.targetPath = modelData.path
                                sideMenu.targetName = modelData.name
                                sideMenu.popup(driveDelegate, 10, driveDelegate.height)
                            }
                        }
                    }
                }
            }
        }
    }
}
