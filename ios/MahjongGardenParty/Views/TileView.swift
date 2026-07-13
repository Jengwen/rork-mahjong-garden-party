import SwiftUI

struct TileView: View {
    @Environment(ThemeManager.self) private var themeManager
    let tile: MahjongTile
    var isSelected: Bool = false
    var size: TileSize = .medium
    var isFaceDown: Bool = false
    var isCharlestonSelected: Bool = false

    var body: some View {
        ZStack {
            if isFaceDown {
                faceDownTile
            } else {
                faceUpTile
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(
            color: (isSelected || isCharlestonSelected)
                ? themeManager.currentTheme.primary.opacity(0.4)
                : .black.opacity(0.08),
            radius: (isSelected || isCharlestonSelected) ? 6 : 3,
            y: (isSelected || isCharlestonSelected) ? -2 : 2
        )
        .offset(y: (isSelected || isCharlestonSelected) ? -8 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCharlestonSelected)
    }

    private var isWind: Bool {
        tile.suit == .wind
    }

    private var windImageName: String? {
        guard tile.suit == .wind else { return nil }
        let names = ["east_wind", "south_wind", "west_wind", "north_wind"]
        return names[min(tile.value - 1, 3)]
    }

    private var isJoker: Bool {
        tile.suit == .joker
    }

    private var isOneBam: Bool {
        tile.suit == .bamboo && tile.value == 1
    }

    private var isRedDragon: Bool {
        tile.suit == .dragon && tile.value == 1
    }

    private var isGreenDragon: Bool {
        tile.suit == .dragon && tile.value == 2
    }

    private var isWhiteDragon: Bool {
        tile.suit == .dragon && tile.value == 3
    }

    private var isFlower: Bool {
        tile.suit == .flower
    }

    private var isDot: Bool {
        tile.suit == .dot
    }

    private var isBamboo: Bool {
        tile.suit == .bamboo && tile.value >= 2
    }

    private var isCharacter: Bool {
        tile.suit == .character
    }

    private let crackColor = Color(red: 0.8, green: 0.235, blue: 0.427)

    private var dotNumberColor: Color {
        Color(red: 0.902, green: 0.663, blue: 0.125)
    }

    private let goldDotColor = Color(red: 230.0/255.0, green: 169.0/255.0, blue: 32.0/255.0)

    private var hasUpperLeftNumber: Bool {
        isOneBam || isBamboo || isCharacter || isDot || isRedDragon || isGreenDragon
    }

    private var upperLeftText: String {
        if isRedDragon { return "R" }
        if isGreenDragon { return "G" }
        return "\(tile.value)"
    }

    private var upperLeftColor: Color {
        if isRedDragon { return tile.suit.color }
        if isGreenDragon { return Color(red: 0.2, green: 0.6, blue: 0.3) }
        if isCharacter { return crackColor }
        if isDot { return goldDotColor }
        return tile.suit.color
    }

    private var whiteDragonDisplaySize: CGFloat {
        switch size {
        case .small: return 40
        case .compact: return 46
        case .medium: return 58
        case .large: return 74
        case .iPadSmall: return 56
        case .iPadCompact: return 66
        case .iPadMedium: return 80
        case .scaled(let w): return 58 * (w / TileSize.referenceWidth)
        }
    }

    private var faceUpTile: some View {
        ZStack {
            if isJoker {
                Image("joker_hat")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.largeGraphicSize, height: size.largeGraphicSize)
            } else if isRedDragon {
                Image("RedDragon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.fullGraphicSize, height: size.fullGraphicSize)
                    .offset(y: size.graphicOffsetY)
            } else if isGreenDragon {
                Image("green_dragon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.largeGraphicSize, height: size.largeGraphicSize)
            } else if isWhiteDragon {
                Image("white_dragon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.largeGraphicSize, height: size.largeGraphicSize)
            } else if isFlower {
                Image("flower_tile")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.largeGraphicSize, height: size.largeGraphicSize)
            } else if isOneBam {
                Image("bam1")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.fullGraphicSize, height: size.fullGraphicSize)
                    .offset(y: size.graphicOffsetY)
            } else if isBamboo {
                Image("bam\(tile.value)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.bambooGraphicWidth, height: size.bambooGraphicHeight)
                    .offset(y: size.bambooGraphicOffsetY)
            } else if isCharacter {
                Image("crack\(tile.value)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.bambooGraphicWidth, height: size.bambooGraphicHeight)
                    .offset(y: size.bambooGraphicOffsetY)
            } else if isDot {
                Image("dot_\(tile.value)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.bambooGraphicWidth, height: size.bambooGraphicHeight)
                    .offset(y: size.bambooGraphicOffsetY)
            } else if isWind, let imageName = windImageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.largeGraphicSize, height: size.largeGraphicSize)
            } else {
                Image(systemName: tile.suit.symbolName)
                    .font(size.iconFont)
                    .foregroundStyle(tile.suit.color)
                Text(tile.shortLabel)
                    .font(size.labelFont)
                    .fontWeight(.bold)
                    .foregroundStyle(tile.suit.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if hasUpperLeftNumber {
                Text(upperLeftText)
                    .font((isBamboo || isCharacter || isDot) ? size.bambooNumberFont : size.upperLeftFont)
                    .fontWeight(.heavy)
                    .foregroundStyle(upperLeftColor)
                    .padding(.leading, size.upperLeftPaddingH)
                    .padding(.top, size.upperLeftPaddingV)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(themeManager.currentTheme.tileBase)
                .overlay(
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(
                    (isSelected || isCharlestonSelected)
                    ? themeManager.currentTheme.primary
                    : themeManager.currentTheme.tileBorder,
                    lineWidth: (isSelected || isCharlestonSelected) ? 2.5 : 1
                )
        )
        .clipShape(.rect(cornerRadius: size.cornerRadius))
    }

    private var faceDownTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(themeManager.currentTheme.primary)

            RoundedRectangle(cornerRadius: max(size.cornerRadius - 3, 2))
                .fill(themeManager.currentTheme.primary.opacity(0.8))
                .padding(3)
                .overlay {
                    Image(systemName: "flower.fill")
                        .font(size.iconFont)
                        .foregroundStyle(.white.opacity(0.3))
                }

            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(themeManager.currentTheme.primary.opacity(0.6), lineWidth: 1)
        }
    }
}

enum TileSize {
    case small, medium, large, compact
    case iPadSmall, iPadCompact, iPadMedium

    /// A freely-scaled tile whose width is decided at layout time from the space
    /// actually available, rather than from a coarse iPhone/iPad switch.
    ///
    /// Every sub-metric (corner radius, icon/label fonts, glyph sizes) is derived
    /// proportionally from `.medium` — the 44pt design reference — so a scaled
    /// tile stays visually consistent with the fixed presets at any size. This is
    /// what lets the Charleston screen fit a 4.7" iPhone SE, a 13" iPad, and
    /// landscape in between without any of them clipping.
    case scaled(width: CGFloat)

    /// The design reference `.scaled` derives from (`.medium`'s width).
    static let referenceWidth: CGFloat = 44
    /// `.medium` is 44x60, so tiles keep a ~1.36 height:width ratio.
    static let aspectRatio: CGFloat = 60.0 / 44.0

    /// Clamped so a scaled tile can never collapse to an untappable sliver, nor grow
    /// absurdly large. The ceiling is above the old `.iPadMedium` (62) because the
    /// Charleston deliberately boosts its tiles past the play-phase rack — see
    /// `CharlestonView.CharlestonLayout.tileBoost`.
    static func fitting(width: CGFloat) -> TileSize {
        .scaled(width: min(max(width, 24), 82))
    }

    var width: CGFloat {
        switch self {
        case .small: return 32
        case .compact: return 36
        case .medium: return 44
        case .large: return 56
        case .iPadSmall: return 44
        case .iPadCompact: return 52
        case .iPadMedium: return 62
        case .scaled(let w): return w.rounded()
        }
    }

    var height: CGFloat {
        switch self {
        case .small: return 42
        case .compact: return 48
        case .medium: return 60
        case .large: return 76
        case .iPadSmall: return 58
        case .iPadCompact: return 68
        case .iPadMedium: return 82
        case .scaled(let w): return (w * TileSize.aspectRatio).rounded()
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 5
        case .compact: return 6
        case .medium: return 7
        case .large: return 9
        case .iPadSmall: return 7
        case .iPadCompact: return 8
        case .iPadMedium: return 9
        case .scaled(let w): return 7 * (w / TileSize.referenceWidth)
        }
    }

    var iconFont: Font {
        switch self {
        case .small: return .system(size: 12)
        case .compact: return .system(size: 14)
        case .medium: return .system(size: 18)
        case .large: return .system(size: 24)
        case .iPadSmall: return .system(size: 18)
        case .iPadCompact: return .system(size: 20)
        case .iPadMedium: return .system(size: 24)
        case .scaled(let w): return .system(size: 18 * (w / TileSize.referenceWidth))
        }
    }

    var labelFont: Font {
        switch self {
        case .small: return .system(size: 8)
        case .compact: return .system(size: 9, weight: .bold)
        case .medium: return .system(size: 11, weight: .bold)
        case .large: return .system(size: 14, weight: .bold)
        case .iPadSmall: return .system(size: 11, weight: .bold)
        case .iPadCompact: return .system(size: 12, weight: .bold)
        case .iPadMedium: return .system(size: 14, weight: .bold)
        case .scaled(let w): return .system(size: 11 * (w / TileSize.referenceWidth), weight: .bold)
        }
    }

    var customImageSize: CGFloat {
        switch self {
        case .small: return 16
        case .compact: return 20
        case .medium: return 26
        case .large: return 34
        case .iPadSmall: return 24
        case .iPadCompact: return 30
        case .iPadMedium: return 36
        case .scaled(let w): return 26 * (w / TileSize.referenceWidth)
        }
    }

    var largeGraphicSize: CGFloat {
        switch self {
        case .small: return 24
        case .compact: return 28
        case .medium: return 36
        case .large: return 48
        case .iPadSmall: return 34
        case .iPadCompact: return 40
        case .iPadMedium: return 50
        case .scaled(let w): return 36 * (w / TileSize.referenceWidth)
        }
    }

    var whiteDragonSize: CGFloat {
        switch self {
        case .small: return 36
        case .compact: return 42
        case .medium: return 52
        case .large: return 68
        case .iPadSmall: return 50
        case .iPadCompact: return 60
        case .iPadMedium: return 72
        case .scaled(let w): return 52 * (w / TileSize.referenceWidth)
        }
    }

    var windImageSize: CGFloat {
        switch self {
        case .small: return 36
        case .compact: return 42
        case .medium: return 52
        case .large: return 68
        case .iPadSmall: return 50
        case .iPadCompact: return 60
        case .iPadMedium: return 72
        case .scaled(let w): return 52 * (w / TileSize.referenceWidth)
        }
    }

    var smallNumberFont: Font {
        switch self {
        case .small: return .system(size: 9, weight: .bold)
        case .compact: return .system(size: 11, weight: .bold)
        case .medium: return .system(size: 13, weight: .bold)
        case .large: return .system(size: 16, weight: .bold)
        case .iPadSmall: return .system(size: 13, weight: .bold)
        case .iPadCompact: return .system(size: 15, weight: .bold)
        case .iPadMedium: return .system(size: 17, weight: .bold)
        case .scaled(let w): return .system(size: 13 * (w / TileSize.referenceWidth), weight: .bold)
        }
    }

    var crackNumberFont: Font {
        switch self {
        case .small: return .system(size: 14, weight: .heavy)
        case .compact: return .system(size: 16, weight: .heavy)
        case .medium: return .system(size: 20, weight: .heavy)
        case .large: return .system(size: 26, weight: .heavy)
        case .iPadSmall: return .system(size: 20, weight: .heavy)
        case .iPadCompact: return .system(size: 24, weight: .heavy)
        case .iPadMedium: return .system(size: 28, weight: .heavy)
        case .scaled(let w): return .system(size: 20 * (w / TileSize.referenceWidth), weight: .heavy)
        }
    }

    var crackCharFont: Font {
        switch self {
        case .small: return .system(size: 10, weight: .bold)
        case .compact: return .system(size: 12, weight: .bold)
        case .medium: return .system(size: 14, weight: .bold)
        case .large: return .system(size: 18, weight: .bold)
        case .iPadSmall: return .system(size: 14, weight: .bold)
        case .iPadCompact: return .system(size: 16, weight: .bold)
        case .iPadMedium: return .system(size: 20, weight: .bold)
        case .scaled(let w): return .system(size: 14 * (w / TileSize.referenceWidth), weight: .bold)
        }
    }

    var fullGraphicSize: CGFloat {
        switch self {
        case .small: return 24
        case .compact: return 28
        case .medium: return 36
        case .large: return 46
        case .iPadSmall: return 34
        case .iPadCompact: return 40
        case .iPadMedium: return 50
        case .scaled(let w): return 36 * (w / TileSize.referenceWidth)
        }
    }

    var graphicOffsetY: CGFloat {
        switch self {
        case .small: return 3
        case .compact: return 3
        case .medium: return 4
        case .large: return 5
        case .iPadSmall: return 4
        case .iPadCompact: return 4
        case .iPadMedium: return 5
        case .scaled(let w): return 4 * (w / TileSize.referenceWidth)
        }
    }

    var largeCrackCharFont: Font {
        switch self {
        case .small: return .system(size: 18, weight: .bold)
        case .compact: return .system(size: 22, weight: .bold)
        case .medium: return .system(size: 28, weight: .bold)
        case .large: return .system(size: 36, weight: .bold)
        case .iPadSmall: return .system(size: 26, weight: .bold)
        case .iPadCompact: return .system(size: 30, weight: .bold)
        case .iPadMedium: return .system(size: 36, weight: .bold)
        case .scaled(let w): return .system(size: 28 * (w / TileSize.referenceWidth), weight: .bold)
        }
    }

    var upperLeftFont: Font {
        switch self {
        case .small: return .system(size: 8, weight: .heavy)
        case .compact: return .system(size: 9, weight: .heavy)
        case .medium: return .system(size: 11, weight: .heavy)
        case .large: return .system(size: 14, weight: .heavy)
        case .iPadSmall: return .system(size: 11, weight: .heavy)
        case .iPadCompact: return .system(size: 12, weight: .heavy)
        case .iPadMedium: return .system(size: 14, weight: .heavy)
        case .scaled(let w): return .system(size: 11 * (w / TileSize.referenceWidth), weight: .heavy)
        }
    }

    var upperLeftPaddingH: CGFloat {
        switch self {
        case .small: return 2
        case .compact: return 3
        case .medium: return 3
        case .large: return 4
        case .iPadSmall: return 3
        case .iPadCompact: return 4
        case .iPadMedium: return 4
        case .scaled(let w): return 3 * (w / TileSize.referenceWidth)
        }
    }

    var bambooGraphicWidth: CGFloat {
        switch self {
        case .small: return 28
        case .compact: return 32
        case .medium: return 40
        case .large: return 52
        case .iPadSmall: return 40
        case .iPadCompact: return 48
        case .iPadMedium: return 58
        case .scaled(let w): return 40 * (w / TileSize.referenceWidth)
        }
    }

    var bambooGraphicHeight: CGFloat {
        switch self {
        case .small: return 36
        case .compact: return 42
        case .medium: return 52
        case .large: return 66
        case .iPadSmall: return 50
        case .iPadCompact: return 58
        case .iPadMedium: return 72
        case .scaled(let w): return 52 * (w / TileSize.referenceWidth)
        }
    }

    var bambooGraphicOffsetY: CGFloat {
        switch self {
        case .small: return 3
        case .compact: return 3
        case .medium: return 4
        case .large: return 5
        case .iPadSmall: return 4
        case .iPadCompact: return 4
        case .iPadMedium: return 5
        case .scaled(let w): return 4 * (w / TileSize.referenceWidth)
        }
    }

    var bambooNumberFont: Font {
        switch self {
        case .small: return .system(size: 12, weight: .heavy)
        case .compact: return .system(size: 14, weight: .heavy)
        case .medium: return .system(size: 18, weight: .heavy)
        case .large: return .system(size: 24, weight: .heavy)
        case .iPadSmall: return .system(size: 18, weight: .heavy)
        case .iPadCompact: return .system(size: 22, weight: .heavy)
        case .iPadMedium: return .system(size: 26, weight: .heavy)
        case .scaled(let w): return .system(size: 18 * (w / TileSize.referenceWidth), weight: .heavy)
        }
    }

    var upperLeftPaddingV: CGFloat {
        switch self {
        case .small: return 1
        case .compact: return 2
        case .medium: return 2
        case .large: return 3
        case .iPadSmall: return 2
        case .iPadCompact: return 3
        case .iPadMedium: return 3
        case .scaled(let w): return 2 * (w / TileSize.referenceWidth)
        }
    }

    var iPadEquivalent: TileSize {
        switch self {
        case .small: return .iPadSmall
        case .compact: return .iPadCompact
        case .medium: return .iPadMedium
        case .large: return .large
        default: return self
        }
    }
}
