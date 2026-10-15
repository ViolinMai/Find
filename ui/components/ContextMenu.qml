import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

StyledMenu {
    id: root

    property string targetPath: ""
    property string targetName: ""
    property bool isDir: false
    property bool isItemTarget: false

    StyledMenuItem {
        iconGlyph: root.isDir ? "📂" : "🚀"
        text: root.isDir ? "Open Folder" : "Open File"
        visible: root.isItemTarget
        font.bold: true
        onTriggered: backend.openEntry(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "💻"
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

    StyledMenuItem {
        iconGlyph: "🔗"
        text: "Copy Path"
        visible: root.isItemTarget
        onTriggered: backend.copyToClipboard(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "⟳"
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

    StyledMenuItem {
        iconGlyph: "🗑️"
        text: "Move to Trash"
        visible: root.isItemTarget
        isDanger: true
        onTriggered: backend.moveToTrash(root.targetPath)
    }
}
