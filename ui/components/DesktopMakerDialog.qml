import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Automate .desktop Application"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Overlay.overlay ? Math.min(Math.round(580 * Theme.scaleFactor), Overlay.overlay.width - 24) : 600
    height: Overlay.overlay ? Math.min(Math.round(480 * Theme.scaleFactor), Overlay.overlay.height - 24) : 500

    property string sourceExecPath: ""
    property var savedTemplates: backend ? backend.getSavedDesktopApps() : []

    function openForExecutable(filePath) {
        sourceExecPath = filePath
        savedTemplates = backend ? backend.getSavedDesktopApps() : []
        if (backend) {
            var preset = backend.getDesktopPresetForExec(filePath)
            appNameInput.text = preset.name || ""
            appExecInput.text = preset.exec_cmd || ("\"" + filePath + "\"")
            appIconInput.text = preset.icon || "application-x-executable"
            appCategoriesInput.text = preset.categories || "Utility;Application;"
            terminalSwitch.checked = Boolean(preset.terminal)
        }
        root.open()
    }

    Connections {
        target: backend
        function onDesktopAppsUpdated() {
            if (backend) root.savedTemplates = backend.getSavedDesktopApps()
        }
        function onPickerCompleted(paths) {
            if (paths.length > 0 && root.pickingIconMode) {
                appIconInput.text = paths[0]
                root.pickingIconMode = false
            }
        }
    }

    IconBrowserDialog {
        id: desktopIconBrowser
        onIconChosen: function(chosenPath) {
            appIconInput.text = chosenPath
        }
    }

    property bool pickingIconMode: false

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.accent
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
                text: "🚀 Automate .desktop Application Entry"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "~/.local/share/applications"
                color: Theme.textTertiary
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Saved Templates Quick Loader
        Rectangle {
            visible: root.savedTemplates.length > 0
            Layout.fillWidth: true
            implicitHeight: Math.round(68 * Theme.scaleFactor)
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderDim

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Text {
                    text: "Saved .desktop Templates (Click to reuse preset):"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: ListView.Horizontal
                    spacing: 6
                    clip: true
                    model: root.savedTemplates

                    delegate: Rectangle {
                        implicitWidth: tplRow.implicitWidth + 16
                        height: Math.round(26 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: tplMouse.containsMouse ? Theme.bgHover : Theme.bgSurface
                        border.color: Theme.borderDim

                        RowLayout {
                            id: tplRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "⚡"; font.pixelSize: Theme.fontSizeSmall }
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                        }

                        MouseArea {
                            id: tplMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                appNameInput.text = modelData.name
                                if (root.sourceExecPath !== "") {
                                    appExecInput.text = "\"" + root.sourceExecPath + "\""
                                } else {
                                    appExecInput.text = modelData.exec_cmd
                                }
                                appIconInput.text = modelData.icon
                                appCategoriesInput.text = modelData.categories || "Utility;Application;"
                                terminalSwitch.checked = Boolean(modelData.terminal)
                            }
                        }
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 10
            columnSpacing: 10

            Text { text: "App Name:"; color: Theme.textSecondary; font.bold: true }
            TextField {
                id: appNameInput
                Layout.columnSpan: 2
                Layout.fillWidth: true
                placeholderText: "e.g. Blender / Custom Script"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                background: Rectangle {
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: appNameInput.activeFocus ? Theme.accent : Theme.borderDim
                }
            }

            Text { text: "Exec Command:"; color: Theme.textSecondary; font.bold: true }
            TextField {
                id: appExecInput
                Layout.columnSpan: 2
                Layout.fillWidth: true
                placeholderText: "/path/to/executable --arg %U"
                color: Theme.textPrimary
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeSmall
                selectByMouse: true
                background: Rectangle {
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: appExecInput.activeFocus ? Theme.accent : Theme.borderDim
                }
            }

            Text { text: "App Icon:"; color: Theme.textSecondary; font.bold: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    width: Math.round(32 * Theme.scaleFactor)
                    height: Math.round(32 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: Theme.bgCard
                    border.color: Theme.borderDim

                    readonly property bool isImgPath: appIconInput.text.indexOf("/") !== -1 || appIconInput.text.indexOf(".") !== -1

                    Image {
                        anchors.fill: parent
                        anchors.margins: 4
                        visible: parent.isImgPath
                        source: visible ? ("file://" + appIconInput.text) : ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 64
                        sourceSize.height: 64
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !parent.isImgPath
                        text: "🚀"
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                TextField {
                    id: appIconInput
                    Layout.fillWidth: true
                    placeholderText: "Select icon or enter path..."
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    selectByMouse: true
                    background: Rectangle {
                        color: Theme.bgCard
                        radius: Theme.radiusSmall
                        border.color: appIconInput.activeFocus ? Theme.accent : Theme.borderDim
                    }
                }
            }
            Button {
                text: "🖼️ Browse Icons..."
                onClicked: desktopIconBrowser.openIconBrowser("")
                contentItem: Text {
                    text: parent.text
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(105 * Theme.scaleFactor)
                    implicitHeight: Math.round(30 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    border.color: Theme.borderDim
                    radius: Theme.radiusSmall
                }
            }

            Text { text: "Categories:"; color: Theme.textSecondary; font.bold: true }
            TextField {
                id: appCategoriesInput
                Layout.columnSpan: 2
                Layout.fillWidth: true
                text: "Utility;Application;"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeSmall
                selectByMouse: true
                background: Rectangle {
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: appCategoriesInput.activeFocus ? Theme.accent : Theme.borderDim
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "Run inside Terminal Window:"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                Layout.fillWidth: true
            }
            Switch {
                id: terminalSwitch
                checked: false
            }
        }

        Item { Layout.fillHeight: true }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderDim }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                onClicked: root.close()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(85 * Theme.scaleFactor)
                    implicitHeight: Math.round(34 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : "transparent"
                    border.color: Theme.borderDim
                    radius: Theme.radiusMedium
                }
            }

            Button {
                text: "⚡ Create & Save .desktop"
                onClicked: {
                    if (backend) {
                        var ok = backend.createAndSaveDesktopApp(
                            root.sourceExecPath,
                            appNameInput.text,
                            appExecInput.text,
                            appIconInput.text,
                            terminalSwitch.checked,
                            appCategoriesInput.text
                        )
                        if (ok) root.close()
                    }
                }
                contentItem: Text {
                    text: parent.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: Theme.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(180 * Theme.scaleFactor)
                    implicitHeight: Math.round(34 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.accentHover : Theme.accent
                    radius: Theme.radiusMedium
                }
            }
        }
    }
}
