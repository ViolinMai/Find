import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Menu {
    id: root

    property string targetPath: ""
    property string targetName: ""
    property bool isDir: false
    property bool isItemTarget: false

    delegate: MenuItem {
        id: menuItem
        implicitWidth: Math.round(180 * Theme.scaleFactor)
        implicitHeight: Math.round(32 * Theme.scaleFactor)

        contentItem: Text {
            text: menuItem.text
            color: menuItem.enabled ? Theme.textPrimary : Theme.textTertiary
            font.pixelSize: Theme.fontSizeNormal
            verticalAlignment: Text.AlignVCenter
            leftPadding: Math.round(8 * Theme.scaleFactor)
        }

        background: Rectangle {
            color: menuItem.highlighted ? Theme.bgHover : "transparent"
            radius: Theme.radiusSmall
        }
    }

    background: Rectangle {
        implicitWidth: Math.round(200 * Theme.scaleFactor)
        color: Theme.bgSurface
        border.color: Theme.borderDim
        border.width: 1
        radius: Theme.radiusMedium
    }

    // Context-Aware Items for Folder / File / Background
    Action {
        text: root.isDir ? "Open Folder" : "Open File"
        visible: root.isItemTarget
        onTriggered: backend.openEntry(root.targetPath)
    }

    Action {
        text: "Open Terminal Here"
        visible: root.isDir || !root.isItemTarget
        onTriggered: backend.openInTerminal(root.isItemTarget ? root.targetPath : backend.currentPath)
    }

    MenuSeparator {
        visible: root.isItemTarget
        contentItem: Rectangle {
            implicitHeight: 1
            color: Theme.borderDim
        }
    }

    Action {
        text: "Copy Path"
        visible: root.isItemTarget
        onTriggered: backend.copyToClipboard(root.targetPath)
    }

    Action {
        text: "Refresh"
        visible: !root.isItemTarget
        onTriggered: backend.refresh()
    }

    MenuSeparator {
        visible: root.isItemTarget
        contentItem: Rectangle {
            implicitHeight: 1
            color: Theme.borderDim
        }
    }

    Action {
        text: "Move to Trash"
        visible: root.isItemTarget
        onTriggered: backend.moveToTrash(root.targetPath)
    }
}
