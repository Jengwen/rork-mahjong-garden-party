import SwiftUI

nonisolated struct AppTheme: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let primaryColor: ThemeColor
    let secondaryColor: ThemeColor
    let accentColor: ThemeColor
    let backgroundColor: ThemeColor
    let tileBaseColor: ThemeColor
    let tileBorderColor: ThemeColor
    let isLocked: Bool
    let price: String?

    var primary: Color { primaryColor.color }
    var secondary: Color { secondaryColor.color }
    var accent: Color { accentColor.color }
    var background: Color { backgroundColor.color }
    var tileBase: Color { tileBaseColor.color }
    var tileBorder: Color { tileBorderColor.color }
}

nonisolated struct ThemeColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

extension AppTheme {
    static let gardenParty = AppTheme(
        id: "garden_party",
        name: "Garden Party",
        description: "Classic garden elegance with soft pinks and greens",
        primaryColor: ThemeColor(red: 0.85, green: 0.45, blue: 0.55),
        secondaryColor: ThemeColor(red: 0.42, green: 0.65, blue: 0.45),
        accentColor: ThemeColor(red: 0.92, green: 0.72, blue: 0.35),
        backgroundColor: ThemeColor(red: 0.97, green: 0.95, blue: 0.92),
        tileBaseColor: ThemeColor(red: 1.0, green: 0.98, blue: 0.95),
        tileBorderColor: ThemeColor(red: 0.85, green: 0.78, blue: 0.70),
        isLocked: false,
        price: nil
    )

    static let palmBeachPastels = AppTheme(
        id: "palm_beach",
        name: "Palm Beach Pastels",
        description: "Bright pastels inspired by coastal living",
        primaryColor: ThemeColor(red: 0.55, green: 0.82, blue: 0.85),
        secondaryColor: ThemeColor(red: 0.95, green: 0.70, blue: 0.55),
        accentColor: ThemeColor(red: 0.98, green: 0.85, blue: 0.45),
        backgroundColor: ThemeColor(red: 0.96, green: 0.97, blue: 0.98),
        tileBaseColor: ThemeColor(red: 1.0, green: 1.0, blue: 0.98),
        tileBorderColor: ThemeColor(red: 0.75, green: 0.85, blue: 0.88),
        isLocked: true,
        price: "$2.99"
    )

    static let classicGreenbrier = AppTheme(
        id: "greenbrier",
        name: "Classic Greenbrier",
        description: "Timeless elegance in emerald and ivory",
        primaryColor: ThemeColor(red: 0.15, green: 0.50, blue: 0.35),
        secondaryColor: ThemeColor(red: 0.70, green: 0.60, blue: 0.45),
        accentColor: ThemeColor(red: 0.85, green: 0.75, blue: 0.55),
        backgroundColor: ThemeColor(red: 0.95, green: 0.94, blue: 0.91),
        tileBaseColor: ThemeColor(red: 0.98, green: 0.97, blue: 0.93),
        tileBorderColor: ThemeColor(red: 0.25, green: 0.55, blue: 0.40),
        isLocked: true,
        price: "$2.99"
    )

    static let springBlooms = AppTheme(
        id: "spring_blooms",
        name: "Spring Blooms",
        description: "Fresh florals in lavender and rose",
        primaryColor: ThemeColor(red: 0.70, green: 0.55, blue: 0.80),
        secondaryColor: ThemeColor(red: 0.90, green: 0.60, blue: 0.65),
        accentColor: ThemeColor(red: 0.95, green: 0.80, blue: 0.50),
        backgroundColor: ThemeColor(red: 0.97, green: 0.95, blue: 0.98),
        tileBaseColor: ThemeColor(red: 1.0, green: 0.98, blue: 1.0),
        tileBorderColor: ThemeColor(red: 0.78, green: 0.65, blue: 0.85),
        isLocked: true,
        price: "$4.99"
    )

    static let allThemes: [AppTheme] = [gardenParty, palmBeachPastels, classicGreenbrier, springBlooms]
}
