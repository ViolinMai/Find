pragma Singleton
import QtQuick

QtObject {
    readonly property real scaleFactor: (typeof backend !== "undefined" && backend && backend.uiScaleFactor) ? backend.uiScaleFactor : 1.35

    // Base background with clean, high translucency
    readonly property color bgBase: (typeof backend !== "undefined" && backend && backend.transparentBlur) ? "#a8131317" : "#18181c"
    readonly property color bgSidebar: (typeof backend !== "undefined" && backend && backend.transparentBlur) ? "#b4101014" : "#141418"

    // Opaque and solid elements
    readonly property color bgSurface: "#222228"
    readonly property color bgCard: "#26262d"
    readonly property color bgHover: "#32323b"
    readonly property color bgSelected: "#383844"
    readonly property color borderDim: "#34343e"
    readonly property color borderFocus: accent

    // Text colors (Full opacity)
    readonly property color textPrimary: "#f8fafc"
    readonly property color textSecondary: "#a1a1aa"
    readonly property color textTertiary: "#71717a"
    readonly property color textDanger: "#f87171"

    // Accents (Dynamically bound to user's chosen theme color)
    readonly property color accent: (typeof backend !== "undefined" && backend && backend.accentColor) ? backend.accentColor : "#0078d4"
    readonly property color accentHover: (typeof backend !== "undefined" && backend && backend.accentHoverColor) ? backend.accentHoverColor : "#1a88e0"

    // Metrics
    readonly property int radiusSmall: Math.round(4 * scaleFactor)
    readonly property int radiusMedium: Math.round(6 * scaleFactor)
    readonly property int radiusLarge: Math.round(9 * scaleFactor)

    // Fonts
    readonly property int fontSizeSmall: Math.round(11 * scaleFactor)
    readonly property int fontSizeNormal: Math.round(12.5 * scaleFactor)
    readonly property int fontSizeMedium: Math.round(13.5 * scaleFactor)
    readonly property int fontSizeTitle: Math.round(15 * scaleFactor)
    readonly property int fontSizeIcon: Math.round(17 * scaleFactor)
}
