import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgSidebar

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

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
        id: sidebarItemMenu
        property string targetPath: ""

        StyledMenuItem {
            iconGlyph: "📂"
            text: "Open"
            font.bold: true
            onTriggered: if (backend) backend.openEntry(sidebarItemMenu.targetPath)
        }
        StyledMenuItem {
            iconGlyph: "➕"
            text: "Open in New Tab"
            onTriggered: if (backend) backend.addTab(sidebarItemMenu.targetPath)
        }
        StyledMenuItem {
            visible: sidebarItemMenu.targetPath !== "recent://" && sidebarItemMenu.targetPath !== "trash://" && sidebarItemMenu.targetPath !== "favorites://"
            iconGlyph: "💻"
            text: "Open in Terminal"
            onTriggered: if (backend) backend.openInTerminal(sidebarItemMenu.targetPath)
        }
        MenuSeparator {
            visible: sidebarItemMenu.targetPath !== "recent://" && sidebarItemMenu.targetPath !== "trash://" && sidebarItemMenu.targetPath !== "favorites://"
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            visible: sidebarItemMenu.targetPath !== "recent://" && sidebarItemMenu.targetPath !== "trash://" && sidebarItemMenu.targetPath !== "favorites://"
            iconGlyph: "👁️"
            text: "Hide from Sidebar"
            isDanger: true
            onTriggered: if (backend) backend.hideSidebarItem(sidebarItemMenu.targetPath)
        }
    }

    component SidebarEntry: Rectangle {
        id: entryRoot
        property string itemName: ""
        property string itemPath: ""
        property string itemIcon: "📁"
        property bool isFav: false
        property int idxInSection: -1
        property int sectionTotal: 0

        readonly property bool isCurrent: (backend ? backend.currentPath : "") === itemPath
        Layout.fillWidth: true
        implicitHeight: Math.round(32 * Theme.scaleFactor)
        radius: Theme.radiusMedium
        color: dropTarget.containsDrag
               ? "#380078d4"
               : (isCurrent ? Theme.bgSelected : (rowMouse.containsMouse ? Theme.bgHover : "transparent"))
        border.color: dropTarget.containsDrag ? Theme.accent : (isCurrent ? Theme.borderFocus : "transparent")
        border.width: dropTarget.containsDrag || isCurrent ? 1 : 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.compactMode ? 0 : 10
            anchors.rightMargin: root.compactMode ? 0 : 6
            spacing: 8

            Item {
                Layout.preferredWidth: root.compactMode ? entryRoot.width : Math.round(20 * Theme.scaleFactor)
                Layout.fillHeight: true

                Image {
                    anchors.centerIn: parent
                    width: Math.round(18 * Theme.scaleFactor)
                    height: Math.round(18 * Theme.scaleFactor)
                    visible: entryRoot.itemIcon.indexOf("/") !== -1 || entryRoot.itemIcon.indexOf(".") !== -1
                    source: visible ? ("file://" + entryRoot.itemIcon) : ""
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.centerIn: parent
                    visible: entryRoot.itemIcon.indexOf("/") === -1 && entryRoot.itemIcon.indexOf(".") === -1
                    text: entryRoot.itemIcon
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            Text {
                visible: !root.compactMode
                Layout.fillWidth: true
                text: entryRoot.itemName
                color: entryRoot.isCurrent ? Theme.textPrimary : Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                font.bold: entryRoot.isCurrent
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (!backend) return
                if (mouse.button === Qt.MiddleButton) {
                    backend.addTab(entryRoot.itemPath)
                } else if (mouse.button === Qt.RightButton) {
                    sidebarItemMenu.targetPath = entryRoot.itemPath
                    sidebarItemMenu.popup(entryRoot, mouse.x + 2, mouse.y + 2)
                } else {
                    backend.openEntry(entryRoot.itemPath)
                }
            }
        }

        DropArea {
            id: dropTarget
            anchors.fill: parent
            onDropped: function(drop) {
                var urls = []
                if (drop.hasUrls) {
                    for (var i = 0; i < drop.urls.length; i++) urls.push(drop.urls[i].toString())
                } else if (drop.text && drop.text.trim() !== "") {
                    urls = drop.text.trim().split(/\r?\n/)
                }
                if (urls.length > 0) {
                    if (entryRoot.itemPath === "favorites://") {
                        for (var j = 0; j < urls.length; j++) {
                            var cleanP = urls[j].replace("file://", "")
                            backend.addToFavorites(cleanP)
                        }
                        drop.acceptProposedAction()
                    } else if (root.appWindow) {
                        var winPt = entryRoot.mapToItem(root.appWindow.contentItem, drop.x, drop.y)
                        root.appWindow.requestSmartDrop(urls, entryRoot.itemPath, winPt.x, winPt.y)
                        drop.acceptProposedAction()
                    }
                }
            }
        }
    }

    Flickable {
        id: sideFlick
        anchors.fill: parent
        anchors.margins: root.compactMode ? 4 : 8
        contentWidth: width
        contentHeight: sideCol.implicitHeight + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: sideCol
            width: sideFlick.width
            spacing: 3

            // QUICK ACCESS SECTION (Includes Virtual Favorites Folder & Recently Added)
            Text {
                visible: !root.compactMode
                text: "  QUICK ACCESS"
                color: Theme.textTertiary
                font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                font.bold: true
                font.letterSpacing: 0.7
            }

            SidebarEntry {
                itemName: "Favorites"
                itemPath: "favorites://"
                itemIcon: "⭐"
            }

            SidebarEntry {
                itemName: "Recently Added"
                itemPath: "recent://"
                itemIcon: "🕒"
            }

            Repeater {
                model: root.quickAccessList
                delegate: SidebarEntry {
                    itemName: modelData.name
                    itemPath: modelData.path
                    itemIcon: modelData.icon
                }
            }

            // DRIVES & MOUNTS SECTION
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }

            Text {
                visible: !root.compactMode
                text: "  DRIVES & MOUNTS"
                color: Theme.textTertiary
                font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                font.bold: true
                font.letterSpacing: 0.7
            }

            Repeater {
                model: root.drivesList
                delegate: SidebarEntry {
                    itemName: modelData.name
                    itemPath: modelData.path
                    itemIcon: modelData.icon
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderDim
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }

            SidebarEntry {
                itemName: "Trash"
                itemPath: "trash://"
                itemIcon: "🗑️"
            }
        }
    }
}
