import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    height: Math.round(52 * Theme.scaleFactor)
    color: Theme.bgCard
    border.color: Theme.borderDim
    border.width: 1

    readonly property var chosen: backend.picker.selectedPaths
    readonly property string displayChosen: chosen.length > 0 ? chosen.join(", ") : (backend.picker.mode === "folder" ? backend.currentPath : "No item selected")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Text {
            text: backend.picker.mode === "folder" ? "Selected Folder:" : "Selected File(s):"
            color: Theme.textSecondary
            font.bold: true
            font.pixelSize: Theme.fontSizeNormal
        }

        Rectangle {
            Layout.fillWidth: true
            height: Math.round(32 * Theme.scaleFactor)
            color: Theme.bgSurface
            radius: Theme.radiusSmall
            border.color: Theme.borderDim

            Text {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: Text.AlignVCenter
                text: root.displayChosen
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
            }
        }

        // Filter info pill
        Rectangle {
            visible: backend.picker.filterDisplay !== ""
            implicitWidth: filterTxt.implicitWidth + 16
            height: Math.round(28 * Theme.scaleFactor)
            color: Theme.bgBase
            radius: Theme.radiusSmall
            border.color: Theme.borderDim

            Text {
                id: filterTxt
                anchors.centerIn: parent
                text: backend.picker.filterDisplay
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Button {
            text: backend.picker.mode === "folder" ? "Select Current Folder" : "Select"
            enabled: root.chosen.length > 0 || backend.picker.mode === "folder"
            contentItem: Text {
                text: parent.text
                color: parent.enabled ? Theme.textPrimary : Theme.textTertiary
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: parent.enabled ? (parent.hovered ? Theme.accentHover : Theme.accent) : Theme.bgHover
                radius: Theme.radiusSmall
            }
            onClicked: backend.confirmPickerSelection()
        }

        Button {
            text: "Cancel"
            contentItem: Text {
                text: parent.text
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: parent.hovered ? Theme.bgHover : "transparent"
                border.color: Theme.borderDim
                radius: Theme.radiusSmall
            }
            onClicked: backend.cancelPicker()
        }
    }
}
