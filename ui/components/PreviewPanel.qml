import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgSidebar

    readonly property var item: backend ? backend.selectedItem : null
    readonly property bool hasSelection: item && item.path !== undefined && item.path !== ""

    function safeVal(val) {
        return (val !== undefined && val !== null) ? String(val) : ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Text {
            text: "Details & Preview"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        // Preview Viewport (Adapts to aspect ratio & shows FolderPreviewIcon for folders)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Math.round(180 * Theme.scaleFactor), Math.max(95, root.height * 0.36))

            // Folder Preview inside Details Panel
            FolderPreviewIcon {
                visible: root.hasSelection && root.item.is_dir === true
                width: Math.min(parent.width * 0.78, parent.height * 0.94)
                height: width * 0.88
                anchors.centerIn: parent
                previews: (root.hasSelection && root.item.folder_previews) ? root.item.folder_previews : []
            }

            // Image or Video Preview with Floating Aspect-Ratio Frame
            Item {
                visible: root.hasSelection && (root.item.is_image === true || (root.item.is_video === true && root.safeVal(root.item.thumb) !== ""))
                anchors.fill: parent

                Image {
                    id: panelImg
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    source: parent.visible ? (root.item.is_image ? "file://" + root.safeVal(root.item.path) : "file://" + root.safeVal(root.item.thumb)) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    mipmap: true
                }

                Rectangle {
                    anchors.centerIn: panelImg
                    width: panelImg.paintedWidth > 0 ? panelImg.paintedWidth + 4 : 0
                    height: panelImg.paintedHeight > 0 ? panelImg.paintedHeight + 4 : 0
                    radius: Theme.radiusMedium
                    color: "transparent"
                    border.color: Theme.borderDim
                    border.width: 1
                    visible: panelImg.status === Image.Ready
                }
            }

            // Text / Code Preview Box
            Rectangle {
                anchors.fill: parent
                visible: root.hasSelection && root.safeVal(root.item.preview_text) !== "" && !root.item.is_image && !root.item.is_video && !root.item.is_dir
                color: Theme.bgSurface
                radius: Theme.radiusMedium
                border.color: Theme.borderDim
                border.width: 1
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    Text {
                        width: parent.width
                        text: root.hasSelection ? root.safeVal(root.item.preview_text) : ""
                        color: Theme.textSecondary
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            // Empty / No Selection Fallback
            Rectangle {
                anchors.fill: parent
                visible: !root.hasSelection || (!root.item.is_dir && !root.item.is_image && (!root.item.is_video || root.safeVal(root.item.thumb) === "") && root.safeVal(root.item.preview_text) === "")
                color: Theme.bgSurface
                radius: Theme.radiusMedium
                border.color: Theme.borderDim
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.hasSelection ? "📄 No preview available" : "📂 Select an item to inspect"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeNormal
                }
            }
        }

        // Details Metadata Section
        Flickable {
            id: detailsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: detailsCol.implicitHeight + 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ColumnLayout {
                id: detailsCol
                width: detailsFlick.width
                spacing: 7

                Text {
                    Layout.fillWidth: true
                    text: root.hasSelection ? root.safeVal(root.item.name) : "Current Location"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.borderDim
                }

                component DetailRow: RowLayout {
                    property string label: ""
                    property string val: ""
                    visible: val !== ""
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.preferredWidth: Math.min(85, root.width * 0.35)
                        text: parent.label
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.val
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                DetailRow { label: "Type"; val: root.hasSelection ? root.safeVal(root.item.type) : "Directory" }
                DetailRow { label: "Size"; val: root.hasSelection ? root.safeVal(root.item.size) : "" }
                DetailRow { label: "Modified"; val: root.hasSelection ? root.safeVal(root.item.modified) : "" }

                DetailRow { label: "Resolution"; val: root.hasSelection ? root.safeVal(root.item.resolution) : "" }
                DetailRow { label: "Video Codec"; val: root.hasSelection ? root.safeVal(root.item.codec) : "" }
                DetailRow { label: "Bit Depth"; val: root.hasSelection ? root.safeVal(root.item.bit_depth) : "" }
                DetailRow { label: "Color Space"; val: root.hasSelection ? root.safeVal(root.item.color_profile) : "" }
                DetailRow { label: "Framerate"; val: root.hasSelection ? root.safeVal(root.item.fps) : "" }
                DetailRow { label: "Bitrate"; val: root.hasSelection ? root.safeVal(root.item.bitrate) : "" }
                DetailRow { label: "Audio Codec"; val: root.hasSelection ? root.safeVal(root.item.audio_codec) : "" }

                DetailRow { label: "Path"; val: root.hasSelection ? root.safeVal(root.item.path) : (backend ? backend.currentPath : "") }
            }
        }
    }
}
