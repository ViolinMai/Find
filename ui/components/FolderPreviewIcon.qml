import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    property var previews: []
    property bool isSelected: false

    readonly property var safeList: {
        if (!previews) return []
        var arr = []
        for (var i = 0; i < previews.length; i++) {
            arr.push(previews[i])
        }
        return arr
    }
    readonly property int count: safeList.length

    // Folder Back Tab
    Rectangle {
        id: backTab
        width: parent.width * 0.42
        height: parent.height * 0.16
        x: parent.width * 0.06
        y: parent.height * 0.06
        radius: Math.max(4, parent.width * 0.05)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f59e0b" }
            GradientStop { position: 1.0; color: "#b45309" }
        }
    }

    // Folder Back Plate
    Rectangle {
        id: backPlate
        x: parent.width * 0.06
        y: parent.height * 0.14
        width: parent.width * 0.88
        height: parent.height * 0.78
        radius: Math.max(6, parent.width * 0.065)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#d97706" }
            GradientStop { position: 1.0; color: "#78350f" }
        }
        border.color: "#fbbf24"
        border.width: 1
    }

    // Inner Pocket Content Area (Holds Prioritized Previews: Video -> Image -> Text)
    Item {
        id: pocketContent
        x: parent.width * 0.10
        y: parent.height * 0.17
        width: parent.width * 0.80
        height: parent.height * 0.68
        clip: true

        // Single Hero Preview (when count == 1)
        Rectangle {
            visible: root.count === 1
            anchors.fill: parent
            anchors.margins: 2
            radius: Math.max(5, parent.width * 0.05)
            color: "#18181f"
            border.color: "#45ffffff"
            border.width: 1
            clip: true

            readonly property var firstItem: root.count > 0 ? root.safeList[0] : null

            Image {
                anchors.fill: parent
                visible: parent.firstItem !== null && (parent.firstItem.kind === "video" || parent.firstItem.kind === "image") && parent.firstItem.thumb !== ""
                source: visible ? "file://" + parent.firstItem.thumb : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 256
                sourceSize.height: 256
                asynchronous: true
                mipmap: true
            }

            // Video Play Badge
            Rectangle {
                visible: parent.firstItem !== null && parent.firstItem.kind === "video"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                width: Math.max(18, parent.width * 0.22)
                height: width
                radius: width / 2
                color: "#cc000000"
                border.color: "#fbbf24"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: "#fbbf24"
                    font.pixelSize: Math.max(8, parent.width * 0.48)
                }
            }

            // Text Snippet Card
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 2
                visible: parent.firstItem !== null && parent.firstItem.kind === "text"

                Text {
                    text: "📄 " + (parent.parent.firstItem ? parent.parent.firstItem.name : "")
                    color: "#38bdf8"
                    font.pixelSize: Math.max(7, pocketContent.width * 0.09)
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: parent.parent.firstItem ? parent.parent.firstItem.snippet : ""
                    color: "#d4d4d8"
                    font.family: "monospace"
                    font.pixelSize: Math.max(6, pocketContent.width * 0.075)
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                }
            }
        }

        // Multi-Preview Grid (when count >= 2, up to 4 items ordered Video -> Image -> Text)
        GridLayout {
            visible: root.count >= 2
            anchors.fill: parent
            anchors.margins: 2
            columns: 2
            rowSpacing: 3
            columnSpacing: 3

            Repeater {
                model: root.count >= 2 ? root.safeList : []
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Math.max(3, pocketContent.width * 0.04)
                    color: "#18181f"
                    border.color: "#38ffffff"
                    border.width: 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: (modelData.kind === "video" || modelData.kind === "image") && modelData.thumb !== ""
                        source: visible ? "file://" + modelData.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 160
                        sourceSize.height: 160
                        asynchronous: true
                        mipmap: true
                    }

                    // Video Badge
                    Rectangle {
                        visible: modelData.kind === "video"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 2
                        width: Math.max(13, parent.width * 0.30)
                        height: width
                        radius: width / 2
                        color: "#cc000000"
                        border.color: "#fbbf24"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            color: "#fbbf24"
                            font.pixelSize: Math.max(6, parent.width * 0.45)
                        }
                    }

                    // Text Snippet Preview
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 1
                        visible: modelData.kind === "text"

                        Text {
                            text: modelData.name
                            color: "#38bdf8"
                            font.pixelSize: Math.max(6, pocketContent.width * 0.075)
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.snippet
                            color: "#a1a1aa"
                            font.family: "monospace"
                            font.pixelSize: Math.max(5, pocketContent.width * 0.065)
                            wrapMode: Text.WrapAnywhere
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                        }
                    }
                }
            }
        }
    }

    // Folder Front Flap (File Explorer Lower Glass/Amber Lip when previews exist, or Full Flap when empty)
    Rectangle {
        id: frontFlap
        x: parent.width * 0.05
        y: root.count > 0 ? parent.height * 0.64 : parent.height * 0.24
        width: parent.width * 0.90
        height: root.count > 0 ? parent.height * 0.29 : parent.height * 0.69
        radius: Math.max(6, parent.width * 0.065)

        gradient: Gradient {
            GradientStop { position: 0.0; color: root.count > 0 ? "#e6fbbf24" : "#fbbf24" }
            GradientStop { position: 1.0; color: root.count > 0 ? "#f2d97706" : "#d97706" }
        }
        border.color: "#fde68a"
        border.width: 1

        // Subtle inner crease line
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.86
            height: 1
            color: "#66ffffff"
        }
    }
}
