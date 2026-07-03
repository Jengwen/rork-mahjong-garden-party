import Foundation

nonisolated enum TileSpec: Sendable, Hashable {
    case numbered(suit: TileSuit, value: Int)
    case anySuit(slot: Int, value: Int)
    case dragon(value: Int)
    case matchingDragon(slot: Int)
    case wind(value: Int)
    case flower
    case anyWindSlot(slot: Int)
    case anyDragonSlot(slot: Int)
    case anyValueAnySuit(suitSlot: Int, valueSlot: Int, allowedValues: [Int])
}

nonisolated struct HandGroup: Sendable, Hashable {
    let count: Int
    let tile: TileSpec

    var jokersAllowed: Bool { count >= 3 }
}

nonisolated struct NMJLHand: Identifiable, Sendable {
    let id: String
    let category: String
    let name: String
    let groups: [HandGroup]
    let points: Int
    let concealed: Bool
    let requireUniqueSuits: Bool

    init(id: String, category: String, name: String, groups: [HandGroup], points: Int, concealed: Bool, requireUniqueSuits: Bool = false) {
        self.id = id
        self.category = category
        self.name = name
        self.groups = groups
        self.points = points
        self.concealed = concealed
        self.requireUniqueSuits = requireUniqueSuits
    }

    var totalTiles: Int { groups.reduce(0) { $0 + $1.count } }

    var displayGroups: [String] {
        groups.map { group in
            let tileLabel: String
            switch group.tile {
            case .numbered(let suit, let value):
                let suitChar: String
                switch suit {
                case .bamboo: suitChar = "B"
                case .character: suitChar = "C"
                case .dot: suitChar = "D"
                default: suitChar = "?"
                }
                tileLabel = "\(value)\(suitChar)"
            case .anySuit(_, let value):
                tileLabel = "\(value)"
            case .dragon(let value):
                let labels = ["R", "G", "0"]
                tileLabel = labels[max(0, min(value - 1, labels.count - 1))]
            case .matchingDragon:
                tileLabel = "Dr"
            case .wind(let value):
                let labels = ["E", "S", "W", "N"]
                tileLabel = labels[max(0, min(value - 1, labels.count - 1))]
            case .flower:
                tileLabel = "F"
            case .anyWindSlot:
                tileLabel = "W"
            case .anyDragonSlot:
                tileLabel = "D"
            case .anyValueAnySuit(_, _, let allowedValues):
                tileLabel = allowedValues.first.map { "\($0)" } ?? "#"
            }
            return String(repeating: tileLabel, count: group.count)
        }
    }
}

nonisolated enum NMJLCardYear: String, CaseIterable, Sendable, Identifiable {
    case year2025 = "NMJL 2025"
    case year2026 = "NMJL 2026"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var isAvailable: Bool {
        switch self {
        case .year2025: return true
        case .year2026: return true
        }
    }
}

nonisolated struct NMJLCard: Identifiable, Sendable {
    let id: String
    let year: NMJLCardYear
    let hands: [NMJLHand]

    var categories: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for hand in hands {
            if !seen.contains(hand.category) {
                seen.insert(hand.category)
                result.append(hand.category)
            }
        }
        return result
    }

    func handsInCategory(_ category: String) -> [NMJLHand] {
        hands.filter { $0.category == category }
    }
}
