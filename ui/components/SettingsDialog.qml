import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Find - Settings"
    width: Overlay.overlay ? Math.min(Math.round(740 * Theme.scaleFactor), Overlay.overlay.width - 20) : 780
    height: Overlay.overlay ? Math.min(Math.round(520 * Theme.scaleFactor), Overlay.overlay.height - 20) : 550
    modal: true
    anchors.centerIn: Overlay.overlay

    property var hiddenItemsList: backend ? backend.getHiddenSidebarItems() : []
    property var customQAList: backend ? backend.getAllCustomQuickAccess() : []
    property var mediaLibsList: backend ? backend.getMediaLibraries() : []
    property var defaultIconsMap: backend ? backend.getDefaultTypeIcons() : ({})
    property int selectedQAIndex: -1
    property string activePickerTarget: ""

    Connections {
        target: backend
        function onPickerCompleted(paths) {
            if (paths.length > 0) {
                var selected = paths[0]
                if (root.activePickerTarget === "qa_path") {
                    pathInput.text = selected
                } else if (root.activePickerTarget === "qa_icon") {
                    iconInput.text = selected
                } else if (root.activePickerTarget === "media_lib_series") {
                    backend.addMediaLibrary(selected, "series")
                    root.mediaLibsList = backend.getMediaLibraries()
                } else if (root.activePickerTarget === "media_lib_movies") {
                    backend.addMediaLibrary(selected, "movies")
                    root.mediaLibsList = backend.getMediaLibraries()
                } else if (root.activePickerTarget.startsWith("def_icon_")) {
                    var key = root.activePickerTarget.replace("def_icon_", "")
                    backend.setDefaultTypeIcon(key, selected)
                    root.defaultIconsMap = backend.getDefaultTypeIcons()
                }
                backend.cancelPicker()
                root.open()
            }
        }
        function onMediaLibraryStateChanged() {
            if (backend) {
                root.mediaLibsList = backend.getMediaLibraries()
            }
        }
    }

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.borderDim
        border.width: 1
        radius: Theme.radiusLarge
    }

    header: Rectangle {
        height: Math.round(46 * Theme.scaleFactor)
        color: Theme.bgCard
        radius: Theme.radiusLarge

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10

            Text {
                text: "⚙️ Find Settings"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                visible: root.width > Math.round(460 * Theme.scaleFactor)
            }

            Item { Layout.fillWidth: true }

            TabBar {
                id: settingsTabs
                background: Rectangle { color: "transparent" }

                TabButton { text: "General & UI" }
                TabButton { text: "Media Library" }
                TabButton { text: "MPV Config" }
                TabButton { text: "Quick Access" }
                TabButton { text: "Icons" }
                TabButton { text: "Hidden" }
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Math.round(14 * Theme.scaleFactor)
        currentIndex: settingsTabs.currentIndex

        // TAB 1: General, Grid Style & Hyprland Layout
        ColumnLayout {
            spacing: Math.round(12 * Theme.scaleFactor)

            Text {
                text: "Grid Preview & Layout Style"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Media & Folder Display Mode:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                }

                Button {
                    text: "✨ Floating Preview"
                    onClicked: if (backend) backend.setGridStyle("floating")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: backend ? backend.gridStyle === "floating" : true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(135 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: (backend && backend.gridStyle === "floating") ? Theme.accent : Theme.bgCard
                        border.color: (backend && backend.gridStyle === "floating") ? Theme.accentHover : Theme.borderDim
                    }
                }

                Button {
                    text: "🃏 Framed Cards"
                    onClicked: if (backend) backend.setGridStyle("cards")
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: backend ? backend.gridStyle === "cards" : false
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(125 * Theme.scaleFactor)
                        implicitHeight: Math.round(30 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: (backend && backend.gridStyle === "cards") ? Theme.accent : Theme.bgCard
                        border.color: (backend && backend.gridStyle === "cards") ? Theme.accentHover : Theme.borderDim
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Quick Access Sidebar Layout:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                }

                Repeater {
                    model: [
                        { key: "auto", label: "Auto (Hyprland)" },
                        { key: "full", label: "Full Sidebar" },
                        { key: "rail", label: "Icon Rail" },
                        { key: "topbar", label: "Top Strip" }
                    ]
                    delegate: Button {
                        text: modelData.label
                        onClicked: if (backend) backend.setSidebarMode(modelData.key)
                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.bold: backend ? backend.sidebarMode === modelData.key : false
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                        }
                        background: Rectangle {
                            implicitWidth: Math.round(96 * Theme.scaleFactor)
                            implicitHeight: Math.round(28 * Theme.scaleFactor)
                            radius: Theme.radiusSmall
                            color: (backend && backend.sidebarMode === modelData.key) ? Theme.accent : Theme.bgCard
                            border.color: (backend && backend.sidebarMode === modelData.key) ? Theme.accentHover : Theme.borderDim
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Transparent Window (Hyprland Blur Ready):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.transparentBlur : false
                    onToggled: if (backend) backend.transparentBlur = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Show Hidden Files & Folders (Ctrl+H):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.showHidden : false
                    onToggled: if (backend) backend.setShowHidden(checked)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Swap Left & Right Mouse Button Roles (Select/Drag):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Switch {
                    checked: backend ? backend.swapMouseButtons : false
                    onToggled: if (backend) backend.setSwapMouseButtons(checked)
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

            Text {
                text: "Storage & Thumbnail Cache"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Current Cache Usage:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: backend ? backend.currentCacheSize : "0 B"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Max Cache Limit:"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                    }
                    Text {
                        text: Math.round(cacheSlider.value) + " MB"
                        color: Theme.textPrimary
                        font.bold: true
                        font.pixelSize: Theme.fontSizeNormal
                    }
                }

                Slider {
                    id: cacheSlider
                    Layout.fillWidth: true
                    from: 100
                    to: 4000
                    stepSize: 50
                    value: backend ? backend.maxCacheMb : 500
                    onMoved: if (backend) backend.setMaxCacheMb(Math.round(value))
                }
            }

            Button {
                text: "Clear Cache Now"
                onClicked: backend.clearCache()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textDanger
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(140 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    radius: Theme.radiusMedium
                    border.color: Theme.borderDim
                }
            }

            Item { Layout.fillHeight: true }
        }

        // TAB 2: Media Library Manager (Series/Anime & Movies Folders + MPV Sync)
        ColumnLayout {
            spacing: Math.round(10 * Theme.scaleFactor)

            Text {
                text: "Media Library Folders (Anime, Series & Movies)"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "Folders added here (and all their subfolders) keep full File Manager features while enabling smart episode numbering, thin progress bars, custom completion checkmarks, silver 'HDR' badges, 'NEW' badges, automatic subtitle hiding (press 'C' to toggle), and live MPV playback tracking."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.round(38 * Theme.scaleFactor)
                radius: Theme.radiusSmall
                color: Theme.bgCard
                border.color: Theme.borderDim
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        implicitWidth: hdrSetPreview.implicitWidth + 10
                        implicitHeight: Math.round(17 * Theme.scaleFactor)
                        radius: 3
                        color: "#24e2e8f0"
                        border.color: "#e2e8f0"
                        border.width: 1

                        Text {
                            id: hdrSetPreview
                            anchors.centerIn: parent
                            text: "HDR"
                            color: "#f8fafc"
                            font.pixelSize: Math.round(8 * Theme.scaleFactor)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }

                    Text {
                        text: "Auto-Play HDR Content in HDR Mode (via mediainfo & toggle-hdr.sh):"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Switch {
                        checked: backend ? backend.autoPlayHdr : true
                        onToggled: if (backend) backend.setAutoPlayHdr(checked)
                    }
                }
            }

            // Background Media Daemon Control Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: daemonCol.implicitHeight + 18
                radius: Theme.radiusSmall
                color: Theme.bgCard
                border.color: (backend && backend.isDaemonRunning) ? "#4010b981" : Theme.borderDim
                border.width: 1

                ColumnLayout {
                    id: daemonCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: Math.round(10 * Theme.scaleFactor)
                            height: Math.round(10 * Theme.scaleFactor)
                            radius: width / 2
                            color: (backend && backend.isDaemonRunning) ? "#10b981" : "#f87171"
                        }

                        Text {
                            text: (backend && backend.isDaemonRunning)
                                  ? "MPV Tracker & HDR Daemon: Running"
                                  : "MPV Tracker & HDR Daemon: Stopped"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }

                        Rectangle {
                            visible: backend ? backend.isDaemonInstalled : false
                            implicitWidth: srvTag.implicitWidth + 8
                            implicitHeight: Math.round(16 * Theme.scaleFactor)
                            radius: 3
                            color: "#220078d4"
                            border.color: Theme.accent
                            border.width: 1
                            Text {
                                id: srvTag
                                anchors.centerIn: parent
                                text: "systemd --user"
                                color: "#38bdf8"
                                font.pixelSize: Math.round(8 * Theme.scaleFactor)
                                font.bold: true
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Auto-Start:"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            checked: backend ? backend.daemonAutostart : true
                            onToggled: if (backend) backend.setDaemonAutostart(checked)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Button {
                            text: (backend && backend.isDaemonInstalled) ? "🔄 Reinstall Service" : "⚡ Create & Install Daemon"
                            onClicked: if (backend) backend.installOrSaveDaemonService("")
                        }

                        Button {
                            text: (backend && backend.isDaemonRunning) ? "↻ Restart" : "▶ Start"
                            onClicked: if (backend) backend.restartMediaDaemon()
                        }

                        Button {
                            text: "⏹ Stop"
                            enabled: backend ? backend.isDaemonRunning : false
                            onClicked: if (backend) backend.stopMediaDaemon()
                        }

                        Button {
                            text: "✎ Edit Unit"
                            onClicked: {
                                if (backend) {
                                    daemonUnitEditor.text = backend.getDaemonServiceContent()
                                    daemonEditDialog.open()
                                }
                            }
                        }

                        Button {
                            text: "🗑️ Remove"
                            enabled: backend ? (backend.isDaemonInstalled || backend.isDaemonRunning) : false
                            onClicked: if (backend) backend.removeDaemonService()
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }

            Dialog {
                id: daemonEditDialog
                title: "Edit find-media-daemon.service"
                modal: true
                anchors.centerIn: Overlay.overlay
                width: Math.min(Math.round(520 * Theme.scaleFactor), root.width - 24)
                height: Math.min(Math.round(340 * Theme.scaleFactor), root.height - 24)

                background: Rectangle {
                    color: Theme.bgSurface
                    border.color: Theme.accent
                    border.width: 1
                    radius: Theme.radiusLarge
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "~/.config/systemd/user/find-media-daemon.service"
                        color: Theme.textSecondary
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: daemonUnitEditor
                            color: Theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            selectByMouse: true
                            background: Rectangle {
                                color: Theme.bgCard
                                radius: Theme.radiusSmall
                                border.color: Theme.borderDim
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "Cancel"
                            onClicked: daemonEditDialog.close()
                        }
                        Button {
                            text: "💾 Save & Reload Daemon"
                            onClicked: {
                                if (backend) backend.installOrSaveDaemonService(daemonUnitEditor.text)
                                daemonEditDialog.close()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "＋ Add Series / Anime Library..."
                    onClicked: {
                        root.activePickerTarget = "media_lib_series"
                        root.close()
                        backend.openInternalPicker("folder", "", "Select Series / Anime Root Folder")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(195 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.accentHover : Theme.accent
                        radius: Theme.radiusSmall
                    }
                }

                Button {
                    text: "🎬 Add Movies Library..."
                    onClicked: {
                        root.activePickerTarget = "media_lib_movies"
                        root.close()
                        backend.openInternalPicker("folder", "", "Select Movies Root Folder")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textPrimary
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(165 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : Theme.bgCard
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }

                Item { Layout.fillWidth: true }
            }

            ListView {
                id: mediaLibListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: root.mediaLibsList

                delegate: Rectangle {
                    width: mediaLibListView.width
                    height: Math.round(42 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: Theme.bgCard
                    border.color: Theme.borderDim

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: modelData.mode === "movies" ? "🎬" : "📺"
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: Theme.fontSizeNormal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.path
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }

                        Button {
                            text: modelData.mode === "movies" ? "Mode: Movies (Separators)" : "Mode: Series (Numbered)"
                            onClicked: {
                                if (!backend) return
                                var nextMode = modelData.mode === "movies" ? "series" : "movies"
                                backend.setMediaLibraryMode(modelData.path, nextMode)
                                root.mediaLibsList = backend.getMediaLibraries()
                            }
                        }

                        Button {
                            text: "Remove"
                            onClicked: {
                                if (!backend) return
                                backend.removeMediaLibrary(modelData.path)
                                root.mediaLibsList = backend.getMediaLibraries()
                            }
                        }
                    }
                }
            }
        }

        // TAB 3: MPV Config Editor (Both, SDR, and HDR Profiles -> Writes to ~/.config/mpv/mpv.conf)
        ColumnLayout {
            spacing: Math.round(8 * Theme.scaleFactor)

            Text {
                text: "MPV Configuration (~/.config/mpv/mpv.conf — Both / SDR / HDR)"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "'Both' holds shared base & subtitle settings. Any setting written in 'SDR' or 'HDR' (such as a custom sub-color) automatically overrides the corresponding key in 'Both'. HDR mode also runs 'toggle-hdr.sh --on' on launch and 'toggle-hdr.sh --off' when MPV closes."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // 1. BOTH (Shared Base & Subtitles)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Text {
                        text: "1. Both (Shared Base & Subs):"
                        color: Theme.accent
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: mpvBothEditor
                            text: backend ? backend.getMpvBothConfig() : ""
                            color: Theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            background: Rectangle {
                                color: Theme.bgCard
                                radius: Theme.radiusSmall
                                border.color: mpvBothEditor.activeFocus ? Theme.accent : Theme.borderDim
                                border.width: 1
                            }
                        }
                    }
                }

                // 2. SDR (Standard Mode Overrides)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Text {
                        text: "2. SDR Only (Overrides Both):"
                        color: "#34d399"
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: mpvSdrEditor
                            text: backend ? backend.getMpvSdrConfig() : ""
                            color: Theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            background: Rectangle {
                                color: Theme.bgCard
                                radius: Theme.radiusSmall
                                border.color: mpvSdrEditor.activeFocus ? Theme.accent : Theme.borderDim
                                border.width: 1
                            }
                        }
                    }
                }

                // 3. HDR (HDR Mode Overrides + Auto toggle-hdr.sh)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Text {
                        text: "3. HDR Only (Overrides Both):"
                        color: "#fbbf24"
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: mpvHdrEditor
                            text: backend ? backend.getMpvHdrConfig() : ""
                            color: Theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            background: Rectangle {
                                color: Theme.bgCard
                                radius: Theme.radiusSmall
                                border.color: mpvHdrEditor.activeFocus ? Theme.accent : Theme.borderDim
                                border.width: 1
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "💾 Save All (Both / SDR / HDR)"
                    onClicked: {
                        if (backend) {
                            backend.saveMpvConfigs(mpvBothEditor.text, mpvSdrEditor.text, mpvHdrEditor.text)
                            mpvSaveStatus.text = "✔ Saved & updated ~/.config/mpv/mpv.conf"
                        }
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(185 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.accentHover : Theme.accent
                        radius: Theme.radiusSmall
                    }
                }

                Button {
                    text: "↺ Reset Defaults"
                    onClicked: {
                        if (backend) {
                            backend.resetMpvConfigsToDefault()
                            mpvBothEditor.text = backend.getMpvBothConfig()
                            mpvSdrEditor.text = backend.getMpvSdrConfig()
                            mpvHdrEditor.text = backend.getMpvHdrConfig()
                            mpvSaveStatus.text = "↺ Restored defaults"
                        }
                    }
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        implicitWidth: Math.round(120 * Theme.scaleFactor)
                        implicitHeight: Math.round(32 * Theme.scaleFactor)
                        color: parent.hovered ? Theme.bgHover : Theme.bgCard
                        border.color: Theme.borderDim
                        radius: Theme.radiusSmall
                    }
                }

                Text {
                    id: mpvSaveStatus
                    text: ""
                    color: "#34d399"
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        // TAB 4: Quick Access Editor
        RowLayout {
            spacing: Math.round(14 * Theme.scaleFactor)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Text {
                    text: "Configure Shortcuts"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }

                ListView {
                    id: qaListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.customQAList
                    spacing: 4

                    delegate: Rectangle {
                        width: qaListView.width
                        height: Math.round(34 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: root.selectedQAIndex === index ? Theme.bgSelected : (itemHover.containsMouse ? Theme.bgHover : Theme.bgCard)
                        border.color: Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text { text: modelData.icon; font.pixelSize: Theme.fontSizeNormal }
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.bold: true
                                Layout.preferredWidth: 90
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
                            id: itemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedQAIndex = index
                                nameInput.text = modelData.name
                                pathInput.text = modelData.path
                                iconInput.text = modelData.icon
                            }
                        }
                    }
                }

                GridLayout {
                    columns: 3
                    Layout.fillWidth: true
                    rowSpacing: 6
                    columnSpacing: 8

                    Text { text: "Name:"; color: Theme.textSecondary }
                    TextField {
                        id: nameInput
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }

                    Text { text: "Target Path:"; color: Theme.textSecondary }
                    TextField {
                        id: pathInput
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }
                    Button {
                        text: "Browse..."
                        onClicked: {
                            root.activePickerTarget = "qa_path"
                            root.close()
                            backend.openInternalPicker("folder", "", "Select Target Folder")
                        }
                    }

                    Text { text: "Icon / Image:"; color: Theme.textSecondary }
                    TextField {
                        id: iconInput
                        Layout.fillWidth: true
                        color: Theme.textPrimary
                        background: Rectangle { color: Theme.bgCard; radius: 4; border.color: Theme.borderDim }
                    }
                    Button {
                        text: "Pick Icon..."
                        onClicked: {
                            root.activePickerTarget = "qa_icon"
                            root.close()
                            backend.openInternalPicker("file", "*.png;*.ico;*.svg", "Select Icon File")
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    Button {
                        text: "Save / Update"
                        onClicked: {
                            if (root.selectedQAIndex >= 0 && root.selectedQAIndex < root.customQAList.length) {
                                var list = root.customQAList.slice()
                                list[root.selectedQAIndex] = {
                                    "name": nameInput.text,
                                    "path": pathInput.text,
                                    "icon": iconInput.text
                                }
                                root.customQAList = list
                                backend.saveCustomQuickAccess(list)
                            }
                        }
                    }
                    Button {
                        text: "Add New"
                        onClicked: {
                            var list = root.customQAList.slice()
                            list.push({
                                "name": nameInput.text || "New Shortcut",
                                "path": pathInput.text || backend.currentPath,
                                "icon": iconInput.text || "⭐"
                            })
                            root.customQAList = list
                            backend.saveCustomQuickAccess(list)
                        }
                    }
                    Button {
                        text: "Delete"
                        enabled: root.selectedQAIndex >= 0
                        onClicked: {
                            var list = root.customQAList.slice()
                            list.splice(root.selectedQAIndex, 1)
                            root.customQAList = list
                            root.selectedQAIndex = -1
                            backend.saveCustomQuickAccess(list)
                        }
                    }
                }
            }
        }

        // TAB 3: Default Icons Configuration
        Flickable {
            id: iconFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: iconCol.implicitHeight + 16
            clip: true

            ColumnLayout {
                id: iconCol
                width: iconFlick.width
                spacing: 8

                Text {
                    text: "Customize Default File & Folder Icons"
                    color: Theme.textPrimary
                    font.bold: true
                    font.pixelSize: Theme.fontSizeMedium
                }

                Repeater {
                    model: [
                        { key: "folder", label: "Folder Icon" },
                        { key: "file", label: "Generic File Icon" },
                        { key: "image", label: "Image Files Icon" },
                        { key: "video", label: "Video Files Icon" },
                        { key: "audio", label: "Audio Files Icon" },
                        { key: "py", label: "Python Files Icon" },
                        { key: "rs", label: "Rust Files Icon" },
                        { key: "json", label: "JSON Files Icon" },
                        { key: "archive", label: "Archive Files Icon" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Math.round(38 * Theme.scaleFactor)
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: Theme.borderDim

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 150
                                text: modelData.label
                                color: Theme.textPrimary
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: root.defaultIconsMap[modelData.key] || "-"
                                color: Theme.textSecondary
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }

                            Button {
                                text: "Select Icon..."
                                onClicked: {
                                    root.activePickerTarget = "def_icon_" + modelData.key
                                    root.close()
                                    backend.openInternalPicker("file", "*.png;*.ico;*.svg", "Select Default Icon")
                                }
                            }
                        }
                    }
                }
            }
        }

        // TAB 4: Hidden Items
        ColumnLayout {
            spacing: 10

            Text {
                text: "Hidden Sidebar Items"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            ListView {
                id: hiddenListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.hiddenItemsList
                spacing: 6

                delegate: Rectangle {
                    width: hiddenListView.width
                    height: Math.round(36 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: Theme.bgCard
                    border.color: Theme.borderDim

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            elide: Text.ElideMiddle
                        }

                        Button {
                            text: "Restore"
                            onClicked: {
                                backend.restoreSidebarItem(modelData)
                                root.hiddenItemsList = backend.getHiddenSidebarItems()
                            }
                        }
                    }
                }
            }
        }
    }
}
