import SwiftUI

nonisolated enum TileSuit: String, CaseIterable, Codable, Sendable, Identifiable {
    case bamboo = "Bamboo"
    case character = "Character"
    case dot = "Dot"
    case wind = "Wind"
    case dragon = "Dragon"
    case flower = "Flower"
    case joker = "Joker"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .bamboo: return "leaf.fill"
        case .character: return "character.textbox"
        case .dot: return "circle.fill"
        case .wind: return "wind"
        case .dragon: return "flame.fill"
        case .flower: return "flower.fill"
        case .joker: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .bamboo: return Color(red: 0.2, green: 0.6, blue: 0.3)
        case .character: return Color(red: 0.7, green: 0.2, blue: 0.2)
        case .dot: return Color(red: 0.2, green: 0.4, blue: 0.7)
        case .wind: return Color(red: 0.4, green: 0.4, blue: 0.5)
        case .dragon: return Color(red: 0.8, green: 0.3, blue: 0.4)
        case .flower: return Color(red: 0.8, green: 0.5, blue: 0.6)
        case .joker: return Color(red: 0.9, green: 0.7, blue: 0.2)
        }
    }
}

nonisolated struct MahjongTile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let suit: TileSuit
    let value: Int
    var isSelected: Bool
    var isRevealed: Bool
    var isDiscarded: Bool

    init(id: UUID = UUID(), suit: TileSuit, value: Int, isSelected: Bool = false, isRevealed: Bool = false, isDiscarded: Bool = false) {
        self.id = id
        self.suit = suit
        self.value = value
        self.isSelected = isSelected
        self.isRevealed = isRevealed
        self.isDiscarded = isDiscarded
    }

    /// Whether this tile can stand in for `other` when forming a group
    /// (pung / kong / quint / exposure), per NMJL matching rules.
    ///
    /// NMJL treats all eight Flowers as one interchangeable tile — F1 through F8
    /// are equivalent for the purpose of building a Flower group. Every other
    /// suit matches on suit *and* value, as you'd expect.
    ///
    /// This distinction is load-bearing: the deck contains exactly ONE copy of
    /// each flower value (F1…F8), so comparing `value` — which is what the call
    /// logic did for every suit — meant two flowers could never match each other.
    /// A player's flower count against a discarded flower was therefore always
    /// zero, making a discarded flower impossible to call and a flower exposure
    /// impossible to build.
    ///
    /// Jokers are deliberately NOT handled here: joker substitution is a separate
    /// rule (allowed only in groups of 3+) and every caller layers it on top.
    func matchesForGrouping(_ other: MahjongTile) -> Bool {
        if suit == .flower && other.suit == .flower { return true }
        return suit == other.suit && value == other.value
    }

    var displayName: String {
        switch suit {
        case .wind:
            let winds = ["East", "South", "West", "North"]
            return winds[min(value - 1, 3)]
        case .dragon:
            let dragons = ["Red", "Green", "White"]
            return dragons[min(value - 1, 2)]
        case .flower:
            return "Flower \(value)"
        case .joker:
            return "Joker"
        default:
            return "\(value) \(suit.rawValue)"
        }
    }

    var shortLabel: String {
        switch suit {
        case .wind:
            let labels = ["E", "S", "W", "N"]
            return labels[min(value - 1, 3)]
        case .dragon:
            let labels = ["R", "G", "W"]
            return labels[min(value - 1, 2)]
        case .flower:
            return "F\(value)"
        case .joker:
            return "J"
        default:
            return "\(value)"
        }
    }

    static func createFullSet() -> [MahjongTile] {
        var tiles: [MahjongTile] = []

        for suit in [TileSuit.bamboo, .character, .dot] {
            for value in 1...9 {
                for _ in 1...4 {
                    tiles.append(MahjongTile(suit: suit, value: value))
                }
            }
        }

        for value in 1...4 {
            for _ in 1...4 {
                tiles.append(MahjongTile(suit: .wind, value: value))
            }
        }

        for value in 1...3 {
            for _ in 1...4 {
                tiles.append(MahjongTile(suit: .dragon, value: value))
            }
        }

        for value in 1...4 {
            tiles.append(MahjongTile(suit: .flower, value: value))
        }
        for value in 1...4 {
            tiles.append(MahjongTile(suit: .flower, value: value + 4))
        }

        for _ in 1...8 {
            tiles.append(MahjongTile(suit: .joker, value: 1))
        }

        return tiles.shuffled()
    }
}
