import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

MenuItem {
    id: menuItem

    property string iconGlyph: ""
    property string shortcutText: ""
    property bool isDanger: false

    implicitWidth: Math.max(Math.round(225 * Theme.scaleFactor), rowContent.implicitWidth + Math.round(26 * Theme.scaleFactor))
    implicitHeight: visible ? Math.round(33 * Theme.scaleFactor) : 0
    height: visible ? implicitHeight : 0
    padding: 0

    readonly property bool isHighlighted: (itemHover.hovered || (menuItem.subMenu && menuItem.subMenu.visible)) && menuItem.enabled

    HoverHandler {
        id: itemHover
        onHoveredChanged: {
            if (hovered && menuItem.menu) {
                for (var i = 0; i < menuItem.menu.count; ++i) {
                    if (menuItem.menu.itemAt(i) === menuItem) {
                        menuItem.menu.currentIndex = i
                        break
                    }
                }
            } else if (!hovered && menuItem.menu && menuItem.highlighted) {
                if (!menuItem.subMenu || !menuItem.subMenu.visible) {
                    menuItem.menu.currentIndex = -1
                }
            }
        }
    }

    arrow: Item {
        width: 0
        height: 0
        visible: false
    }

    indicator: Item {
        width: 0
        height: 0
        visible: false
    }

    contentItem: RowLayout {
        id: rowContent
        anchors.fill: parent
        anchors.leftMargin: Math.round(10 * Theme.scaleFactor)
        anchors.rightMargin: Math.round(10 * Theme.scaleFactor)
        spacing: Math.round(8 * Theme.scaleFactor)

        // Uniform Fixed-Width Icon / Checkmark Column
        Item {
            Layout.preferredWidth: Math.round(22 * Theme.scaleFactor)
            Layout.preferredHeight: Math.round(22 * Theme.scaleFactor)
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text: menuItem.checkable ? (menuItem.checked ? "✔" : "") : menuItem.iconGlyph
                color: menuItem.checkable ? (menuItem.isHighlighted ? "#ffffff" : Theme.accent) : "#ffffff"
                font.pixelSize: Theme.fontSizeNormal
                font.bold: menuItem.checkable
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Uniform Main Label Column
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: menuItem.text
            color: !menuItem.enabled
                   ? "#686873"
                   : (menuItem.isDanger
                      ? (menuItem.isHighlighted ? "#ffffff" : "#f87171")
                      : "#f8fafc")
            font.pixelSize: Theme.fontSizeNormal
            font.bold: menuItem.font.bold
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        // Uniform Shortcut Pill
        Rectangle {
            visible: menuItem.shortcutText !== "" && !menuItem.subMenu
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: scTxt.implicitWidth + Math.round(10 * Theme.scaleFactor)
            implicitHeight: Math.round(19 * Theme.scaleFactor)
            radius: Theme.radiusSmall
            color: menuItem.isHighlighted ? "#30ffffff" : "#18181e"
            border.color: menuItem.isHighlighted ? "#45ffffff" : "#32323d"
            border.width: 1

            Text {
                id: scTxt
                anchors.centerIn: parent
                text: menuItem.shortcutText
                color: menuItem.isHighlighted ? "#ffffff" : "#9e9ea9"
                font.pixelSize: Math.round(9.5 * Theme.scaleFactor)
                font.bold: true
            }
        }

        // Uniform Submenu Arrow
        Text {
            visible: menuItem.subMenu !== null
            Layout.alignment: Qt.AlignVCenter
            text: "›"
            color: menuItem.isHighlighted ? "#ffffff" : "#a1a1aa"
            font.pixelSize: Theme.fontSizeTitle
            font.bold: true
        }
    }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: menuItem.isHighlighted
               ? (menuItem.isDanger ? "#dc2626" : Theme.accent)
               : "transparent"
    }
}
