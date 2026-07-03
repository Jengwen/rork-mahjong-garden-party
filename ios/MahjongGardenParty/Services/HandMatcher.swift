import Foundation

nonisolated struct TileKey: Hashable, Sendable {
    let suit: TileSuit
    let value: Int
}

nonisolated struct HandMatcher {
    static func checkWin(hand: [MahjongTile], exposedSets: [[MahjongTile]], card: NMJLCard) -> NMJLHand? {
        var allTiles: [MahjongTile] = hand
        for set in exposedSets {
            allTiles.append(contentsOf: set)
        }

        let hasExposed = !exposedSets.isEmpty

        for nmjlHand in card.hands {
            if nmjlHand.concealed && hasExposed { continue }
            if allTiles.count != nmjlHand.totalTiles { continue }
            if hasExposed && !exposedSetsCompatible(exposedSets: exposedSets, targetHand: nmjlHand) { continue }
            if matchHand(tiles: allTiles, pattern: nmjlHand) {
                return nmjlHand
            }
        }
        return nil
    }

    static func matchHand(tiles: [MahjongTile], pattern: NMJLHand) -> Bool {
        let suitSlots = collectSlots(groups: pattern.groups, isSuit: true)
        let windSlots = collectSlots(groups: pattern.groups, isSuit: false)
        let dragonSlots = collectDragonSlots(groups: pattern.groups)
        let valueSlotInfo = collectValueSlots(groups: pattern.groups)

        let suits: [TileSuit] = [.bamboo, .character, .dot]
        let windValues = [1, 2, 3, 4]
        let dragonValues = [1, 2, 3]

        let suitSlotList = Array(suitSlots)
        let windSlotList = Array(windSlots)
        let dragonSlotList = Array(dragonSlots)

        var suitAssignments: [[Int: TileSuit]] = [[:]]
        for slot in suitSlotList {
            var next: [[Int: TileSuit]] = []
            for existing in suitAssignments {
                for suit in suits {
                    var copy = existing
                    copy[slot] = suit
                    next.append(copy)
                }
            }
            suitAssignments = next
        }

        if pattern.requireUniqueSuits {
            suitAssignments = suitAssignments.filter { assignment in
                let values = Array(assignment.values)
                return Set(values).count == values.count
            }
        }

        var windAssignments: [[Int: Int]] = [[:]]
        for slot in windSlotList {
            var next: [[Int: Int]] = []
            for existing in windAssignments {
                for val in windValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            windAssignments = next
        }

        var dragonAssignments: [[Int: Int]] = [[:]]
        for slot in dragonSlotList {
            var next: [[Int: Int]] = []
            for existing in dragonAssignments {
                for val in dragonValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            dragonAssignments = next
        }

        var valueAssignments: [[Int: Int]] = [[:]]
        for (slot, allowedValues) in valueSlotInfo {
            var next: [[Int: Int]] = []
            for existing in valueAssignments {
                for val in allowedValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            valueAssignments = next
        }

        for sa in suitAssignments {
            for wa in windAssignments {
                for da in dragonAssignments {
                    for va in valueAssignments {
                        if tryMatch(tiles: tiles, groups: pattern.groups, suitAssignments: sa, windAssignments: wa, dragonAssignments: da, valueAssignments: va) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    private static func collectSlots(groups: [HandGroup], isSuit: Bool) -> Set<Int> {
        var slots: Set<Int> = []
        for group in groups {
            switch group.tile {
            case .anySuit(let slot, _), .matchingDragon(let slot):
                if isSuit { slots.insert(slot) }
            case .anyValueAnySuit(let suitSlot, _, _):
                if isSuit { slots.insert(suitSlot) }
            case .anyWindSlot(let slot):
                if !isSuit { slots.insert(slot) }
            default:
                break
            }
        }
        return slots
    }

    private static func collectDragonSlots(groups: [HandGroup]) -> Set<Int> {
        var slots: Set<Int> = []
        for group in groups {
            if case .anyDragonSlot(let slot) = group.tile {
                slots.insert(slot)
            }
        }
        return slots
    }

    private static func collectValueSlots(groups: [HandGroup]) -> [Int: [Int]] {
        var slots: [Int: [Int]] = [:]
        for group in groups {
            if case .anyValueAnySuit(_, let valueSlot, let allowedValues) = group.tile {
                slots[valueSlot] = allowedValues
            }
        }
        return slots
    }

    private static func tryMatch(
        tiles: [MahjongTile],
        groups: [HandGroup],
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int] = [:]
    ) -> Bool {
        var freq: [TileKey: Int] = [:]
        var jokerCount = 0
        var flowerCount = 0

        for tile in tiles {
            if tile.suit == .joker {
                jokerCount += 1
            } else if tile.suit == .flower {
                flowerCount += 1
            } else {
                let key = TileKey(suit: tile.suit, value: tile.value)
                freq[key, default: 0] += 1
            }
        }

        var totalJokersNeeded = 0

        for group in groups {
            if case .flower = group.tile {
                let used = min(flowerCount, group.count)
                let deficit = group.count - used
                if deficit > 0 && !group.jokersAllowed { return false }
                flowerCount -= used
                totalJokersNeeded += deficit
                continue
            }

            guard let resolved = resolveTileSpec(group.tile, suitAssignments: suitAssignments, windAssignments: windAssignments, dragonAssignments: dragonAssignments, valueAssignments: valueAssignments) else {
                return false
            }

            let available = freq[resolved, default: 0]
            let used = min(available, group.count)
            let deficit = group.count - used

            if deficit > 0 && !group.jokersAllowed {
                return false
            }

            freq[resolved] = available - used
            totalJokersNeeded += deficit
        }

        return totalJokersNeeded <= jokerCount
    }

    private static func resolveTileSpec(
        _ spec: TileSpec,
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int] = [:]
    ) -> TileKey? {
        switch spec {
        case .numbered(let suit, let value):
            return TileKey(suit: suit, value: value)
        case .anySuit(let slot, let value):
            guard let suit = suitAssignments[slot] else { return nil }
            return TileKey(suit: suit, value: value)
        case .dragon(let value):
            return TileKey(suit: .dragon, value: value)
        case .matchingDragon(let slot):
            guard let suit = suitAssignments[slot] else { return nil }
            let dragonValue: Int
            switch suit {
            case .bamboo: dragonValue = 2
            case .character: dragonValue = 1
            case .dot: dragonValue = 3
            default: return nil
            }
            return TileKey(suit: .dragon, value: dragonValue)
        case .wind(let value):
            return TileKey(suit: .wind, value: value)
        case .flower:
            return nil
        case .anyWindSlot(let slot):
            guard let val = windAssignments[slot] else { return nil }
            return TileKey(suit: .wind, value: val)
        case .anyDragonSlot(let slot):
            guard let val = dragonAssignments[slot] else { return nil }
            return TileKey(suit: .dragon, value: val)
        case .anyValueAnySuit(let suitSlot, let valueSlot, _):
            guard let suit = suitAssignments[suitSlot] else { return nil }
            guard let value = valueAssignments[valueSlot] else { return nil }
            return TileKey(suit: suit, value: value)
        }
    }

    static func checkWinForBot(hand: [MahjongTile], exposedSets: [[MahjongTile]], card: NMJLCard) -> Bool {
        return checkWin(hand: hand, exposedSets: exposedSets, card: card) != nil
    }

    // MARK: - Call Validation (NMJL Rules)

    static func canCallTileForExposure(
        tile: MahjongTile,
        hand: [MahjongTile],
        exposedSets: [[MahjongTile]],
        targetHand: NMJLHand?
    ) -> [CallType] {
        // NMJL rule: a discarded Joker can never be called.
        if tile.suit == .joker { return [] }
        guard let target = targetHand else {
            return basicCallCheck(tile: tile, hand: hand)
        }

        if target.concealed {
            return []
        }

        var calls: [CallType] = []
        let tileKey = TileKey(suit: tile.suit, value: tile.value)

        let matchCount = hand.filter { $0.suit == tile.suit && $0.value == tile.value }.count
        let jokerCount = hand.filter { $0.suit == .joker }.count

        let neededGroups = groupsNeedingTile(tileKey: tileKey, targetHand: target, hand: hand, exposedSets: exposedSets)

        for group in neededGroups {
            if group.count >= 3 {
                let handMatches = matchCount
                let jokersAvailable = jokerCount

                if group.count == 3 && (handMatches + jokersAvailable) >= 2 && !calls.contains(.pung) {
                    calls.append(.pung)
                }
                if group.count == 4 && (handMatches + jokersAvailable) >= 3 && !calls.contains(.kong) {
                    calls.append(.kong)
                }
                if group.count >= 5 && (handMatches + jokersAvailable) >= (group.count - 1) && !calls.contains(.quint) {
                    calls.append(.quint)
                }
            }
        }

        var testHand = hand
        testHand.append(tile)
        if checkWin(hand: testHand, exposedSets: exposedSets, card: NMJLCard(id: "test", year: .year2025, hands: [target])) != nil {
            if !calls.contains(.mahjong) {
                calls.append(.mahjong)
            }
        }

        return calls
    }

    static func canCallForMahjong(
        tile: MahjongTile,
        hand: [MahjongTile],
        exposedSets: [[MahjongTile]],
        card: NMJLCard
    ) -> Bool {
        // NMJL rule: a discarded Joker can never be called for mahjong.
        if tile.suit == .joker { return false }
        var testHand = hand
        testHand.append(tile)
        return checkWin(hand: testHand, exposedSets: exposedSets, card: card) != nil
    }

    private static func basicCallCheck(tile: MahjongTile, hand: [MahjongTile]) -> [CallType] {
        var calls: [CallType] = []
        let matchCount = hand.filter { $0.suit == tile.suit && $0.value == tile.value }.count
        let jokerCount = hand.filter { $0.suit == .joker }.count

        if (matchCount + jokerCount) >= 2 && matchCount >= 1 {
            calls.append(.pung)
        }
        if (matchCount + jokerCount) >= 3 && matchCount >= 1 {
            calls.append(.kong)
        }
        calls.append(.mahjong)
        return calls
    }

    private static func groupsNeedingTile(tileKey: TileKey, targetHand: NMJLHand, hand: [MahjongTile], exposedSets: [[MahjongTile]]) -> [HandGroup] {
        let suits: [TileSuit] = [.bamboo, .character, .dot]

        var matchingGroups: [HandGroup] = []

        for group in targetHand.groups {
            guard group.count >= 3 else { continue }

            switch group.tile {
            case .numbered(let suit, let value):
                if tileKey.suit == suit && tileKey.value == value {
                    matchingGroups.append(group)
                }
            case .anySuit(_, let value):
                if tileKey.value == value && suits.contains(tileKey.suit) {
                    matchingGroups.append(group)
                }
            case .dragon(let value):
                if tileKey.suit == .dragon && tileKey.value == value {
                    matchingGroups.append(group)
                }
            case .matchingDragon:
                if tileKey.suit == .dragon {
                    matchingGroups.append(group)
                }
            case .wind(let value):
                if tileKey.suit == .wind && tileKey.value == value {
                    matchingGroups.append(group)
                }
            case .anyWindSlot:
                if tileKey.suit == .wind {
                    matchingGroups.append(group)
                }
            case .anyDragonSlot:
                if tileKey.suit == .dragon {
                    matchingGroups.append(group)
                }
            case .anyValueAnySuit(_, _, let allowedValues):
                if suits.contains(tileKey.suit) && allowedValues.contains(tileKey.value) {
                    matchingGroups.append(group)
                }
            case .flower:
                if tileKey.suit == .flower {
                    matchingGroups.append(group)
                }
            }
        }

        return matchingGroups
    }

    // MARK: - Hand Analysis for Suggested Hands

    nonisolated struct HandAnalysis: Sendable {
        let hand: NMJLHand
        let tilesNeeded: Int
        let tilesHave: Int
        let totalTiles: Int
        let matchedTileKeys: [TileKey]
        let missingDescriptions: [String]

        var progress: Double {
            guard totalTiles > 0 else { return 0 }
            return Double(tilesHave) / Double(totalTiles)
        }
    }

    static func analyzeAllHands(playerHand: [MahjongTile], exposedSets: [[MahjongTile]], card: NMJLCard) -> [HandAnalysis] {
        var allTiles = playerHand
        for set in exposedSets {
            allTiles.append(contentsOf: set)
        }

        let hasExposed = !exposedSets.isEmpty
        let deadline = Date().addingTimeInterval(3.0)

        var results: [HandAnalysis] = []
        results.reserveCapacity(card.hands.count)
        for nmjlHand in card.hands {
            if hasExposed {
                if nmjlHand.concealed { continue }
                if !exposedSetsCompatible(exposedSets: exposedSets, targetHand: nmjlHand) { continue }
            }
            let analysis = analyzeHandFit(tiles: allTiles, targetHand: nmjlHand)
            results.append(analysis)
            if Date() > deadline { break }
        }

        results.sort { $0.tilesNeeded < $1.tilesNeeded }
        return results
    }

    private static func exposedSetsCompatible(exposedSets: [[MahjongTile]], targetHand: NMJLHand) -> Bool {
        let suits: [TileSuit] = [.bamboo, .character, .dot]

        var exposedKeys: [(key: TileKey, count: Int)] = []
        for set in exposedSets {
            let nonJokers = set.filter { $0.suit != .joker }
            guard let representative = nonJokers.first else { continue }
            let key = TileKey(suit: representative.suit, value: representative.value)
            exposedKeys.append((key, set.count))
        }

        let suitSlots = collectSlots(groups: targetHand.groups, isSuit: true)
        let windSlots = collectSlots(groups: targetHand.groups, isSuit: false)
        let dragonSlots = collectDragonSlots(groups: targetHand.groups)
        let valueSlotInfo = collectValueSlots(groups: targetHand.groups)

        let suitPerms = filterUniqueSuits(generateSuitAssignments(slots: Array(suitSlots), suits: suits), requireUnique: targetHand.requireUniqueSuits)
        let windPerms = generateIntAssignments(slots: Array(windSlots), values: [1, 2, 3, 4])
        let dragonPerms = generateIntAssignments(slots: Array(dragonSlots), values: [1, 2, 3])
        var valuePerms: [[Int: Int]] = [[:]] 
        for (slot, allowedValues) in valueSlotInfo {
            var next: [[Int: Int]] = []
            for existing in valuePerms {
                for val in allowedValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            valuePerms = next
        }

        for sa in suitPerms {
            for wa in windPerms {
                for da in dragonPerms {
                    for va in valuePerms {
                        if allExposedSetsMatch(exposedKeys: exposedKeys, groups: targetHand.groups, suitAssignments: sa, windAssignments: wa, dragonAssignments: da, valueAssignments: va) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    private static func allExposedSetsMatch(
        exposedKeys: [(key: TileKey, count: Int)],
        groups: [HandGroup],
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int]
    ) -> Bool {
        var used = Array(repeating: false, count: groups.count)
        return matchExposedRecursive(
            exposedKeys: exposedKeys,
            exposedIndex: 0,
            groups: groups,
            used: &used,
            suitAssignments: suitAssignments,
            windAssignments: windAssignments,
            dragonAssignments: dragonAssignments,
            valueAssignments: valueAssignments
        )
    }

    private static func matchExposedRecursive(
        exposedKeys: [(key: TileKey, count: Int)],
        exposedIndex: Int,
        groups: [HandGroup],
        used: inout [Bool],
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int]
    ) -> Bool {
        if exposedIndex >= exposedKeys.count { return true }
        let exposed = exposedKeys[exposedIndex]

        for (index, group) in groups.enumerated() {
            if used[index] { continue }
            guard group.count == exposed.count else { continue }

            var candidateMatches = false
            if case .flower = group.tile {
                if exposed.key.suit == .flower { candidateMatches = true }
            } else if let resolved = resolveTileSpec(
                group.tile,
                suitAssignments: suitAssignments,
                windAssignments: windAssignments,
                dragonAssignments: dragonAssignments,
                valueAssignments: valueAssignments
            ) {
                if resolved == exposed.key { candidateMatches = true }
            }

            if !candidateMatches { continue }

            used[index] = true
            if matchExposedRecursive(
                exposedKeys: exposedKeys,
                exposedIndex: exposedIndex + 1,
                groups: groups,
                used: &used,
                suitAssignments: suitAssignments,
                windAssignments: windAssignments,
                dragonAssignments: dragonAssignments,
                valueAssignments: valueAssignments
            ) {
                return true
            }
            used[index] = false
        }

        return false
    }

    private static func analyzeHandFit(tiles: [MahjongTile], targetHand: NMJLHand) -> HandAnalysis {
        let suits: [TileSuit] = [.bamboo, .character, .dot]
        let suitSlots = collectSlots(groups: targetHand.groups, isSuit: true)
        let windSlots = collectSlots(groups: targetHand.groups, isSuit: false)
        let dragonSlots = collectDragonSlots(groups: targetHand.groups)
        let valueSlotInfo = collectValueSlots(groups: targetHand.groups)

        let suitPerms = filterUniqueSuits(generateSuitAssignments(slots: Array(suitSlots), suits: suits), requireUnique: targetHand.requireUniqueSuits)
        let windPerms = generateIntAssignments(slots: Array(windSlots), values: [1, 2, 3, 4])
        let dragonPerms = generateIntAssignments(slots: Array(dragonSlots), values: [1, 2, 3])
        var valuePerms: [[Int: Int]] = [[:]] 
        for (slot, allowedValues) in valueSlotInfo {
            var next: [[Int: Int]] = []
            for existing in valuePerms {
                for val in allowedValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            valuePerms = next
        }

        var bestHave = 0
        var bestMatched: [TileKey] = []
        var bestMissing: [String] = []

        for sa in suitPerms {
            for wa in windPerms {
                for da in dragonPerms {
                    for va in valuePerms {
                        let (have, matched, missing) = scoreAnalysis(
                            tiles: tiles,
                            groups: targetHand.groups,
                            suitAssignments: sa,
                            windAssignments: wa,
                            dragonAssignments: da,
                            valueAssignments: va
                        )
                        if have > bestHave {
                            bestHave = have
                            bestMatched = matched
                            bestMissing = missing
                        }
                    }
                }
            }
        }

        let total = targetHand.totalTiles
        let needed = total - bestHave

        return HandAnalysis(
            hand: targetHand,
            tilesNeeded: max(needed, 0),
            tilesHave: bestHave,
            totalTiles: total,
            matchedTileKeys: bestMatched,
            missingDescriptions: bestMissing
        )
    }

    private static func scoreAnalysis(
        tiles: [MahjongTile],
        groups: [HandGroup],
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int]
    ) -> (Int, [TileKey], [String]) {
        var freq: [TileKey: Int] = [:]
        var jokerCount = 0
        var flowerCount = 0

        for tile in tiles {
            if tile.suit == .joker {
                jokerCount += 1
            } else if tile.suit == .flower {
                flowerCount += 1
            } else {
                let key = TileKey(suit: tile.suit, value: tile.value)
                freq[key, default: 0] += 1
            }
        }

        var totalHave = 0
        var matched: [TileKey] = []
        var missing: [String] = []
        var jokersUsed = 0

        struct JokerCandidate {
            let groupDesc: String
            let deficit: Int
        }
        var jokerCandidates: [JokerCandidate] = []

        for group in groups {
            if case .flower = group.tile {
                let used = min(flowerCount, group.count)
                totalHave += used
                flowerCount -= used
                let deficit = group.count - used
                if deficit > 0 {
                    if group.jokersAllowed {
                        jokerCandidates.append(JokerCandidate(groupDesc: "Flower", deficit: deficit))
                    } else {
                        missing.append("\(deficit)x Flower")
                    }
                }
                for _ in 0..<used {
                    matched.append(TileKey(suit: .flower, value: 1))
                }
                continue
            }

            guard let resolved = resolveTileSpec(
                group.tile,
                suitAssignments: suitAssignments,
                windAssignments: windAssignments,
                dragonAssignments: dragonAssignments,
                valueAssignments: valueAssignments
            ) else {
                missing.append("\(group.count)x ?")
                continue
            }

            let available = freq[resolved, default: 0]
            let used = min(available, group.count)
            totalHave += used
            freq[resolved] = available - used

            for _ in 0..<used {
                matched.append(resolved)
            }

            let deficit = group.count - used
            if deficit > 0 {
                if group.jokersAllowed {
                    jokerCandidates.append(JokerCandidate(groupDesc: describeTileKey(resolved), deficit: deficit))
                } else {
                    missing.append("\(deficit)x \(describeTileKey(resolved))")
                }
            }
        }

        var remainingJokers = jokerCount - jokersUsed
        var unfilled: [JokerCandidate] = []
        for candidate in jokerCandidates {
            let jokersForThis = min(remainingJokers, candidate.deficit)
            totalHave += jokersForThis
            remainingJokers -= jokersForThis
            let remaining = candidate.deficit - jokersForThis
            if remaining > 0 {
                unfilled.append(JokerCandidate(groupDesc: candidate.groupDesc, deficit: remaining))
            }
        }

        for candidate in unfilled {
            missing.append("\(candidate.deficit)x \(candidate.groupDesc)")
        }

        return (totalHave, matched, missing)
    }

    static func describeTileKey(_ key: TileKey) -> String {
        switch key.suit {
        case .bamboo: return "\(key.value) Bam"
        case .character: return "\(key.value) Crak"
        case .dot: return "\(key.value) Dot"
        case .wind:
            let names = ["East", "South", "West", "North"]
            let idx = max(0, min(key.value - 1, names.count - 1))
            return names[idx]
        case .dragon:
            let names = ["Red Dr", "Green Dr", "White Dr"]
            let idx = max(0, min(key.value - 1, names.count - 1))
            return names[idx]
        case .flower: return "Flower"
        case .joker: return "Joker"
        }
    }

    static func playerHasTile(_ key: TileKey, in tiles: [MahjongTile]) -> Int {
        if key.suit == .flower {
            return tiles.filter { $0.suit == .flower }.count
        }
        return tiles.filter { $0.suit == key.suit && $0.value == key.value }.count
    }

    // MARK: - Bot Target Hand Selection

    static func selectBestTargetHand(hand: [MahjongTile], card: NMJLCard) -> NMJLHand? {
        var bestHand: NMJLHand?
        var bestScore: Int = -1

        for nmjlHand in card.hands {
            let score = scoreHandFit(hand: hand, targetHand: nmjlHand)
            if score > bestScore {
                bestScore = score
                bestHand = nmjlHand
            }
        }

        return bestHand
    }

    private static func scoreHandFit(hand: [MahjongTile], targetHand: NMJLHand) -> Int {
        let suits: [TileSuit] = [.bamboo, .character, .dot]

        var bestScore = 0

        let suitSlots = collectSlots(groups: targetHand.groups, isSuit: true)
        let windSlots = collectSlots(groups: targetHand.groups, isSuit: false)
        let dragonSlots = collectDragonSlots(groups: targetHand.groups)

        let valueSlotInfo = collectValueSlots(groups: targetHand.groups)
        let suitPerms = filterUniqueSuits(generateSuitAssignments(slots: Array(suitSlots), suits: suits), requireUnique: targetHand.requireUniqueSuits)
        let windPerms = generateIntAssignments(slots: Array(windSlots), values: [1, 2, 3, 4])
        let dragonPerms = generateIntAssignments(slots: Array(dragonSlots), values: [1, 2, 3])
        var valuePerms: [[Int: Int]] = [[:]]  
        for (slot, allowedValues) in valueSlotInfo {
            var next: [[Int: Int]] = []
            for existing in valuePerms {
                for val in allowedValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            valuePerms = next
        }

        for sa in suitPerms {
            for wa in windPerms {
                for da in dragonPerms {
                    for va in valuePerms {
                        let score = scoreAssignment(hand: hand, groups: targetHand.groups, suitAssignments: sa, windAssignments: wa, dragonAssignments: da, valueAssignments: va)
                        bestScore = max(bestScore, score)
                    }
                }
            }
        }

        return bestScore
    }

    private static func filterUniqueSuits(_ assignments: [[Int: TileSuit]], requireUnique: Bool) -> [[Int: TileSuit]] {
        guard requireUnique else { return assignments }
        return assignments.filter { assignment in
            let suits = Array(assignment.values)
            return Set(suits).count == suits.count
        }
    }

    private static func generateSuitAssignments(slots: [Int], suits: [TileSuit]) -> [[Int: TileSuit]] {
        var result: [[Int: TileSuit]] = [[:]]
        for slot in slots {
            var next: [[Int: TileSuit]] = []
            for existing in result {
                for suit in suits {
                    var copy = existing
                    copy[slot] = suit
                    next.append(copy)
                }
            }
            result = next
        }
        return result
    }

    private static func generateIntAssignments(slots: [Int], values: [Int]) -> [[Int: Int]] {
        var result: [[Int: Int]] = [[:]]
        for slot in slots {
            var next: [[Int: Int]] = []
            for existing in result {
                for val in values {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            result = next
        }
        return result
    }

    private static func scoreAssignment(
        hand: [MahjongTile],
        groups: [HandGroup],
        suitAssignments: [Int: TileSuit],
        windAssignments: [Int: Int],
        dragonAssignments: [Int: Int],
        valueAssignments: [Int: Int] = [:]
    ) -> Int {
        var freq: [TileKey: Int] = [:]
        var jokerCount = 0
        var flowerCount = 0

        for tile in hand {
            if tile.suit == .joker {
                jokerCount += 1
            } else if tile.suit == .flower {
                flowerCount += 1
            } else {
                let key = TileKey(suit: tile.suit, value: tile.value)
                freq[key, default: 0] += 1
            }
        }

        var score = 0

        for group in groups {
            if case .flower = group.tile {
                let used = min(flowerCount, group.count)
                score += used * 2
                flowerCount -= used
                continue
            }

            guard let resolved = resolveTileSpec(group.tile, suitAssignments: suitAssignments, windAssignments: windAssignments, dragonAssignments: dragonAssignments, valueAssignments: valueAssignments) else {
                continue
            }

            let available = freq[resolved, default: 0]
            let used = min(available, group.count)
            score += used * 2
            freq[resolved] = available - used
        }

        score += jokerCount

        return score
    }

    // MARK: - Bot Smart Discard

    static func selectBotDiscard(hand: [MahjongTile], targetHand: NMJLHand?) -> Int {
        guard let target = targetHand, !hand.isEmpty else {
            return hand.isEmpty ? 0 : Int.random(in: 0..<hand.count)
        }

        let scores = scoreTilesForTarget(hand: hand, target: target)
        let minScore = scores.min(by: { $0.score < $1.score })?.score ?? 0
        let worstTiles = scores.filter { $0.score == minScore }
        let pick = worstTiles.randomElement() ?? scores[0]
        return pick.index
    }

    static func selectBotCharlestonTiles(hand: [MahjongTile], targetHand: NMJLHand?, count: Int) -> [Int] {
        guard !hand.isEmpty, count > 0 else { return [] }
        guard let target = targetHand else {
            let indices = Array(0..<hand.count)
            return Array(indices.shuffled().prefix(min(count, hand.count)))
        }

        let scores = scoreTilesForTarget(hand: hand, target: target)
        let sorted = scores.sorted { $0.score < $1.score }
        return Array(sorted.prefix(min(count, sorted.count)).map { $0.index })
    }

    static func scoreTilesForTarget(hand: [MahjongTile], target: NMJLHand) -> [(index: Int, score: Int)] {
        let suits: [TileSuit] = [.bamboo, .character, .dot]
        let suitSlots = collectSlots(groups: target.groups, isSuit: true)
        let windSlots = collectSlots(groups: target.groups, isSuit: false)
        let dragonSlots = collectDragonSlots(groups: target.groups)
        let valueSlotInfo = collectValueSlots(groups: target.groups)

        let suitPerms = filterUniqueSuits(generateSuitAssignments(slots: Array(suitSlots), suits: suits), requireUnique: target.requireUniqueSuits)
        let windPerms = generateIntAssignments(slots: Array(windSlots), values: [1, 2, 3, 4])
        let dragonPerms = generateIntAssignments(slots: Array(dragonSlots), values: [1, 2, 3])
        var valuePerms: [[Int: Int]] = [[:]]  
        for (slot, allowedValues) in valueSlotInfo {
            var next: [[Int: Int]] = []
            for existing in valuePerms {
                for val in allowedValues {
                    var copy = existing
                    copy[slot] = val
                    next.append(copy)
                }
            }
            valuePerms = next
        }

        var bestAssignment: (sa: [Int: TileSuit], wa: [Int: Int], da: [Int: Int], va: [Int: Int])?
        var bestTotal = -1
        for sa in suitPerms {
            for wa in windPerms {
                for da in dragonPerms {
                    for va in valuePerms {
                        let s = scoreAssignment(hand: hand, groups: target.groups, suitAssignments: sa, windAssignments: wa, dragonAssignments: da, valueAssignments: va)
                        if s > bestTotal {
                            bestTotal = s
                            bestAssignment = (sa, wa, da, va)
                        }
                    }
                }
            }
        }

        var tileScores: [(index: Int, score: Int)] = []

        for (index, tile) in hand.enumerated() {
            if tile.suit == .joker {
                tileScores.append((index, 1000))
                continue
            }
            if tile.suit == .flower {
                let flowerNeeded = target.groups.contains { if case .flower = $0.tile { return true }; return false }
                tileScores.append((index, flowerNeeded ? 50 : 0))
                continue
            }

            let key = TileKey(suit: tile.suit, value: tile.value)
            var relevance = 0

            if let best = bestAssignment {
                for group in target.groups {
                    if let resolved = resolveTileSpec(group.tile, suitAssignments: best.sa, windAssignments: best.wa, dragonAssignments: best.da, valueAssignments: best.va) {
                        if resolved == key {
                            relevance += group.count * 5
                        }
                    }
                }
            }

            if relevance == 0 {
                for group in target.groups {
                    if tileMatchesGroup(key: key, group: group) {
                        relevance += group.count * 2
                    }
                }
            }

            let dupes = hand.filter { $0.suit == tile.suit && $0.value == tile.value }.count
            if dupes >= 2 { relevance += dupes * 3 }

            tileScores.append((index, relevance))
        }

        return tileScores
    }

    private static func tileMatchesGroup(key: TileKey, group: HandGroup) -> Bool {
        let suits: [TileSuit] = [.bamboo, .character, .dot]

        switch group.tile {
        case .numbered(let suit, let value):
            return key.suit == suit && key.value == value
        case .anySuit(_, let value):
            return key.value == value && suits.contains(key.suit)
        case .dragon(let value):
            return key.suit == .dragon && key.value == value
        case .matchingDragon:
            return key.suit == .dragon
        case .wind(let value):
            return key.suit == .wind && key.value == value
        case .anyWindSlot:
            return key.suit == .wind
        case .anyDragonSlot:
            return key.suit == .dragon
        case .anyValueAnySuit(_, _, let allowedValues):
            return suits.contains(key.suit) && allowedValues.contains(key.value)
        case .flower:
            return key.suit == .flower
        }
    }
}
