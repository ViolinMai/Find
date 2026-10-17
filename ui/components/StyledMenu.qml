import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Menu {
    id: control
    property string iconGlyph: ""

    topPadding: Math.round(6 * Theme.scaleFactor)
    bottomPadding: Math.round(6 * Theme.scaleFactor)
    leftPadding: Math.round(6 * Theme.scaleFactor)
    rightPadding: Math.round(6 * Theme.scaleFactor)

    onOpened: {
        control.currentIndex = -1
    }

    onClosed: {
        control.currentIndex = -1
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 100; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 100; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 75; easing.type: Easing.InCubic }
    }

    contentItem: ListView {
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: false
        clip: true
        currentIndex: control.currentIndex

        HoverHandler {
            onHoveredChanged: {
                if (!hovered) {
                    control.currentIndex = -1
                }
            }
        }
    }

    background: Rectangle {
        implicitWidth: Math.round(235 * Theme.scaleFactor)
        color: "#1e1e24"
        border.color: "#3e3e4a"
        border.width: 1
        radius: Theme.radiusLarge

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Theme.radiusLarge - 1
            color: "transparent"
            border.color: "#16ffffff"
            border.width: 1
        }
    }

    delegate: StyledMenuItem {
        iconGlyph: subMenu && subMenu.iconGlyph !== undefined ? subMenu.iconGlyph : ""
    }
}
