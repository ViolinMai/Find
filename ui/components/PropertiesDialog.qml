import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Dialog {
    id: root
    title: "Properties & Permissions"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Overlay.overlay ? Math.min(Math.round(520 * Theme.scaleFactor), Overlay.overlay.width - 24) : 540
    padding: 0

    property var propsData: ({})
    property string targetPath: ""

    property bool uR: true
    property bool uW: true
    property bool uX: false
    property bool gR: true
    property bool gW: false
    property bool gX: false
    property bool oR: true
    property bool oW: false
    property bool oX: false

    readonly property int computedMode: {
        var m = 0
        if (uR) m |= 0o400
        if (uW) m |= 0o200
        if (uX) m |= 0o100
        if (gR) m |= 0o040
        if (gW) m |= 0o020
        if (gX) m |= 0o010
        if (oR) m |= 0o004
        if (oW) m |= 0o002
        if (oX) m |= 0o001
        return m
    }

    readonly property string computedOctalStr: "0" + computedMode.toString(8).padStart(3, "0")

    function openForPath(pathStr) {
        if (!backend) return
        var info = backend.getItemProperties(pathStr)
        if (!info || !info.path) return
        targetPath = info.path
        propsData = info
        uR = Boolean(info.u_r)
        uW = Boolean(info.u_w)
        uX = Boolean(info.u_x)
        gR = Boolean(info.g_r)
        gW = Boolean(info.g_w)
        gX = Boolean(info.g_x)
        oR = Boolean(info.o_r)
        oW = Boolean(info.o_w)
        oX = Boolean(info.o_x)
        root.open()
    }

    background: Rectangle {
        color: Theme.bgSurface
        border.color: Theme.accent
        border.width: 1
        radius: Theme.radiusLarge
        clip: true
    }

    header: Rectangle {
        height: Math.round(46 * Theme.scaleFactor)
        color: "#16161b"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 10

            Text {
                text: (root.propsData.icon || "📄") + "  Properties — " + (root.propsData.name || "")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Rectangle {
                width: Math.round(26 * Theme.scaleFactor)
                height: Math.round(26 * Theme.scaleFactor)
                radius: Theme.radiusSmall
                color: closePropMouse.containsMouse ? "#35f87171" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: closePropMouse.containsMouse ? Theme.textDanger : Theme.textSecondary
                    font.bold: true
                }
                MouseArea {
                    id: closePropMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // General Metadata Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: metaGrid.implicitHeight + 20
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderDim

            GridLayout {
                id: metaGrid
                anchors.fill: parent
                anchors.margins: 10
                columns: 2
                rowSpacing: 6
                columnSpacing: 12

                Text { text: "Type:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: root.propsData.type || "-"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight }

                Text { text: "Location:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: root.propsData.parent_dir || "-"; color: Theme.textSecondary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft; elide: Text.ElideMiddle }

                Text { visible: Boolean(root.propsData.is_symlink); text: "Link Target:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { visible: Boolean(root.propsData.is_symlink); text: root.propsData.symlink_target || ""; color: "#38bdf8"; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft; elide: Text.ElideMiddle }

                Text { text: "Size:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: root.propsData.size || "-"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeSmall; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft }

                Text { text: "Modified:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: root.propsData.modified || "-"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft }

                Text { text: "Created:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: root.propsData.created || "-"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft }

                Text { text: "Owner / Group:"; color: Theme.textTertiary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Text { text: (root.propsData.owner || "-") + " : " + (root.propsData.group || "-"); color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft }
            }
        }

        // Permissions Matrix Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: permCol.implicitHeight + 20
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderDim

            ColumnLayout {
                id: permCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "🔒 UNIX Permissions (chmod)"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        implicitWidth: octTxt.implicitWidth + 12
                        implicitHeight: Math.round(22 * Theme.scaleFactor)
                        radius: Theme.radiusSmall
                        color: Theme.bgSurface
                        border.color: Theme.accent
                        Text {
                            id: octTxt
                            anchors.centerIn: parent
                            text: root.computedOctalStr
                            color: Theme.accent
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }
                }

                component PermPill: Rectangle {
                    property string label: ""
                    property bool activeBit: false
                    signal toggledBit()
                    Layout.fillWidth: true
                    height: Math.round(26 * Theme.scaleFactor)
                    radius: Theme.radiusSmall
                    color: activeBit ? Theme.accent : Theme.bgSurface
                    border.color: activeBit ? Theme.accentHover : Theme.borderDim
                    Text {
                        anchors.centerIn: parent
                        text: parent.label
                        color: parent.activeBit ? "#ffffff" : Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: parent.activeBit
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: parent.toggledBit()
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    rowSpacing: 6
                    columnSpacing: 6

                    Text { text: "Owner:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    PermPill { label: "Read (r)"; activeBit: root.uR; onToggledBit: root.uR = !root.uR }
                    PermPill { label: "Write (w)"; activeBit: root.uW; onToggledBit: root.uW = !root.uW }
                    PermPill { label: "Exec (x)"; activeBit: root.uX; onToggledBit: root.uX = !root.uX }

                    Text { text: "Group:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    PermPill { label: "Read (r)"; activeBit: root.gR; onToggledBit: root.gR = !root.gR }
                    PermPill { label: "Write (w)"; activeBit: root.gW; onToggledBit: root.gW = !root.gW }
                    PermPill { label: "Exec (x)"; activeBit: root.gX; onToggledBit: root.gX = !root.gX }

                    Text { text: "Others:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    PermPill { label: "Read (r)"; activeBit: root.oR; onToggledBit: root.oR = !root.oR }
                    PermPill { label: "Write (w)"; activeBit: root.oW; onToggledBit: root.oW = !root.oW }
                    PermPill { label: "Exec (x)"; activeBit: root.oX; onToggledBit: root.oX = !root.oX }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "📋 Copy Full Path"
                onClicked: if (backend) backend.copyToClipboard(root.targetPath)
                contentItem: Text {
                    text: parent.text
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(125 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : Theme.bgCard
                    border.color: Theme.borderDim
                    radius: Theme.radiusSmall
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "Close"
                onClicked: root.close()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(75 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.bgHover : "transparent"
                    border.color: Theme.borderDim
                    radius: Theme.radiusSmall
                }
            }

            Button {
                text: "💾 Apply Permissions"
                onClicked: {
                    if (backend && backend.setItemPermissions(root.targetPath, root.computedMode)) {
                        root.close()
                    }
                }
                contentItem: Text {
                    text: parent.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                background: Rectangle {
                    implicitWidth: Math.round(145 * Theme.scaleFactor)
                    implicitHeight: Math.round(32 * Theme.scaleFactor)
                    color: parent.hovered ? Theme.accentHover : Theme.accent
                    radius: Theme.radiusSmall
                }
            }
        }
    }
}
