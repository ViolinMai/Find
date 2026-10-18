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

        // Preview Viewport (Adapts to aspect ratio & shows tall vertical poster for movies & series folders!)
        Item {
            readonly property bool hasPosterImg: root.hasSelection && root.safeVal(root.item.poster) !== "" && (!root.item.is_dir || (backend && backend.showSeriesPosters))
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(
                Math.round((hasPosterImg ? 255 : 180) * Theme.scaleFactor),
                Math.max(110, root.height * (hasPosterImg ? 0.46 : 0.36))
            )

            // Folder Preview inside Details Panel (when no vertical poster overrides it)
            FolderPreviewIcon {
                visible: root.hasSelection && root.item.is_dir === true && !parent.hasPosterImg
                width: Math.min(parent.width * 0.78, parent.height * 0.94)
                height: width * 0.88
                anchors.centerIn: parent
                previews: (root.hasSelection && root.item.folder_previews) ? root.item.folder_previews : []
            }

            // Image, Video, or Jellyfin Vertical Movie Poster Preview
            Item {
                visible: root.hasSelection && (parent.hasPosterImg || root.item.is_image === true || (root.item.is_video === true && root.safeVal(root.item.thumb) !== ""))
                anchors.fill: parent

                Image {
                    id: panelImg
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    source: parent.visible
                            ? (parent.parent.hasPosterImg
                               ? ("file://" + root.safeVal(root.item.poster))
                               : (root.item.is_image ? "file://" + root.safeVal(root.item.path) : "file://" + root.safeVal(root.item.thumb)))
                            : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    mipmap: true
                }

                Rectangle {
                    anchors.centerIn: panelImg
                    width: panelImg.paintedWidth > 0 ? panelImg.paintedWidth : 0
                    height: panelImg.paintedHeight > 0 ? panelImg.paintedHeight : 0
                    radius: Math.round(9 * Theme.scaleFactor)
                    color: "transparent"
                    border.color: parent.parent.hasPosterImg ? "transparent" : Theme.borderDim
                    border.width: parent.parent.hasPosterImg ? 0 : 1
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
                    text: {
                        if (!root.hasSelection) return "Current Location"
                        var epT = root.safeVal(root.item.episode_title)
                        return epT !== "" ? epT : root.safeVal(root.item.name)
                    }
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                    horizontalAlignment: Text.AlignLeft
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
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideMiddle
                    }
                }

                DetailRow { label: "Selected"; val: (root.hasSelection && root.item.is_multi === true) ? (String(root.item.multi_count) + " Items") : "" }
                DetailRow { label: "Episode"; val: root.hasSelection ? root.safeVal(root.item.episode_title) : "" }
                DetailRow { label: "Rating"; val: (root.hasSelection && root.safeVal(root.item.rating) !== "") ? ("⭐ " + root.safeVal(root.item.rating)) : "" }
                DetailRow { label: "Type"; val: root.hasSelection ? root.safeVal(root.item.type) : "Directory" }
                DetailRow { label: (root.hasSelection && root.item.is_multi === true) ? "Total Size" : "Size"; val: root.hasSelection ? root.safeVal(root.item.size) : "" }
                DetailRow { label: "Modified"; val: root.hasSelection ? root.safeVal(root.item.modified) : "" }

                readonly property bool isVideoItem: root.hasSelection && root.item.is_video === true

                DetailRow { visible: detailsCol.isVideoItem; label: "Resolution"; val: root.hasSelection ? (root.safeVal(root.item.resolution) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Video Codec"; val: root.hasSelection ? (root.safeVal(root.item.codec) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Bit Depth"; val: root.hasSelection ? (root.safeVal(root.item.bit_depth) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Color Space"; val: root.hasSelection ? (root.safeVal(root.item.color_profile) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Framerate"; val: root.hasSelection ? (root.safeVal(root.item.fps) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Bitrate"; val: root.hasSelection ? (root.safeVal(root.item.bitrate) || "…") : "" }
                DetailRow { visible: detailsCol.isVideoItem; label: "Audio Codec"; val: root.hasSelection ? (root.safeVal(root.item.audio_codec) || "…") : "" }

                // Audio Languages Row (Arabic always first when present)
                RowLayout {
                    visible: detailsCol.isVideoItem
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.preferredWidth: Math.min(85, root.width * 0.35)
                        Layout.alignment: Qt.AlignTop
                        text: "Audio Langs"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: (root.hasSelection && root.item.audio_langs && root.item.audio_langs.length > 0) ? root.item.audio_langs : ["…"]
                            delegate: Rectangle {
                                readonly property bool isAr: String(modelData).toLowerCase().startsWith("ar")
                                implicitWidth: aLangTxt.implicitWidth + 10
                                implicitHeight: Math.round(18 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: isAr ? "#2810b981" : Theme.bgSurface
                                border.color: isAr ? "#10b981" : Theme.borderDim
                                border.width: 1

                                Text {
                                    id: aLangTxt
                                    anchors.centerIn: parent
                                    text: String(modelData)
                                    color: parent.isAr ? "#34d399" : Theme.textSecondary
                                    font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                    font.bold: parent.isAr
                                }
                            }
                        }
                    }
                }

                // Subtitle Languages Row (Internal + External, Arabic always first when present)
                RowLayout {
                    visible: detailsCol.isVideoItem
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.preferredWidth: Math.min(85, root.width * 0.35)
                        Layout.alignment: Qt.AlignTop
                        text: "Subtitles"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: (root.hasSelection && root.item.sub_langs && root.item.sub_langs.length > 0) ? root.item.sub_langs : (root.hasSelection && root.safeVal(root.item.resolution) === "…" ? ["…"] : ["none"])
                            delegate: Rectangle {
                                readonly property string codeStr: String(modelData)
                                readonly property bool isAr: codeStr.toLowerCase().startsWith("ar")
                                readonly property bool isExt: codeStr.indexOf("ext") !== -1
                                implicitWidth: sLangTxt.implicitWidth + 10
                                implicitHeight: Math.round(18 * Theme.scaleFactor)
                                radius: Theme.radiusSmall
                                color: isAr ? "#2810b981" : (isExt ? "#250078d4" : Theme.bgSurface)
                                border.color: isAr ? "#10b981" : (isExt ? Theme.accent : Theme.borderDim)
                                border.width: 1

                                Text {
                                    id: sLangTxt
                                    anchors.centerIn: parent
                                    text: parent.codeStr
                                    color: parent.isAr ? "#34d399" : (parent.isExt ? "#38bdf8" : Theme.textSecondary)
                                    font.pixelSize: Math.round(9 * Theme.scaleFactor)
                                    font.bold: parent.isAr || parent.isExt
                                }
                            }
                        }
                    }
                }

                // Jellyfin Synopsis / Overview Box
                Rectangle {
                    visible: root.hasSelection && root.safeVal(root.item.overview) !== ""
                    Layout.fillWidth: true
                    implicitHeight: overviewCol.implicitHeight + 14
                    radius: Theme.radiusSmall
                    color: Theme.bgSurface
                    border.color: Theme.borderDim
                    border.width: 1

                    ColumnLayout {
                        id: overviewCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            text: "📖 Synopsis (Jellyfin)"
                            color: Theme.accent
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.hasSelection ? root.safeVal(root.item.overview) : ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Clickable Path Row -> Copies plaintext path directly on click!
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: pathRowLayout.implicitHeight + 10
                    radius: Theme.radiusSmall
                    color: pathCopyMouse.containsMouse ? Theme.bgHover : Theme.bgSurface
                    border.color: pathCopyMouse.containsMouse ? Theme.accent : Theme.borderDim
                    border.width: 1

                    RowLayout {
                        id: pathRowLayout
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        Text {
                            text: "📋 Path"
                            color: pathCopyMouse.containsMouse ? Theme.accent : Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.hasSelection ? root.safeVal(root.item.path) : (backend ? backend.currentPath : "")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideMiddle
                        }
                    }

                    MouseArea {
                        id: pathCopyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!backend) return
                            var p = root.hasSelection ? root.safeVal(root.item.path) : backend.currentPath
                            if (p !== "") backend.copyToClipboard(p)
                        }
                    }
                }
            }
        }
    }
}
