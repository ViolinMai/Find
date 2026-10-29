import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    height: Math.round(54 * Theme.scaleFactor)
    color: Theme.bgCard
    border.color: Theme.borderDim
    border.width: 1

    readonly property bool isSaveMode: (backend && backend.picker) ? (backend.picker.mode === "save") : false
    readonly property var chosen: (backend && backend.picker) ? backend.picker.selectedPaths : []
    readonly property string displayChosen: chosen.length > 0 ? chosen.join(", ") : ((backend && backend.picker && backend.picker.mode === "folder") ? backend.currentPath : "No item selected")

    function tryConfirmPicker() {
        if (!backend) return
        if (root.isSaveMode) {
            var fn = saveNameInput.text.trim()
            if (fn === "") return
            var targetFull = backend.currentPath + "/" + fn
            var props = backend.getItemProperties(targetFull)
            if (props && props.path) {
                saveOverwriteDialog.open()
                return
            }
        }
        backend.confirmPickerSelection()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Text {
            text: root.isSaveMode
                  ? "Save As:"
                  : ((backend && backend.picker && backend.picker.mode === "folder") ? "Selected Folder:" : "Selected File(s):")
            color: Theme.textSecondary
            font.bold: true
            font.pixelSize: Theme.fontSizeNormal
        }

        // Editable filename input when in Save mode (e.g. Firefox download dialog)
        TextField {
            id: saveNameInput
            visible: root.isSaveMode
            Layout.fillWidth: true
            height: Math.round(32 * Theme.scaleFactor)
            text: (backend && backend.picker) ? backend.picker.saveFilename : ""
            placeholderText: "Enter filename to save..."
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeNormal
            selectByMouse: true
            onTextChanged: {
                if (backend && backend.picker && backend.picker.saveFilename !== text) {
                    backend.picker.setSaveFilename(text)
                }
            }
            onAccepted: root.tryConfirmPicker()
            background: Rectangle {
                color: Theme.bgSurface
                radius: Theme.radiusSmall
                border.color: saveNameInput.activeFocus ? Theme.accent : Theme.borderDim
                border.width: 1
            }
        }

        Rectangle {
            visible: !root.isSaveMode
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
            visible: (backend && backend.picker) ? (backend.picker.filterDisplay !== "") : false
            implicitWidth: filterTxt.implicitWidth + 16
            height: Math.round(28 * Theme.scaleFactor)
            color: Theme.bgBase
            radius: Theme.radiusSmall
            border.color: Theme.borderDim

            Text {
                id: filterTxt
                anchors.centerIn: parent
                text: (backend && backend.picker) ? backend.picker.filterDisplay : ""
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Button {
            text: root.isSaveMode
                  ? "💾 Save Here"
                  : ((backend && backend.picker && backend.picker.mode === "folder") ? "Select Current Folder" : "Select")
            enabled: root.isSaveMode
                     ? (saveNameInput.text.trim() !== "")
                     : (root.chosen.length > 0 || (backend && backend.picker && backend.picker.mode === "folder"))
            contentItem: Text {
                text: parent.text
                color: parent.enabled ? "#ffffff" : Theme.textTertiary
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitWidth: Math.round(115 * Theme.scaleFactor)
                implicitHeight: Math.round(32 * Theme.scaleFactor)
                color: parent.enabled ? (parent.hovered ? Theme.accentHover : Theme.accent) : Theme.bgHover
                radius: Theme.radiusSmall
            }
            onClicked: root.tryConfirmPicker()
        }

        Dialog {
            id: saveOverwriteDialog
            title: "Confirm Overwrite"
            modal: true
            anchors.centerIn: Overlay.overlay
            width: Math.round(380 * Theme.scaleFactor)

            background: Rectangle {
                color: Theme.bgSurface
                border.color: "#f59e0b"
                border.width: 1
                radius: Theme.radiusLarge
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: "A file named \"" + saveNameInput.text.trim() + "\" already exists in this folder.\n\nDo you want to replace it?"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Cancel"
                        onClicked: saveOverwriteDialog.close()
                    }
                    Button {
                        text: "Replace"
                        onClicked: {
                            saveOverwriteDialog.close()
                            if (backend) backend.confirmPickerSelection()
                        }
                    }
                }
            }
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
                implicitWidth: Math.round(78 * Theme.scaleFactor)
                implicitHeight: Math.round(32 * Theme.scaleFactor)
                color: parent.hovered ? Theme.bgHover : "transparent"
                border.color: Theme.borderDim
                radius: Theme.radiusSmall
            }
            onClicked: backend.cancelPicker()
        }
    }
}
