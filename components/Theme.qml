pragma Singleton
import QtQuick

QtObject {
    // Nutsty Dark Modern Theme Colors
    readonly property color bgApp: "#121212"          // Deep black window background
    readonly property color bgCard: "#181818"         // Card background
    readonly property color bgCardHover: "#282828"    // Card hover state
    readonly property color bgElevated: "#242424"     // Floating cards / menus
    readonly property color bgHighlight: "#2a2a2a"    // Active row highlight
    
    // Borders & Dividers
    readonly property color border: "#282828"         // Subtle hairline border
    readonly property color divider: "#1f1f1f"        // Hairline divider

    // Typography Colors
    readonly property color textPrimary: "#ffffff"    // 100% white bold text
    readonly property color textSecondary: "#b3b3b3"  // Muted 70% gray subtitle
    readonly property color textMuted: "#727272"      // Dim 45% gray icons/counters

    // Brand Accents
    readonly property color accentGreen: "#deb06c"    // Warm dynamic wallpaper tone (Zero hardcoded green)
    readonly property color accentGreenHover: "#eed08c"
    readonly property color accent: accentGreen       // Primary accent alias
    readonly property color accentPill: "#ffffff"
    readonly property color accentPillText: "#000000"

    // Typography Family
    readonly property string fontFamily: "Inter, SF Pro Display, -apple-system, sans-serif"

    // Spacing and Radii (Concentric: R_inner = R_outer - Padding)
    readonly property int radiusApp: 24
    readonly property int radiusCard: 8
    readonly property int radiusPill: 16
    readonly property int radiusSm: 4

    // Contrast Utility
    function isColorDark(c) {
        if (!c) return true;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.55;
    }
}
