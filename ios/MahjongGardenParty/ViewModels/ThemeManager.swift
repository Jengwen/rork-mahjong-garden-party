import SwiftUI

@Observable
@MainActor
class ThemeManager {
    var currentTheme: AppTheme = .gardenParty
    var selectedThemeId: String = "garden_party" {
        didSet {
            if let theme = AppTheme.allThemes.first(where: { $0.id == selectedThemeId }) {
                currentTheme = theme
            }
        }
    }

    var meshGradientColors: [Color] {
        [
            currentTheme.primary.opacity(0.3),
            currentTheme.background,
            currentTheme.secondary.opacity(0.2),
            currentTheme.background,
            currentTheme.accent.opacity(0.15),
            currentTheme.background,
            currentTheme.primary.opacity(0.1),
            currentTheme.secondary.opacity(0.15),
            currentTheme.background,
        ]
    }
}
