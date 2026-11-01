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

    onAboutToShow: {
        control.currentIndex = -1
    }

    onOpened: {
        control.currentIndex = -1
    }

    onClosed: {
        control.currentIndex = -1
    }

    function closeOtherSubMenus(activeItem) {
        for (var i = 0; i < control.count; ++i) {
            var it = control.itemAt(i)
            if (it && it !== activeItem && it.subMenu && it.subMenu.visible) {
                it.subMenu.close()
            }
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 90; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 65; easing.type: Easing.InCubic }
    }

    contentItem: ListView {
        implicitHeight: Math.min(contentHeight, Overlay.overlay ? Math.max(220, Overlay.overlay.height - 48) : 520)
        model: control.contentModel
        interactive: contentHeight > implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        currentIndex: -1
        highlightFollowsCurrentItem: false

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
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
