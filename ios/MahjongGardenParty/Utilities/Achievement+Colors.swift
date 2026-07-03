import SwiftUI

extension Achievement {
    /// Primary tint for an earned achievement badge. Each pairing stays inside the
    /// app's Garden Party palette — warm rose, sage, champagne gold, terracotta,
    /// lavender — so the trophy wall reads as a cohesive collection rather than
    /// a generic rainbow.
    var badgeColors: [Color] {
        switch id {
        case "first_win":
            // Champagne gold → warm honey (matches accent gold)
            return [Color(red: 0.95, green: 0.78, blue: 0.42), Color(red: 0.85, green: 0.58, blue: 0.25)]
        case "win_streak_3":
            // Rose → terracotta (matches primary rose)
            return [Color(red: 0.90, green: 0.58, blue: 0.62), Color(red: 0.78, green: 0.40, blue: 0.45)]
        case "win_streak_5":
            // Blush → dusty mauve
            return [Color(red: 0.92, green: 0.65, blue: 0.72), Color(red: 0.70, green: 0.45, blue: 0.62)]
        case "games_10":
            // Sage → deeper garden green (matches secondary)
            return [Color(red: 0.55, green: 0.75, blue: 0.55), Color(red: 0.32, green: 0.58, blue: 0.42)]
        case "games_50":
            // Emerald → forest (greenbrier-leaning)
            return [Color(red: 0.42, green: 0.68, blue: 0.50), Color(red: 0.18, green: 0.48, blue: 0.35)]
        case "first_mahjong":
            // Sunlit gold → rose (celebration accent)
            return [Color(red: 0.96, green: 0.82, blue: 0.45), Color(red: 0.88, green: 0.52, blue: 0.50)]
        case "host_party":
            // Coral rose → champagne (party confetti, palette-tuned)
            return [Color(red: 0.92, green: 0.55, blue: 0.58), Color(red: 0.94, green: 0.78, blue: 0.45)]
        case "collector":
            // Lavender → dusty plum (spring blooms accent)
            return [Color(red: 0.72, green: 0.60, blue: 0.82), Color(red: 0.50, green: 0.42, blue: 0.68)]
        case "wins_10":
            // Bronze rose (warm metallic in palette)
            return [Color(red: 0.82, green: 0.62, blue: 0.45), Color(red: 0.58, green: 0.38, blue: 0.28)]
        case "wins_25":
            // Crown gold → rose-gold (regal, palette-tuned)
            return [Color(red: 0.95, green: 0.80, blue: 0.42), Color(red: 0.82, green: 0.48, blue: 0.40)]
        default:
            return [Color.accentColor, Color.accentColor.opacity(0.7)]
        }
    }

    var badgeGradient: LinearGradient {
        LinearGradient(
            colors: badgeColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var badgePrimaryColor: Color {
        badgeColors.first ?? .accentColor
    }
}
