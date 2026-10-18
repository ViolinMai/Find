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
    readonly property bool isExecTarget: (backend && !root.isDir && targetPath !== "") ? backend.isExecutableFile(targetPath) : false
    readonly property bool isArchiveTarget: (backend && !root.isDir && targetPath !== "") ? backend.isArchiveFile(targetPath) : false
    readonly property string archiveSubfolderName: (backend && isArchiveTarget) ? backend.getArchiveBaseName(targetPath) : "Archive"
    readonly property string itemBaseName: {
        if (!targetName) return "Archive"
        var dotIdx = targetName.lastIndexOf(".")
        return (!root.isDir && dotIdx > 0) ? targetName.substring(0, dotIdx) : targetName
    }
    readonly property string shortArchiveBaseName: {
        var b = itemBaseName
        if (b.length > 18) {
            return b.substring(0, 15) + "..."
        }
        return b
    }
    readonly property string shortExtractSubfolderName: {
        var s = archiveSubfolderName
        if (s.length > 18) {
            return s.substring(0, 15) + "..."
        }
        return s
    }
    readonly property bool canInstallFontsTarget: (backend && targetPath !== "") ? backend.canInstallFontsFrom(targetPath) : false
    readonly property bool canResumeTargetFolder: (backend && root.isDir && targetPath !== "") ? backend.canResumeFolder(targetPath) : false
    readonly property bool isFavoritedTarget: (backend && targetPath !== "") ? backend.isPathFavorited(targetPath) : false
    readonly property bool isInTrash: backend ? backend.isTrashView : false

    readonly property bool hasDialogOpen: renameDialog.visible || customArchiveDialog.visible

    signal requestDesktopMaker(string execPath)
    signal requestPermanentDelete(string targetPath)
    signal requestProperties(string targetPath)

    function popupSafe(anchorItem, mouseX, mouseY) {
        if (anchorItem && mouseX !== undefined && mouseY !== undefined) {
            root.popup(anchorItem, mouseX + 3, mouseY + 3)
        } else {
            root.popup()
        }
    }

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
        visible: backend ? (backend.currentPath === "mediahub://") : false
        iconGlyph: "📂"
        text: "Open Containing Folder"
        font.bold: true
        onTriggered: if (backend) backend.goToParentFolder(root.targetPath)
    }

    StyledMenuItem {
        visible: backend ? (backend.currentPath === "mediahub://") : false
        iconGlyph: "👁️"
        text: "Hide from Media Hub (Until Progress Changes)"
        isDanger: true
        onTriggered: if (backend) backend.hideFromMediaHub(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "▶"
        text: {
            if (!root.canResumeTargetFolder || !backend) return "Resume"
            var info = backend.getResumeFolderInfo(root.targetPath)
            if (!info.has_resume) return "Resume"
            return info.time_str !== ""
                   ? ("Resume " + info.ep_num + "  •  " + info.time_str)
                   : ("Resume " + info.ep_num)
        }
        visible: root.canResumeTargetFolder
        font.bold: true
        onTriggered: if (backend) backend.resumeMediaFolder(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "➕"
        text: "Open in New Tab"
        visible: root.isDir
        onTriggered: if (backend) backend.addTab(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "📊"
        text: "Storage Analyzer (Largest Items)"
        visible: root.isDir
        font.bold: true
        onTriggered: if (backend) backend.openStorageAnalyzer(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: root.isFavoritedTarget ? "★" : "☆"
        text: root.isFavoritedTarget ? "Remove from Favorites" : "Add to Favorites"
        font.bold: true
        onTriggered: {
            if (!backend) return
            if (root.isFavoritedTarget) {
                backend.removeFromFavorites(root.targetPath)
            } else {
                backend.addToFavorites(root.targetPath)
            }
        }
    }

    StyledMenuItem {
        iconGlyph: "▶️"
        text: "Run Executable"
        visible: root.isExecTarget
        font.bold: true
        onTriggered: if (backend) backend.runExecutable(root.targetPath, false)
    }

    StyledMenuItem {
        iconGlyph: "💻"
        text: "Run in Terminal"
        visible: root.isExecTarget
        onTriggered: if (backend) backend.runExecutable(root.targetPath, true)
    }

    StyledMenuItem {
        iconGlyph: "🚀"
        text: "Add to Applications (.desktop)..."
        visible: root.isExecTarget
        font.bold: true
        onTriggered: root.requestDesktopMaker(root.targetPath)
    }

    StyledMenuItem {
        iconGlyph: "🔤"
        text: "Install / Download Font(s) to System"
        visible: root.canInstallFontsTarget
        font.bold: true
        onTriggered: if (backend) backend.installFontsToSystem(root.targetPath, "")
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
        enabled: backend ? (backend.hasClipboardItems || backend.getClipboardPath() !== "") : false
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

    // 4. WinRAR-Style Extract & Archive Options
    StyledMenuItem {
        visible: root.isArchiveTarget
        iconGlyph: "📂"
        text: "Extract Here"
        font.bold: true
        onTriggered: if (backend) backend.extractArchive(root.targetPath, "here", "")
    }

    StyledMenuItem {
        visible: root.isArchiveTarget
        iconGlyph: "📁"
        text: "Extract to \"" + root.shortExtractSubfolderName + "/\""
        font.bold: true
        onTriggered: if (backend) backend.extractArchive(root.targetPath, "subfolder", "")
    }

    StyledMenuItem {
        visible: root.isArchiveTarget
        iconGlyph: "🧭"
        text: "Extract files... (Choose Folder)"
        onTriggered: if (backend) backend.extractArchive(root.targetPath, "choose", "")
    }

    MenuSeparator {
        visible: root.isArchiveTarget
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    StyledMenu {
        title: "Archive"
        iconGlyph: "📦"

        StyledMenuItem {
            iconGlyph: "📦"
            text: "Add to archive..."
            font.bold: true
            onTriggered: {
                customArchiveNameField.text = root.itemBaseName
                customArchiveDialog.selectedFormat = "zip"
                customArchiveDialog.open()
                customArchiveNameField.forceActiveFocus()
                customArchiveNameField.selectAll()
            }
        }
        StyledMenuItem {
            iconGlyph: "⚡"
            text: "Add to \"" + root.shortArchiveBaseName + ".zip\""
            onTriggered: if (backend) backend.compressItem(root.targetPath, "zip", root.itemBaseName)
        }
        StyledMenuItem {
            iconGlyph: "⚡"
            text: "Add to \"" + root.shortArchiveBaseName + ".tar.gz\""
            onTriggered: if (backend) backend.compressItem(root.targetPath, "tar.gz", root.itemBaseName)
        }
        StyledMenuItem {
            iconGlyph: "⚡"
            text: "Add to \"" + root.shortArchiveBaseName + ".7z\""
            onTriggered: if (backend) backend.compressItem(root.targetPath, "7z", root.itemBaseName)
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
        StyledMenuItem {
            visible: backend ? (backend.isMediaLibraryView || backend.isMediaHubView) : false
            iconGlyph: "👁️"
            text: "Hide from Media Hub (Until Progress Changes)"
            onTriggered: if (backend) backend.hideFromMediaHub(root.targetPath)
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
        }
        StyledMenuItem {
            iconGlyph: "🧹"
            text: root.isDir ? "Clear Local Cache (Folder & Subfolders)" : "Clear Local Cache & Refresh from Server"
            isDanger: true
            onTriggered: if (backend) backend.clearMediaEntryCache(root.targetPath)
        }
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    // 5. Trash / Restore / Permanent Delete
    StyledMenuItem {
        visible: root.isInTrash
        iconGlyph: "↩"
        text: "Restore / Revert to Original Location"
        font.bold: true
        onTriggered: if (backend) backend.restoreFromTrash(root.targetPath)
    }

    StyledMenuItem {
        visible: root.isInTrash
        iconGlyph: "🔥"
        text: "Delete Permanently..."
        shortcutText: "Del"
        isDanger: true
        font.bold: true
        onTriggered: root.requestPermanentDelete(root.targetPath)
    }

    StyledMenuItem {
        visible: !root.isInTrash
        iconGlyph: "🗑️"
        text: "Move to Trash"
        shortcutText: "Del"
        isDanger: true
        onTriggered: backend.moveToTrash(root.targetPath)
    }

    MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.borderDim }
    }

    StyledMenuItem {
        iconGlyph: "ℹ️"
        text: "Properties & Permissions"
        shortcutText: "Alt+Enter"
        onTriggered: root.requestProperties(root.targetPath)
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

    // WinRAR-style "Add to archive..." Modal Dialog
    Dialog {
        id: customArchiveDialog
        title: "Add to Archive"
        anchors.centerIn: Overlay.overlay
        width: Math.min(Math.round(410 * Theme.scaleFactor), Overlay.overlay ? Overlay.overlay.width - 32 : 440)
        modal: true

        property string selectedFormat: "zip"

        background: Rectangle {
            color: Theme.bgSurface
            border.color: Theme.accent
            border.width: 1
            radius: Theme.radiusLarge
        }

        header: Rectangle {
            height: Math.round(42 * Theme.scaleFactor)
            color: Theme.bgCard
            radius: Theme.radiusLarge
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "📦 Add to Archive"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Archive Name:"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            TextField {
                id: customArchiveNameField
                Layout.fillWidth: true
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                onAccepted: customArchiveDialog.accept()
                background: Rectangle {
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: customArchiveNameField.activeFocus ? Theme.accent : Theme.borderDim
                    border.width: 1
                }
            }

            Text {
                text: "Archive Format:"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["zip", "tar.gz", "tar.xz", "7z"]
                    delegate: Rectangle {
                        readonly property bool isChosen: customArchiveDialog.selectedFormat === modelData
                        Layout.fillWidth: true
                        height: Math.round(30 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: isChosen ? Theme.accent : Theme.bgCard
                        border.color: isChosen ? Theme.accentHover : Theme.borderDim
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "." + modelData.toUpperCase()
                            color: parent.isChosen ? "#ffffff" : Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: customArchiveDialog.selectedFormat = modelData
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: customArchiveDialog.reject()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(80 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : "transparent"
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }

                Button {
                    text: "🗜️ Create Archive"
                    onClicked: customArchiveDialog.accept()
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(135 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.accentHover : Theme.accent
                        radius: Theme.radiusSmall
                    }
                }
            }
        }

        onAccepted: {
            if (backend) {
                backend.compressItem(root.targetPath, customArchiveDialog.selectedFormat, customArchiveNameField.text)
            }
        }
    }
}
