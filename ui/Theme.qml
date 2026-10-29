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

    // Dedicated Media Hub Theme Palette (Only affects Media Hub / --mh)
    readonly property string mhThemeId: (typeof backend !== "undefined" && backend && backend.mediaHubTheme) ? backend.mediaHubTheme : "obsidian"
    readonly property color mhBgBase: {
        switch (mhThemeId) {
            case "oled": return "#000000"
            case "crimson": return "#12080b"
            case "violet": return "#0d0917"
            case "emerald": return "#071310"
            case "ocean": return "#071018"
            case "match_app": return bgBase
            default: return "#0b0d13"
        }
    }
    readonly property color mhBgCard: {
        switch (mhThemeId) {
            case "oled": return "#0f0f12"
            case "crimson": return "#241117"
            case "violet": return "#1c1430"
            case "emerald": return "#102620"
            case "ocean": return "#102232"
            case "match_app": return bgCard
            default: return "#161924"
        }
    }
    readonly property color mhAccent: {
        switch (mhThemeId) {
            case "oled": return "#38bdf8"
            case "crimson": return "#f43f5e"
            case "violet": return "#a855f7"
            case "emerald": return "#10b981"
            case "ocean": return "#0ea5e9"
            case "match_app": return accent
            default: return "#6366f1"
        }
    }
}
