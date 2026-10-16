import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Select Icon"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Overlay.overlay ? Math.min(Math.round(740 * Theme.scaleFactor), Overlay.overlay.width - 24) : 760
    height: Overlay.overlay ? Math.min(Math.round(520 * Theme.scaleFactor), Overlay.overlay.height - 24) : 540
    padding: 0

    property string currentRootFolder: ""
    property string previewSelectedPath: ""
    signal iconChosen(string iconPath)

    function openIconBrowser(initialDir) {
        previewSelectedPath = ""
        searchField.text = ""
        if (initialDir && initialDir !== "") {
            currentRootFolder = initialDir
        } else if (backend) {
            var roots = backend.getIconSearchRoots()
            currentRootFolder = roots.length > 0 ? roots[0] : ""
        }
        if (backend) {
            backend.scanIconsRecursively(currentRootFolder, "")
        }
        root.open()
    }

    Connections {
        target: backend
        function onPickerCompleted(paths) {
            if (root.visible && paths.length > 0 && root.browsingCustomFolder) {
                root.browsingCustomFolder = false
                root.currentRootFolder = paths[0]
                backend.scanIconsRecursively(root.currentRootFolder, searchField.text)
            }
        }
    }

    property bool browsingCustomFolder: false

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.accent
        border.width: 1
        radius: Theme.radiusLarge
        clip: true
    }

    header: Rectangle {
        height: Math.round(48 * Theme.scaleFactor)
        color: "#16161b"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 10

            Text {
                text: "🖼️  Icon Browser (Recursive Folder Preview)"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: Math.round(28 * Theme.scaleFactor)
                height: Math.round(28 * Theme.scaleFactor)
                radius: Theme.radiusMedium
                color: closeIconDlgMouse.containsMouse ? "#35f87171" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: closeIconDlgMouse.containsMouse ? Theme.textDanger : Theme.textSecondary
                    font.bold: true
                }
                MouseArea {
                    id: closeIconDlgMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Top Filter & Directory Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "🔍 Search icons across all subfolders (e.g. folder, code, mpv, steam)..."
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                onTextChanged: {
                    if (backend) backend.scanIconsRecursively(root.currentRootFolder, text)
                }
                background: Rectangle {
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: Theme.bgCard
                    radius: Theme.radiusSmall
                    border.color: searchField.activeFocus ? Theme.accent : Theme.borderDim
                }
            }

            Button {
                text: "🌐 All System Icons"
                onClicked: {
                    root.currentRootFolder = ""
                    if (backend) backend.scanIconsRecursively("", searchField.text)
                }
                contentItem: Text {
                    text: parent.text
                    color: root.currentRootFolder === "" ? "#ffffff" : Theme.textPrimary
                    font.bold: root.currentRootFolder === ""
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(130 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: root.currentRootFolder === "" ? Theme.accent : (parent.hovered ? Theme.bgHover : Theme.bgCard)
                    border.color: Theme.borderDim
                    radius: Theme.radiusSmall
                }
            }

            Button {
                text: "📂 Choose Folder..."
                onClicked: {
                    root.browsingCustomFolder = true
                    if (backend) backend.openInternalPicker("folder", "", "Select Root Icons Folder")
                }
                contentItem: Text {
                    text: parent.text
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(125 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    border.color: Theme.borderDim
                    radius: Theme.radiusSmall
                }
            }
        }

        // Quick Root Pills
        Flickable {
            Layout.fillWidth: true
            height: Math.round(26 * Theme.scaleFactor)
            contentWidth: rootsRow.implicitWidth
            contentHeight: height
            clip: true

            RowLayout {
                id: rootsRow
                height: parent.height
                spacing: 6

                Repeater {
                    model: backend ? backend.getIconSearchRoots() : []
                    delegate: Rectangle {
                        readonly property bool isCurrRoot: root.currentRootFolder === modelData
                        implicitWidth: rTxt.implicitWidth + 14
                        height: Math.round(24 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: isCurrRoot ? Theme.bgSelected : Theme.bgCard
                        border.color: isCurrRoot ? Theme.accent : Theme.borderDim

                        Text {
                            id: rTxt
                            anchors.centerIn: parent
                            text: modelData
                            color: parent.isCurrRoot ? Theme.textPrimary : Theme.textSecondary
                            font.family: "monospace"
                            font.pixelSize: Math.round(9 * Theme.scaleFactor)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentRootFolder = modelData
                                if (backend) backend.scanIconsRecursively(modelData, searchField.text)
                            }
                        }
                    }
                }
            }
        }

        // Recursive Icons Grid
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.bgBase
            radius: Theme.radiusMedium
            border.color: Theme.borderDim

            GridView {
                id: iconsGrid
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                cellWidth: Math.round(96 * Theme.scaleFactor)
                cellHeight: Math.round(92 * Theme.scaleFactor)
                model: backend ? backend.iconGalleryItems : []

                WheelHandler {
                    target: null
                    orientation: Qt.Vertical
                    onWheel: function(event) {
                        var step = (event.angleDelta.y / 120.0) * Math.round(240 * Theme.scaleFactor)
                        var maxY = Math.max(0, iconsGrid.contentHeight - iconsGrid.height)
                        iconsGrid.contentY = Math.max(0, Math.min(maxY, iconsGrid.contentY - step))
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: iconsGrid.cellWidth - 6
                    height: iconsGrid.cellHeight - 6
                    radius: Theme.radiusMedium
                    readonly property bool isPicked: root.previewSelectedPath === modelData.path
                    color: isPicked ? Theme.bgSelected : (icMouse.containsMouse ? Theme.bgHover : Theme.bgCard)
                    border.color: isPicked ? Theme.accent : Theme.borderDim
                    border.width: isPicked ? 2 : 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Image {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: "file://" + modelData.path
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 96
                            sourceSize.height: 96
                            asynchronous: true
                            mipmap: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: Math.round(9 * Theme.scaleFactor)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                        }
                    }

                    MouseArea {
                        id: icMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.previewSelectedPath = modelData.path
                        }
                        onDoubleClicked: {
                            root.iconChosen(modelData.path)
                            root.close()
                        }
                    }
                }
            }
        }

        // Bottom Live Preview & Confirm Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: Math.round(42 * Theme.scaleFactor)
                height: Math.round(42 * Theme.scaleFactor)
                radius: Theme.radiusMedium
                color: Theme.bgCard
                border.color: root.previewSelectedPath !== "" ? Theme.accent : Theme.borderDim

                Image {
                    anchors.fill: parent
                    anchors.margins: 5
                    visible: root.previewSelectedPath !== ""
                    source: visible ? ("file://" + root.previewSelectedPath) : ""
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 128
                    sourceSize.height: 128
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: root.previewSelectedPath !== "" ? "Selected Icon Preview" : "Click any icon above to preview (Double-click to apply)"
                    color: Theme.textPrimary
                    font.bold: true
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    Layout.fillWidth: true
                    text: root.previewSelectedPath
                    color: Theme.textTertiary
                    font.family: "monospace"
                    font.pixelSize: Math.round(9 * Theme.scaleFactor)
                    elide: Text.ElideMiddle
                }
            }

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
                    implicitWidth: Math.round(80 * Theme.scaleFactor)
                    implicitHeight: Math.round(34 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : "transparent"
                    border.color: Theme.borderDim
                    radius: Theme.radiusMedium
                }
            }

            Button {
                text: "✔ Use This Icon"
                enabled: root.previewSelectedPath !== ""
                onClicked: {
                    root.iconChosen(root.previewSelectedPath)
                    root.close()
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#ffffff" : Theme.textTertiary
                    font.bold: true
                    font.pixelSize: Theme.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(135 * Theme.scaleFactor)
                    implicitHeight: Math.round(34 * Theme.scaleFactor)
                    color: parent.enabled ? (parent.hovered ? Theme.accentHover : Theme.accent) : Theme.bgCard
                    radius: Theme.radiusMedium
                }
            }
        }
    }
}
