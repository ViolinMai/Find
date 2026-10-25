import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

StyledMenu {
    id: root

    property string targetPath: ""
    property string targetName: ""
    property string showPath: ""
    property bool isDir: false
    property bool isAiringItem: false
    property string airingId: ""
    property string airingLinkedPath: ""

    signal requestAiringLinkModal(string airingId, string airingTitle)

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
        visible: root.showPath !== "" && root.showPath !== root.targetPath
        iconGlyph: "📺"
        text: "Go to Show Page"
        font.bold: true
        onTriggered: {
            if (backend && root.showPath !== "") {
                backend.setViewMode("details")
                backend.navigateTo(root.showPath)
            }
        }
    }

    StyledMenuItem {
        visible: !root.isDir && !root.isAiringItem
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

    MenuSeparator {
        visible: root.isAiringItem
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    StyledMenuItem {
        visible: root.isAiringItem
        iconGlyph: "🔗"
        text: root.airingLinkedPath !== "" ? "Change Linked Media Hub Work..." : "Link with Media Hub Work..."
        font.bold: true
        onTriggered: root.requestAiringLinkModal(root.airingId, root.targetName)
    }

    StyledMenuItem {
        visible: root.isAiringItem && root.airingLinkedPath !== ""
        iconGlyph: "📺"
        text: "Go to Linked Show Page"
        font.bold: true
        onTriggered: {
            if (backend && root.airingLinkedPath !== "") {
                backend.setViewMode("details")
                backend.navigateTo(root.airingLinkedPath)
            }
        }
    }

    StyledMenuItem {
        visible: root.isAiringItem && root.airingLinkedPath !== ""
        iconGlyph: "⛓️‍💥"
        text: "Unlink Media Hub Work"
        onTriggered: if (backend) backend.linkAiringToMediaFolder(root.airingId, "")
    }

    StyledMenuItem {
        visible: root.isAiringItem
        iconGlyph: "🚫"
        text: "Ignore this from Airing"
        isDanger: true
        font.bold: true
        onTriggered: if (backend) backend.ignoreAiringItem(root.airingId)
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
