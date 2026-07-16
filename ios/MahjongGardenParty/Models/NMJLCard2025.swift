import Foundation

extension NMJLCard {
    static let card2025 = NMJLCard(
        id: "nmjl_2025",
        year: .year2025,
        hands: yearHands2025 + evenHands2025 + anyLikeHands2025 + quintHands2025 + consecutiveHands2025 + oddHands2025 + windsDragonsHands2025 + threeSixNineHands2025 + singlesPairsHands2025
    )

    // MARK: - 2025 Year Hands

    private static let yearHands2025: [NMJLHand] = [
        NMJLHand(
            id: "2025_1a",
            category: "2025",
            name: "2025 #1",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 2)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2025_1b",
            category: "2025",
            name: "2025 #1",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2025_2",
            category: "2025",
            name: "2025 #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .dragon(value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2025_3",
            category: "2025",
            name: "2025 #3",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2025_4",
            category: "2025",
            name: "2025 #4",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .dragon(value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - 2468 (Even Numbers)

    private static let evenHands2025: [NMJLHand] = [
        NMJLHand(
            id: "2468_1a",
            category: "2468",
            name: "2468 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2468_1b",
            category: "2468",
            name: "2468 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 8)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2468_2a",
            category: "2468",
            name: "2468 #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2468_2b",
            category: "2468",
            name: "2468 #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 8)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2468_3",
            category: "2468",
            name: "2468 #3",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2468_4",
            category: "2468",
            name: "2468 #4",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2468_5",
            category: "2468",
            name: "2468 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2468_6",
            category: "2468",
            name: "2468 #6",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 8)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 8)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2468_7",
            category: "2468",
            name: "2468 #7",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 4, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2468_8",
            category: "2468",
            name: "2468 #8",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - Any Like Numbers

    private static let anyLikeHands2025: [NMJLHand] = [
        NMJLHand(
            id: "like_1",
            category: "Any Like Numbers",
            name: "Like Numbers #1",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "like_2",
            category: "Any Like Numbers",
            name: "Like Numbers #2",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "like_3",
            category: "Any Like Numbers",
            name: "Like Numbers #3",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 1)),
                HandGroup(count: 3, tile: .anyDragonSlot(slot: 1)),
            ],
            points: 25,
            concealed: true
        ),
    ]

    // MARK: - Quints

    private static let quint1Variants2025: [NMJLHand] = (1...7).map { start in
        NMJLHand(
            id: "quint_1_\(start)",
            category: "Quints",
            name: "Quints #1",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: start)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: start + 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 3, value: start + 2)),
            ],
            points: 35,
            concealed: false,
            requireUniqueSuits: true
        )
    }

    private static let quintHands2025: [NMJLHand] = quint1Variants2025 + [
        NMJLHand(
            id: "quint_2",
            category: "Quints",
            name: "Quints #2",
            groups: [
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anyWindSlot(slot: 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 2)),
            ],
            points: 35,
            concealed: false
        ),
        NMJLHand(
            id: "quint_3",
            category: "Quints",
            name: "Quints #3",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 3, value: 1)),
            ],
            points: 40,
            concealed: false
        ),
    ]

    // MARK: - Consecutive Run

    private static let consecutiveHands2025: [NMJLHand] = [
        NMJLHand(
            id: "consec_1a",
            category: "Consecutive Run",
            name: "Run #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_1b",
            category: "Consecutive Run",
            name: "Run #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_2a",
            category: "Consecutive Run",
            name: "Run #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 4)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_2b",
            category: "Consecutive Run",
            name: "Run #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 4)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_3a",
            category: "Consecutive Run",
            name: "Run #3",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_3b",
            category: "Consecutive Run",
            name: "Run #3",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_4",
            category: "Consecutive Run",
            name: "Run #4",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_5",
            category: "Consecutive Run",
            name: "Run #5",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "consec_6",
            category: "Consecutive Run",
            name: "Run #6",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_7a",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 1)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_7b",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 2)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_7c",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 3)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_7d",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 4)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_7e",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "consec_8",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
            ],
            points: 30,
            concealed: true
        ),
    ]

    // MARK: - 13579 (Odd Numbers)

    private static let oddHands2025: [NMJLHand] = [
        NMJLHand(
            id: "odd_1a",
            category: "13579",
            name: "13579 #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "odd_1b",
            category: "13579",
            name: "13579 #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_2a",
            category: "13579",
            name: "13579 #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 5)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_2b",
            category: "13579",
            name: "13579 #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_3a",
            category: "13579",
            name: "13579 #3",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "odd_3b",
            category: "13579",
            name: "13579 #3",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "odd_4",
            category: "13579",
            name: "13579 #4",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "odd_5a",
            category: "13579",
            name: "13579 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "odd_5b",
            category: "13579",
            name: "13579 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_6a",
            category: "13579",
            name: "13579 #6",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_6b",
            category: "13579",
            name: "13579 #6",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_7a",
            category: "13579",
            name: "13579 #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .wind(value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 5)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_7b",
            category: "13579",
            name: "13579 #7",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .wind(value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_8",
            category: "13579",
            name: "13579 #8",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_9a",
            category: "13579",
            name: "13579 #9",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "odd_9b",
            category: "13579",
            name: "13579 #9",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - Winds & Dragons

    private static let windsDragonsHands2025: [NMJLHand] = [
        NMJLHand(
            id: "wd_1a",
            category: "Winds & Dragons",
            name: "Winds & Dragons #1",
            groups: [
                HandGroup(count: 4, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 4, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_1b",
            category: "Winds & Dragons",
            name: "Winds & Dragons #1",
            groups: [
                HandGroup(count: 3, tile: .wind(value: 4)),
                HandGroup(count: 4, tile: .wind(value: 1)),
                HandGroup(count: 4, tile: .wind(value: 3)),
                HandGroup(count: 3, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_2",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anyDragonSlot(slot: 2)),
                HandGroup(count: 3, tile: .anyDragonSlot(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_3",
            category: "Winds & Dragons",
            name: "Winds & Dragons #3",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 4, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_4",
            category: "Winds & Dragons",
            name: "Winds & Dragons #4",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 3, tile: .anyDragonSlot(slot: 1)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .wind(value: 2)),
                HandGroup(count: 3, tile: .anyDragonSlot(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_5",
            category: "Winds & Dragons",
            name: "Winds & Dragons #5",
            groups: [
                HandGroup(count: 4, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 2, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 4, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "wd_6",
            category: "Winds & Dragons",
            name: "Winds & Dragons #6",
            groups: [
                HandGroup(count: 4, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 2, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 3, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 4, tile: .wind(value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_7a",
            category: "Winds & Dragons",
            name: "Winds & Dragons #7",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 2, tile: .wind(value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_7b",
            category: "Winds & Dragons",
            name: "Winds & Dragons #7",
            groups: [
                HandGroup(count: 3, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 2, tile: .wind(value: 3)),
                HandGroup(count: 3, tile: .wind(value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "wd_8",
            category: "Winds & Dragons",
            name: "Winds & Dragons #8",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 3, tile: .wind(value: 2)),
                HandGroup(count: 4, tile: .anyDragonSlot(slot: 1)),
            ],
            points: 30,
            concealed: true
        ),
    ]

    // MARK: - 369

    private static let threeSixNineHands2025: [NMJLHand] = [
        NMJLHand(
            id: "369_1a",
            category: "369",
            name: "369 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_1b",
            category: "369",
            name: "369 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_2a",
            category: "369",
            name: "369 #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_2b",
            category: "369",
            name: "369 #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "369_3",
            category: "369",
            name: "369 #3",
            groups: [
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [3, 6, 9])),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [3, 6, 9])),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_4",
            category: "369",
            name: "369 #4",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_5",
            category: "369",
            name: "369 #5",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [3, 6, 9])),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [3, 6, 9])),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "369_6",
            category: "369",
            name: "369 #6",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 9)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 3)),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - Singles & Pairs

    private static let singlesPairsHands2025: [NMJLHand] = [
        NMJLHand(
            id: "sp_1",
            category: "Singles & Pairs",
            name: "Singles & Pairs #1",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 2, tile: .wind(value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "sp_2",
            category: "Singles & Pairs",
            name: "Singles & Pairs #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 8)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 2)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "sp_3",
            category: "Singles & Pairs",
            name: "Singles & Pairs #3",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 2, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [3, 6, 9])),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "sp_4",
            category: "Singles & Pairs",
            name: "Singles & Pairs #4",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 2)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "sp_5",
            category: "Singles & Pairs",
            name: "Singles & Pairs #5",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 2, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 2, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
            ],
            points: 50,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "sp_6",
            category: "Singles & Pairs",
            name: "Singles & Pairs #6",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 75,
            concealed: false
        ),
    ]

    // MARK: - 2026 Year Hands

    private static let yearHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_1",
            category: "2026",
            name: "2026 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .dragon(value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2a",
            category: "2026",
            name: "2026 #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2b",
            category: "2026",
            name: "2026 #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_3",
            category: "2026",
            name: "2026 #3",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_4",
            category: "2026",
            name: "2026 #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .dragon(value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .wind(value: 2)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - 2468 (Even Numbers) - 2026

    private static let evenHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_2468_1",
            category: "2468",
            name: "2468 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2468_2",
            category: "2468",
            name: "2468 #2",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_2468_3",
            category: "2468",
            name: "2468 #3",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 2, tile: .wind(value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2468_4",
            category: "2468",
            name: "2468 #4",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 8)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2468_5",
            category: "2468",
            name: "2468 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_2468_6",
            category: "2468",
            name: "2468 #6",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_2468_7",
            category: "2468",
            name: "2468 #7",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_2468_8",
            category: "2468",
            name: "2468 #8",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 8)),
            ],
            points: 30,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - Any Like Numbers - 2026

    private static let anyLikeHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_like_1",
            category: "Any Like Numbers",
            name: "Like Numbers #1",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 6, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 1)),
            ],
            points: 30,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_like_2",
            category: "Any Like Numbers",
            name: "Like Numbers #2",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 1)),
                HandGroup(count: 1, tile: .matchingDragon(slot: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_like_3",
            category: "Any Like Numbers",
            name: "Like Numbers #3",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 1)),
                HandGroup(count: 2, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - Quints - 2026

    private static let quint2Variants2026: [NMJLHand] = (1...7).map { start in
        NMJLHand(
            id: "2026_quint_2_\(start)",
            category: "Quints",
            name: "Quints #2",
            groups: [
                HandGroup(count: 4, tile: .flower),
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: start)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: start + 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: start + 2)),
            ],
            points: 45,
            concealed: false
        )
    }

    private static let quintHands2026: [NMJLHand] = quint2Variants2026 + [
        NMJLHand(
            id: "2026_quint_1",
            category: "Quints",
            name: "Quints #1",
            groups: [
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 3, value: 1)),
            ],
            points: 40,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_quint_3",
            category: "Quints",
            name: "Quints #3",
            groups: [
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 5, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 2)),
            ],
            points: 40,
            concealed: false
        ),
    ]

    // MARK: - Consecutive Run - 2026

    private static let consecutiveHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_consec_1a",
            category: "Consecutive Run",
            name: "Run #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_1b",
            category: "Consecutive Run",
            name: "Run #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_2a",
            category: "Consecutive Run",
            name: "Run #2",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_2b",
            category: "Consecutive Run",
            name: "Run #2",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_3",
            category: "Consecutive Run",
            name: "Run #3",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_4a",
            category: "Consecutive Run",
            name: "Run #4",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 4)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_4b",
            category: "Consecutive Run",
            name: "Run #4",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 4)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_5a",
            category: "Consecutive Run",
            name: "Run #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_5b",
            category: "Consecutive Run",
            name: "Run #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_6",
            category: "Consecutive Run",
            name: "Run #6",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 6, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_7a",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_consec_7b",
            category: "Consecutive Run",
            name: "Run #7",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8a",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 4)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8b",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8c",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8d",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 7)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8e",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 8)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_consec_8f",
            category: "Consecutive Run",
            name: "Run #8",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 8)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    // MARK: - 13579 (Odd Numbers) - 2026

    private static let oddHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_odd_1a",
            category: "13579",
            name: "13579 #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_1b",
            category: "13579",
            name: "13579 #1",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_2a",
            category: "13579",
            name: "13579 #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 5)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_2b",
            category: "13579",
            name: "13579 #2",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_3a",
            category: "13579",
            name: "13579 #3",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_3b",
            category: "13579",
            name: "13579 #3",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 2, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_4",
            category: "13579",
            name: "13579 #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_5a",
            category: "13579",
            name: "13579 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_5b",
            category: "13579",
            name: "13579 #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_6a",
            category: "13579",
            name: "13579 #6",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_6b",
            category: "13579",
            name: "13579 #6",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_7a",
            category: "13579",
            name: "13579 #7",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_odd_7b",
            category: "13579",
            name: "13579 #7",
            groups: [
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 4, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_8a",
            category: "13579",
            name: "13579 #8",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 1)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_8b",
            category: "13579",
            name: "13579 #8",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 3, value: 5)),
            ],
            points: 35,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_odd_9",
            category: "13579",
            name: "13579 #9",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
            ],
            points: 30,
            concealed: true
        ),
    ]

    // MARK: - Winds & Dragons - 2026

    private static let windsDragonsHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_wd_1a",
            category: "Winds & Dragons",
            name: "Winds & Dragons #1",
            groups: [
                HandGroup(count: 4, tile: .wind(value: 4)),
                HandGroup(count: 3, tile: .wind(value: 1)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 4, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_1b",
            category: "Winds & Dragons",
            name: "Winds & Dragons #1",
            groups: [
                HandGroup(count: 3, tile: .wind(value: 4)),
                HandGroup(count: 4, tile: .wind(value: 1)),
                HandGroup(count: 4, tile: .wind(value: 3)),
                HandGroup(count: 3, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_2a",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_2b",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_2c",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_2d",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_2e",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_2f",
            category: "Winds & Dragons",
            name: "Winds & Dragons #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 3, tile: .matchingDragon(slot: 3)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_wd_3",
            category: "Winds & Dragons",
            name: "Winds & Dragons #3",
            groups: [
                HandGroup(count: 3, tile: .wind(value: 4)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [1, 3, 5, 7, 9])),
                HandGroup(count: 3, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_4",
            category: "Winds & Dragons",
            name: "Winds & Dragons #4",
            groups: [
                HandGroup(count: 3, tile: .wind(value: 1)),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 4, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: [2, 4, 6, 8])),
                HandGroup(count: 3, tile: .wind(value: 3)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_5",
            category: "Winds & Dragons",
            name: "Winds & Dragons #5",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .wind(value: 4)),
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 4, tile: .anyDragonSlot(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_6",
            category: "Winds & Dragons",
            name: "Winds & Dragons #6",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 4, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_wd_7",
            category: "Winds & Dragons",
            name: "Winds & Dragons #7",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 3, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 2, tile: .wind(value: 2)),
            ],
            points: 30,
            concealed: true
        ),
        NMJLHand(
            id: "2026_wd_8",
            category: "Winds & Dragons",
            name: "Winds & Dragons #8",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 2, tile: .wind(value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .wind(value: 3)),
                HandGroup(count: 3, tile: .wind(value: 4)),
            ],
            points: 25,
            concealed: false
        ),
    ]

    // MARK: - 369 - 2026

    private static let threeSixNineHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_369_1a",
            category: "369",
            name: "369 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_1b",
            category: "369",
            name: "369 #1",
            groups: [
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_2",
            category: "369",
            name: "369 #2",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_3a",
            category: "369",
            name: "369 #3",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .matchingDragon(slot: 1)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_369_3b",
            category: "369",
            name: "369 #3",
            groups: [
                HandGroup(count: 3, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anyDragonSlot(slot: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_369_4",
            category: "369",
            name: "369 #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 1, tile: .wind(value: 4)),
                HandGroup(count: 1, tile: .wind(value: 1)),
                HandGroup(count: 1, tile: .wind(value: 3)),
                HandGroup(count: 1, tile: .wind(value: 2)),
            ],
            points: 25,
            concealed: false
        ),
        NMJLHand(
            id: "2026_369_5a",
            category: "369",
            name: "369 #5",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 3)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_5b",
            category: "369",
            name: "369 #5",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_5c",
            category: "369",
            name: "369 #5",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 4, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 4, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 25,
            concealed: false,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_369_6",
            category: "369",
            name: "369 #6",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 3, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 30,
            concealed: true
        ),
    ]

    // MARK: - Singles & Pairs - 2026

    private static let singlesPairsHands2026: [NMJLHand] = [
        NMJLHand(
            id: "2026_sp_1",
            category: "Singles & Pairs",
            name: "Singles & Pairs #1",
            groups: [
                HandGroup(count: 2, tile: .wind(value: 4)),
                HandGroup(count: 2, tile: .wind(value: 1)),
                HandGroup(count: 2, tile: .wind(value: 3)),
                HandGroup(count: 2, tile: .wind(value: 2)),
                HandGroup(count: 1, tile: .anyValueAnySuit(suitSlot: 1, valueSlot: 1, allowedValues: Array(1...9))),
                HandGroup(count: 1, tile: .matchingDragon(slot: 1)),
                HandGroup(count: 1, tile: .anyValueAnySuit(suitSlot: 2, valueSlot: 1, allowedValues: Array(1...9))),
                HandGroup(count: 1, tile: .matchingDragon(slot: 2)),
                HandGroup(count: 1, tile: .anyValueAnySuit(suitSlot: 3, valueSlot: 1, allowedValues: Array(1...9))),
                HandGroup(count: 1, tile: .matchingDragon(slot: 3)),
            ],
            points: 50,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_sp_2",
            category: "Singles & Pairs",
            name: "Singles & Pairs #2",
            groups: [
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 8)),
                HandGroup(count: 2, tile: .flower),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "2026_sp_3",
            category: "Singles & Pairs",
            name: "Singles & Pairs #3",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 9)),
                HandGroup(count: 2, tile: .anySuit(slot: 3, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 9)),
            ],
            points: 50,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_sp_4a",
            category: "Singles & Pairs",
            name: "Singles & Pairs #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "2026_sp_4b",
            category: "Singles & Pairs",
            name: "Singles & Pairs #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 8)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "2026_sp_4c",
            category: "Singles & Pairs",
            name: "Singles & Pairs #4",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 4)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 8)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "2026_sp_4d",
            category: "Singles & Pairs",
            name: "Singles & Pairs #5",
            groups: [
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 1, value: 9)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 1)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 5)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 7)),
                HandGroup(count: 2, tile: .anySuit(slot: 2, value: 9)),
            ],
            points: 50,
            concealed: true
        ),
        NMJLHand(
            id: "2026_sp_5",
            category: "Singles & Pairs",
            name: "Singles & Pairs #6",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 75,
            concealed: true,
            requireUniqueSuits: true
        ),
        NMJLHand(
            id: "2026_sp_6",
            category: "Singles & Pairs",
            name: "Singles & Pairs #6",
            groups: [
                HandGroup(count: 2, tile: .flower),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 1, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 2, value: 6)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .dragon(value: 3)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 2)),
                HandGroup(count: 1, tile: .anySuit(slot: 3, value: 6)),
            ],
            points: 75,
            concealed: true,
            requireUniqueSuits: true
        ),
    ]

    static let card2026 = NMJLCard(
        id: "nmjl_2026",
        year: .year2026,
        hands: yearHands2026 + evenHands2026 + anyLikeHands2026 + quintHands2026 + consecutiveHands2026 + oddHands2026 + windsDragonsHands2026 + threeSixNineHands2026 + singlesPairsHands2026
    )

    static func cardForYear(_ year: NMJLCardYear) -> NMJLCard {
        switch year {
        case .year2025: return card2025
        case .year2026: return card2026
        }
    }
}
