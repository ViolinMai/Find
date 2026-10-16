import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

StyledMenu {
    id: root

    property string targetPath: ""
    property string targetName: ""
    property bool isDir: false
    property var availableApps: (backend && targetPath !== "") ? backend.getAvailableApps(targetPath) : []
    property string defaultApp: (backend && targetPath !== "") ? backend.getDefaultApp(targetPath) : "Default App"
    readonly property bool isVideoTarget: (backend && !root.isDir && targetPath !== "") ? backend.isVideoFile(targetPath) : false

    function openRenameModal() {
        newNameField.text = root.targetName
        renameDialog.open()
    }

    // 1. Open / Open in New Tab / Open with Default
    StyledMenuItem {
        iconGlyph: root.isDir ? "📂" : "🚀"
        text: root.isDir ? "Open Folder" : "Open with " + root.defaultApp
        font.bold: true
        onTriggered: if (backend) backend.openEntry(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "➕"
        text: "Open in New Tab"
        visible: root.isDir
        onTriggered: if (backend) backend.addTab(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "🔆"
        text: "Open MPV with HDR"
        visible: root.isVideoTarget
        font.bold: true
        onTriggered: if (backend) backend.openInMpvCustom(root.targetPath, true)
    }

    // 2. Open With Submenu
    StyledMenu {
        title: "Open With"
        iconGlyph: "⚡"
        visible: !root.isDir

        Repeater {
            model: root.availableApps
            delegate: StyledMenuItem {
                iconGlyph: "🔹"
                text: modelData.name
                onTriggered: backend.openWithApp(root.targetPath, modelData.cmd)
            }
        }

        MenuSeparator {
            visible: root.availableApps.length > 0
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }

        StyledMenuItem {
            iconGlyph: "⚙️"
            text: "System Default..."
            onTriggered: backend.openEntry(root.targetPath)
        }
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    // 3. Cut, Copy, Paste, Copy Location, Duplicate, Rename
    StyledMenuItem {
        iconGlyph: "✂️"
        text: "Cut"
        shortcutText: "Ctrl+X"
        onTriggered: if (backend) backend.stageClipboard(root.targetPath, true)
    }

    StyledMenuItem {
        iconGlyph: "📋"
        text: "Copy"
        shortcutText: "Ctrl+C"
        onTriggered: if (backend) backend.stageClipboard(root.targetPath, false)
    }

    StyledMenuItem {
        iconGlyph: "📥"
        text: root.isDir ? "Paste Into Folder" : "Paste Here"
        shortcutText: "Ctrl+V"
        enabled: backend ? (backend.getClipboardPath() !== "") : false
        onTriggered: {
            if (!backend) return
            var dest = root.isDir ? root.targetPath : backend.currentPath
            backend.pasteToFolder(dest)
        }
    }

    StyledMenuItem {
        iconGlyph: "🔗"
        text: "Copy Path"
        shortcutText: "Ctrl+Alt+C"
        onTriggered: backend.copyToClipboard(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "📑"
        text: "Duplicate Here"
        shortcutText: "Ctrl+D"
        onTriggered: backend.duplicateItem(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "✏️"
        text: "Rename..."
        shortcutText: "F2"
        onTriggered: {
            newNameField.text = root.targetName
            renameDialog.open()
        }
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    // 4. Organization & Archive
    StyledMenuItem {
        iconGlyph: "📁"
        text: "Move to New Folder"
        onTriggered: backend.moveToNewFolder(root.targetPath)
    }

    StyledMenu {
        title: "Compress"
        iconGlyph: "📦"

        StyledMenuItem {
            iconGlyph: "🗜️"
            text: "Archive as .zip"
            onTriggered: backend.compressItem(root.targetPath, "zip")
        }
        StyledMenuItem {
            iconGlyph: "🗜️"
            text: "Archive as .tar.gz"
            onTriggered: backend.compressItem(root.targetPath, "tar.gz")
        }
    }

    StyledMenu {
        title: "Share"
        iconGlyph: "📡"

        StyledMenuItem {
            iconGlyph: "📱"
            text: "KDE Connect / Copy URI"
            onTriggered: backend.shareItem(root.targetPath)
        }
    }

    StyledMenuItem {
        iconGlyph: "💻"
        text: "Open Terminal Here"
        visible: root.isDir
        onTriggered: if (backend) backend.openInTerminal(root.targetPath)
    }

    // Media Library & Episode Watch Controls
    StyledMenu {
        title: "Media Library Options"
        iconGlyph: "🎬"
        visible: root.isDir || (backend ? backend.isMediaLibraryView : false)

        StyledMenuItem {
            visible: root.isDir
            iconGlyph: "📺"
            text: "Set Folder as Series/Anime Library"
            onTriggered: if (backend) backend.addMediaLibrary(root.targetPath, "series")
        }
        StyledMenuItem {
            visible: root.isDir
            iconGlyph: "🎞️"
            text: (backend && backend.isFolderMarkedAsMovie(root.targetPath))
                  ? "Unmark Movie Folder Mode"
                  : "Mark Folder as Movies (No Numbering + Separator)"
            onTriggered: if (backend) backend.toggleMovieFolderStatus(root.targetPath)
        }
        StyledMenuItem {
            visible: !root.isDir && (backend ? backend.isMediaLibraryView : false)
            iconGlyph: "✓"
            text: "Mark Episode/Movie as Watched"
            onTriggered: if (backend) backend.markMediaWatched(root.targetPath, true)
        }
        StyledMenuItem {
            visible: !root.isDir && (backend ? backend.isMediaLibraryView : false)
            iconGlyph: "↺"
            text: "Reset Watch Progress"
            onTriggered: if (backend) backend.markMediaWatched(root.targetPath, false)
        }
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    // 5. Properties & Trash
    StyledMenuItem {
        iconGlyph: "ℹ️"
        text: "Properties & Inspect"
        shortcutText: "Alt+Enter"
        onTriggered: {
            backend.selectItem(root.targetPath, root.targetName, root.isDir, "", "", "")
        }
    }

    StyledMenuItem {
        iconGlyph: "🗑️"
        text: "Move to Trash"
        shortcutText: "Del"
        isDanger: true
        onTriggered: backend.moveToTrash(root.targetPath)
    }

    // Rename Inline Dialog
    Dialog {
        id: renameDialog
        title: "Rename Item"
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(360 * Theme.scaleFactor), Overlay.overlay ? Overlay.overlay.width - 32 : 420)
        modal: true

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.borderDim
            border.width: 1
            radius: Theme.radiusLarge
        }

        header: Rectangle {
            height: Math.round(40 * Theme.scaleFactor)
            color: Theme.bgCard
            radius: Theme.radiusLarge
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "✏️ Rename Item"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            TextField {
                id: newNameField
                text: root.targetName
                Layout.fillWidth: true
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                focus: true
                selectByMouse: true
                background: Rectangle {
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: newNameField.activeFocus ? Theme.accent : Theme.borderDim
                    border.width: 1
                }
                onAccepted: renameDialog.accept()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: renameDialog.reject()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(78 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : "transparent"
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }

                Button {
                    text: "Rename"
                    onClicked: renameDialog.accept()
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(88 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.accentHover : Theme.accent
                        radius: Theme.radiusSmall
                    }
                }
            }
        }

        onAccepted: {
            backend.renameItem(root.targetPath, newNameField.text)
        }
    }
}
