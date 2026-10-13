import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
import "components"

ApplicationWindow {
    id: root
    width: 1680
    height: 980
    minimumWidth: 900
    minimumHeight: 550
    visible: true
    title: backend.picker.isActive ? backend.picker.title : "Find"
    color: Theme.bgBase

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        propagateComposedEvents: true

        onClicked: function(mouse) {
            if (mouse.button === Qt.BackButton) {
                if (backend.canGoBack) {
                    backend.goBack()
                    mouse.accepted = true
                }
            } else if (mouse.button === Qt.ForwardButton) {
                if (backend.canGoForward) {
                    backend.goForward()
                    mouse.accepted = true
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Navigation Bar
        Rectangle {
            Layout.fillWidth: true
            height: Math.round(54 * Theme.scaleFactor)
            color: Theme.bgBase

            AddressBar {
                anchors.fill: parent
                anchors.leftMargin: Math.round(14 * Theme.scaleFactor)
                anchors.rightMargin: Math.round(14 * Theme.scaleFactor)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.borderDim
        }

        // Main Body: Fixed Sturdy Sidebar | File Content | Preview
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            handle: Rectangle {
                implicitWidth: Math.round(8 * Theme.scaleFactor)
                color: "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: parent.height
                    color: SplitHandle.hovered || SplitHandle.pressed ? Theme.accent : Theme.borderDim
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SplitHCursor
                    enabled: false
                }
            }

            Sidebar {
                SplitView.preferredWidth: Math.round(240 * Theme.scaleFactor)
                SplitView.minimumWidth: Math.round(180 * Theme.scaleFactor)
                SplitView.maximumWidth: Math.round(360 * Theme.scaleFactor)
            }

            FileView {
                SplitView.fillWidth: true
            }

            PreviewPanel {
                SplitView.preferredWidth: Math.round(290 * Theme.scaleFactor)
                SplitView.minimumWidth: Math.round(220 * Theme.scaleFactor)
                SplitView.maximumWidth: Math.round(480 * Theme.scaleFactor)
            }
        }

        // Unified Bottom Bar: Visible Only When Picker Is Active
        PickerBottomBar {
            Layout.fillWidth: true
            visible: backend.picker.isActive
        }
    }
}
