import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

StyledMenu {
    id: root

    property string targetPath: ""
    property string targetName: ""
    property bool isDir: false
    property bool isAiringItem: false
    property string airingId: ""
    property string airingLinkedPath: ""

    function popupSafe(anchorItem, mouseX, mouseY) {
        if (anchorItem && mouseX !== undefined && mouseY !== undefined) {
            root.popup(anchorItem, mouseX + 3, mouseY + 3)
        } else {
            root.popup()
        }
    }

    StyledMenuItem {
        iconGlyph: "▶"
        text: root.isDir ? "Open / Resume Show" : "Play Episode in MPV"
        font.bold: true
        onTriggered: {
            if (!backend) return
            if (root.isDir && backend.canResumeFolder(root.targetPath)) {
                backend.resumeMediaFolder(root.targetPath)
            } else {
                backend.openEntry(root.targetPath)
            }
        }
    }

    StyledMenuItem {
        iconGlyph: "📂"
        text: "Open in Find"
        font.bold: true
        onTriggered: {
            if (backend) backend.openInFindInstance(root.targetPath)
        }
    }

    StyledMenuItem {
        visible: !root.isDir
        iconGlyph: "📁"
        text: "Open Containing Folder"
        onTriggered: {
            if (backend) backend.goToParentFolder(root.targetPath)
        }
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    StyledMenuItem {
        visible: root.isAiringItem
        iconGlyph: "➕"
        text: "Increment Watched Episode (+1)"
        font.bold: true
        onTriggered: if (backend) backend.adjustAiringEpisode(root.airingId, 1)
    }

    StyledMenuItem {
        visible: root.isAiringItem
        iconGlyph: "➖"
        text: "Decrement Watched Episode (-1)"
        onTriggered: if (backend) backend.adjustAiringEpisode(root.airingId, -1)
    }

    StyledMenuItem {
        visible: !root.isDir && !root.isAiringItem
        iconGlyph: "✓"
        text: "Mark as Watched"
        onTriggered: if (backend) backend.markMediaWatched(root.targetPath, true)
    }

    StyledMenuItem {
        visible: !root.isDir && !root.isAiringItem
        iconGlyph: "↺"
        text: "Reset Watch Progress"
        onTriggered: if (backend) backend.markMediaWatched(root.targetPath, false)
    }

    StyledMenuItem {
        visible: !root.isAiringItem
        iconGlyph: "👁️"
        text: "Hide from Hub (Until Watched)"
        onTriggered: if (backend) backend.hideFromMediaHub(root.targetPath)
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    StyledMenuItem {
        iconGlyph: "📋"
        text: "Copy Path"
        onTriggered: if (backend) backend.copyToClipboard(root.targetPath)
    }
}
