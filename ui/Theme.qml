pragma Singleton
import QtQuick

QtObject {
    // Scaling Factor
    readonly property real scaleFactor: 1.5

    // Colors
    readonly property color bgBase: "#1c1c1f"
    readonly property color bgSidebar: "#18181b"
    readonly property color bgSurface: "#232327"
    readonly property color bgCard: "#27272b"
    readonly property color bgHover: "#333338"
    readonly property color bgSelected: "#3a3a42"
    readonly property color borderDim: "#2e2e34"
    readonly property color borderFocus: "#0078d4"

    // Text colors
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: "#9e9ea6"
    readonly property color textTertiary: "#6e6e76"
    readonly property color textDanger: "#ef4444"

    // Accents
    readonly property color accent: "#0078d4"
    readonly property color accentHover: "#1984d8"

    // Metrics (Scaled 1.5x)
    readonly property int radiusSmall: Math.round(4 * scaleFactor)
    readonly property int radiusMedium: Math.round(6 * scaleFactor)
    readonly property int radiusLarge: Math.round(8 * scaleFactor)

    // Fonts (Scaled 1.5x)
    readonly property int fontSizeSmall: Math.round(11 * scaleFactor)
    readonly property int fontSizeNormal: Math.round(13 * scaleFactor)
    readonly property int fontSizeMedium: Math.round(14 * scaleFactor)
    readonly property int fontSizeTitle: Math.round(15 * scaleFactor)
    readonly property int fontSizeIcon: Math.round(18 * scaleFactor)
}
