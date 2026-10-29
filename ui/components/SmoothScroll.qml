import QtQuick
import ".."

Item {
    id: root
    anchors.fill: parent
    z: 99

    property Flickable target: parent
    property int orientation: Qt.Vertical
    property real baseStep: 170.0
    property bool enableCtrlZoom: false

    readonly property bool isHoriz: orientation === Qt.Horizontal
    property real targetPos: 0.0

    function stopScroll() {
        if (scrollAnim.running) {
            scrollAnim.stop()
        }
        if (root.target) {
            root.targetPos = root.isHoriz ? root.target.contentX : root.target.contentY
        }
    }

    Connections {
        target: root.target
        function onMovingChanged() {
            if (root.target && root.target.moving) {
                if (scrollAnim.running) scrollAnim.stop()
                root.targetPos = root.isHoriz ? root.target.contentX : root.target.contentY
            }
        }
        function onContentYChanged() {
            if (!root.isHoriz && root.target && !scrollAnim.running) {
                root.targetPos = root.target.contentY
            }
        }
        function onContentXChanged() {
            if (root.isHoriz && root.target && !scrollAnim.running) {
                root.targetPos = root.target.contentX
            }
        }
        function onContentHeightChanged() {
            if (!root.isHoriz && root.target) {
                var maxPos = Math.max(0.0, root.target.contentHeight - root.target.height)
                if (root.targetPos > maxPos) {
                    root.targetPos = maxPos
                }
            }
        }
        function onContentWidthChanged() {
            if (root.isHoriz && root.target) {
                var maxPos = Math.max(0.0, root.target.contentWidth - root.target.width)
                if (root.targetPos > maxPos) {
                    root.targetPos = maxPos
                }
            }
        }
    }

    Connections {
        target: typeof backend !== "undefined" ? backend : null
        function onCurrentPathChanged() {
            root.stopScroll()
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: root.target
        property: root.isHoriz ? "contentX" : "contentY"
        to: root.targetPos
        duration: 145
        easing.type: Easing.OutCubic
    }

    WheelHandler {
        id: wheelHandler
        target: null
        orientation: root.orientation
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false

        onWheel: function(event) {
            if (!root.target || !root.target.visible) return

            if (event.modifiers & Qt.ControlModifier) {
                if (root.enableCtrlZoom && typeof backend !== "undefined" && backend) {
                    var dyZoom = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                    if (dyZoom !== 0) {
                        if (backend.viewMode === "grid") {
                            var curCols = backend.gridColumns > 0 ? backend.gridColumns : 4
                            var nextCols = dyZoom > 0 ? Math.max(2, curCols - 1) : Math.min(8, curCols + 1)
                            backend.setGridColumns(nextCols)
                        } else {
                            var deltaScale = dyZoom > 0 ? 0.05 : -0.05
                            backend.setUiScaleFactor(backend.uiScaleFactor + deltaScale)
                        }
                        event.accepted = true
                    }
                }
                return
            }

            var propSize = root.isHoriz ? root.target.contentWidth : root.target.contentHeight
            var viewDim = root.isHoriz ? root.target.width : root.target.height
            var maxPos = Math.max(0.0, propSize - viewDim)
            if (maxPos <= 0.5) return

            var curPos = root.isHoriz ? root.target.contentX : root.target.contentY
            var pxDelta = root.isHoriz ? event.pixelDelta.x : event.pixelDelta.y
            var angDelta = root.isHoriz
                           ? (event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y)
                           : (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x)

            var mult = (typeof backend !== "undefined" && backend && backend.scrollSpeedMultiplier) ? backend.scrollSpeedMultiplier : 1.25
            var scale = Theme.scaleFactor

            // High-precision touchpad pixelDelta: apply directly without artificial lag
            if (pxDelta !== 0 && Math.abs(pxDelta) < 120 && event.phase !== Qt.NoScrollPhase) {
                scrollAnim.stop()
                var directPos = Math.max(0.0, Math.min(maxPos, curPos - pxDelta * mult))
                if (root.isHoriz) {
                    root.target.contentX = directPos
                } else {
                    root.target.contentY = directPos
                }
                root.targetPos = directPos
                event.accepted = true
                return
            }

            if (angDelta === 0) return

            var notches = angDelta / 120.0
            var step = notches * (root.baseStep * scale * mult)
            var baseTarget = scrollAnim.running ? root.targetPos : curPos
            var newTarget = Math.max(0.0, Math.min(maxPos, baseTarget - step))

            if (Math.abs(newTarget - curPos) < 0.5) return

            root.targetPos = newTarget
            scrollAnim.from = curPos
            scrollAnim.to = newTarget
            scrollAnim.restart()
            event.accepted = true
        }
    }
}
