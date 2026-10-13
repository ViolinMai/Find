import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgSidebar

    readonly property var item: backend.selectedItem
    readonly property bool hasSelection: item && item.path !== undefined && item.path !== ""

    function safeVal(val) {
        return (val !== undefined && val !== null) ? String(val) : ""
    }

    visible: hasSelection

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.round(14 * Theme.scaleFactor)
        spacing: Math.round(10 * Theme.scaleFactor)

        Text {
            text: "Details & Preview"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        // Preview Viewport
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(180 * Theme.scaleFactor)
            color: Theme.bgBase
            radius: Theme.radiusMedium
            border.color: Theme.borderDim
            border.width: 1
            clip: true

            // Image Preview or Video Thumbnail
            Image {
                anchors.fill: parent
                anchors.margins: 4
                visible: root.hasSelection && (root.item.is_image === true || (root.item.is_video === true && root.safeVal(root.item.thumb) !== ""))
                source: visible ? (root.item.is_image ? "file://" + root.safeVal(root.item.path) : "file://" + root.safeVal(root.item.thumb)) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
            }

            // Video Details Header (Placed on the Left)
            RowLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 10
                visible: root.hasSelection && root.item.is_video === true
                spacing: 8

                Text {
                    text: "🎬"
                    font.pixelSize: Math.round(28 * Theme.scaleFactor)
                }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: root.hasSelection && root.safeVal(root.item.resolution) !== "" ? root.safeVal(root.item.resolution) : "Video Media"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }
                    Text {
                        text: root.hasSelection && root.safeVal(root.item.codec) !== "" ? root.safeVal(root.item.codec) : ""
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Text Preview
            ScrollView {
                anchors.fill: parent
                anchors.margins: 8
                visible: root.hasSelection && root.safeVal(root.item.preview_text) !== "" && !root.item.is_image && !root.item.is_video
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

            // Folder and Generic Fallback
            Text {
                anchors.centerIn: parent
                visible: root.hasSelection && !root.item.is_image && (!root.item.is_video || root.safeVal(root.item.thumb) === "") && root.safeVal(root.item.preview_text) === ""
                text: (root.hasSelection && root.item.is_dir) ? "📁 Folder" : "No preview available"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeNormal
            }
        }

        // Details Section
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Math.round(8 * Theme.scaleFactor)

                Text {
                    Layout.fillWidth: true
                    text: root.hasSelection ? root.safeVal(root.item.name) : ""
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderDim
                }

                component DetailRow: RowLayout {
                    property string label: ""
                    property string val: ""
                    visible: val !== ""

                    Text {
                        Layout.preferredWidth: Math.round(85 * Theme.scaleFactor)
                        text: parent.label
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.val
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }

                DetailRow { label: "Type"; val: root.hasSelection ? root.safeVal(root.item.type) : "" }
                DetailRow { label: "Size"; val: root.hasSelection ? root.safeVal(root.item.size) : "" }
                DetailRow { label: "Modified"; val: root.hasSelection ? root.safeVal(root.item.modified) : "" }

                DetailRow { label: "Resolution"; val: root.hasSelection ? root.safeVal(root.item.resolution) : "" }
                DetailRow { label: "Video Codec"; val: root.hasSelection ? root.safeVal(root.item.codec) : "" }
                DetailRow { label: "Bit Depth"; val: root.hasSelection ? root.safeVal(root.item.bit_depth) : "" }
                DetailRow { label: "Color Space"; val: root.hasSelection ? root.safeVal(root.item.color_profile) : "" }
                DetailRow { label: "Framerate"; val: root.hasSelection ? root.safeVal(root.item.fps) : "" }
                DetailRow { label: "Bitrate"; val: root.hasSelection ? root.safeVal(root.item.bitrate) : "" }
                DetailRow { label: "Audio Codec"; val: root.hasSelection ? root.safeVal(root.item.audio_codec) : "" }

                DetailRow { label: "Path"; val: root.hasSelection ? root.safeVal(root.item.path) : "" }
            }
        }
    }
}
