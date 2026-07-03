//
//  MahjongGardenPartyTests.swift
//  MahjongGardenPartyTests
//
//  Created by Rork on March 29, 2026.
//

import Testing
@testable import MahjongGardenParty

@MainActor
struct MahjongGardenPartyTests {

    // MARK: - Helpers

    private func makeParticipant(seat: Int, name: String = "Player", userId: String = "u") -> GameParticipant {
        GameParticipant(
            id: "p\(seat)",
            gameId: "g1",
            userId: "\(userId)\(seat)",
            seatIndex: seat,
            displayName: "\(name)\(seat)",
            avatarImage: "daffodil",
            createdAt: nil
        )
    }

    // MARK: - startOnlineGame invariants

    @Test func startOnlineGame_assignsAllFourSeats() async throws {
        let vm = GameViewModel()
        // Two human participants in seats 0 and 3, bots fill 1 and 2.
        let participants = [
            makeParticipant(seat: 0, name: "Alice"),
            makeParticipant(seat: 3, name: "Dora"),
        ]

        vm.startOnlineGame(participants: participants)

        #expect(vm.players.count == 4)
        #expect(vm.players.map(\.seatPosition) == [.east, .south, .west, .north])
    }

    @Test func startOnlineGame_placesParticipantsAtCorrectSeats() async throws {
        let vm = GameViewModel()
        let participants = [
            makeParticipant(seat: 2, name: "Bob"),
            makeParticipant(seat: 0, name: "Alice"),
        ]

        vm.startOnlineGame(participants: participants)

        #expect(vm.players[0].profile.displayName == "Alice0")
        #expect(vm.players[0].isBot == false)
        #expect(vm.players[2].profile.displayName == "Bob2")
        #expect(vm.players[2].isBot == false)
        #expect(vm.players[1].isBot)
        #expect(vm.players[3].isBot)
    }

    @Test func startOnlineGame_fillsEmptySeatsWithUniqueBots() async throws {
        let vm = GameViewModel()
        // Only seat 0 occupied, three bots needed.
        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        let bots = vm.players.filter { $0.isBot }
        #expect(bots.count == 3)
        let botNames = Set(bots.map { $0.profile.displayName })
        #expect(botNames == Set(["Lily", "Rose", "Daisy"]))
    }

    @Test func startOnlineGame_dealsThirteenTilesPerPlayer() async throws {
        let vm = GameViewModel()
        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        for player in vm.players {
            #expect(player.hand.count == 13)
        }
    }

    @Test func startOnlineGame_wallHasRemainingTilesAfterDeal() async throws {
        let vm = GameViewModel()
        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        // Full set is 152 tiles, 4 * 13 = 52 dealt, 100 remain.
        let totalTiles = MahjongTile.createFullSet().count
        #expect(vm.wall.count == totalTiles - 52)
        #expect(vm.wall.count == 100)
    }

    @Test func startOnlineGame_dealtTilesAreDisjointFromWall() async throws {
        let vm = GameViewModel()
        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        let handIds = Set(vm.players.flatMap { $0.hand.map(\.id) })
        let wallIds = Set(vm.wall.map(\.id))
        #expect(handIds.intersection(wallIds).isEmpty)
        #expect(handIds.count == 52)
    }

    @Test func startOnlineGame_setsCharlestonStateAndFirstTurn() async throws {
        let vm = GameViewModel()
        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        #expect(vm.gameStatus == .charleston)
        #expect(vm.gameMode == .async)
        #expect(vm.charlestonPhase == .firstRight)
        #expect(vm.charlestonComplete == false)
        #expect(vm.currentPlayerIndex == 0)
        #expect(vm.players[0].isCurrentTurn)
        #expect(vm.discardPile.isEmpty)
        #expect(vm.moveHistory.isEmpty)
    }

    @Test func startOnlineGame_assignsTargetHandsToBotsOnly() async throws {
        let vm = GameViewModel()
        vm.startOnlineGame(participants: [makeParticipant(seat: 1)])

        for player in vm.players {
            if player.isBot {
                #expect(player.targetHand != nil)
            } else {
                #expect(player.targetHand == nil)
            }
        }
    }

    // MARK: - Charleston pass flow

    @Test func toggleCharlestonSelection_capsAtThreeTiles() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        for i in 0..<5 {
            vm.toggleCharlestonSelection(at: i)
        }

        #expect(vm.charlestonSelectedIndices.count == 3)
        #expect(vm.canConfirmCharleston)
    }

    @Test func toggleCharlestonSelection_deselectsWhenTapped() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 0)

        #expect(vm.charlestonSelectedIndices == [1])
        #expect(vm.canConfirmCharleston == false)
    }

    @Test func confirmCharlestonPass_solo_movesTilesRightAndAdvancesPhase() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        let humanIdx = vm.humanPlayerIndex ?? -1
        #expect(humanIdx == 0)
        let receiverIdx = (humanIdx + 1) % 4

        let originalHand = vm.players[humanIdx].hand
        let passingIds = Set([0, 1, 2].map { originalHand[$0].id })

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()

        // Human no longer holds the passed tiles.
        let humanIds = Set(vm.players[humanIdx].hand.map(\.id))
        #expect(humanIds.isDisjoint(with: passingIds))

        // Receiver to the right got all three.
        let receiverIds = Set(vm.players[receiverIdx].hand.map(\.id))
        #expect(passingIds.isSubset(of: receiverIds))

        // Every player still holds 13 tiles.
        for player in vm.players { #expect(player.hand.count == 13) }

        // Phase advanced to 1st Charleston: across.
        #expect(vm.charlestonPhase == .firstAcross)
        #expect(vm.charlestonSelectedIndices.isEmpty)
    }

    @Test func confirmCharlestonPass_solo_threePassesReachStopOption() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        // Three full passes (right → across → left) → showStopCharlestonOption.
        for _ in 0..<3 {
            vm.toggleCharlestonSelection(at: 0)
            vm.toggleCharlestonSelection(at: 1)
            vm.toggleCharlestonSelection(at: 2)
            vm.confirmCharlestonPass()
        }

        #expect(vm.charlestonPhase == .secondLeft)
        #expect(vm.showStopCharlestonOption)
        #expect(vm.gameStatus == .charleston)
    }

    @Test func confirmCharlestonPass_solo_secondCharlestonReversesDirection() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        let humanIdx = vm.humanPlayerIndex ?? -1
        #expect(humanIdx == 0)

        // Walk through the first Charleston (right → across → left). The phase that
        // matters is the transition from .firstLeft → .secondLeft, which is the
        // direction "reversal" — both phases pass to the left, then the second
        // Charleston winds back across → right.
        let expectedAfterEachPass: [CharlestonPhase] = [.firstAcross, .firstLeft, .secondLeft]
        for expected in expectedAfterEachPass {
            vm.toggleCharlestonSelection(at: 0)
            vm.toggleCharlestonSelection(at: 1)
            vm.toggleCharlestonSelection(at: 2)
            vm.confirmCharlestonPass()
            #expect(vm.charlestonPhase == expected)
        }

        // First Charleston complete; second Charleston now begins by passing LEFT,
        // i.e. the reversal of the first Charleston's final direction order.
        #expect(vm.charlestonPhase == .secondLeft)
        #expect(vm.charlestonPhase.direction == .left)
        #expect(vm.charlestonPhase.isSecondCharleston)
        #expect(vm.showStopCharlestonOption)

        // Capture the human's pass and confirm it lands on the LEFT neighbor (i+3)%4.
        vm.continueCharleston() // dismiss the optional stop prompt
        let leftNeighborIdx = (humanIdx + 3) % 4
        let preHand = vm.players[humanIdx].hand
        let passingIds = Set([0, 1, 2].map { preHand[$0].id })

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()

        let leftIds = Set(vm.players[leftNeighborIdx].hand.map(\.id))
        #expect(passingIds.isSubset(of: leftIds))
        #expect(vm.charlestonPhase == .secondAcross)

        // And the second Charleston winds back to the right on its final leg.
        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()
        #expect(vm.charlestonPhase == .secondRight)
        #expect(vm.charlestonPhase.direction == .right)
    }

    @Test func stopCharlestonEarly_finishesCharleston() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        vm.stopCharlestonEarly()

        #expect(vm.charlestonComplete)
        #expect(vm.gameStatus == .playing)
        #expect(vm.showStopCharlestonOption == false)
    }

    @Test func selectCourtesyCount_zero_finishesCharleston() async throws {
        let vm = GameViewModel()
        vm.startNewGame(mode: .solo)

        vm.selectCourtesyCount(0)

        #expect(vm.charlestonComplete)
        #expect(vm.gameStatus == .playing)
        #expect(vm.showCourtesyOptions == false)
    }

    @Test func confirmCharlestonPass_online_nonHostBuffersAndDoesNotFinalize() async throws {
        let vm = GameViewModel()
        vm.isOnlineMode = true
        vm.localSeatIndex = 0 // non-host (host is seat 3)
        vm.startOnlineGame(participants: [makeParticipant(seat: 0, name: "Alice")])

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()

        // Local seat's tiles are buffered, no exchange yet.
        #expect(vm.charlestonPendingPasses[0]?.count == 3)
        #expect(vm.players[0].hand.count == 10)
        #expect(vm.charlestonPhase == .firstRight)
        #expect(vm.hasSubmittedCharlestonPass)
    }

    @Test func confirmCharlestonPass_online_hostFinalizesAfterAllSubmit() async throws {
        let vm = GameViewModel()
        vm.isOnlineMode = true
        vm.localSeatIndex = 3 // host
        vm.startOnlineGame(participants: [makeParticipant(seat: 3, name: "Host")])

        let originalHostHand = vm.players[3].hand
        let passingIds = Set([0, 1, 2].map { originalHostHand[$0].id })

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass() // host's submission triggers finalize since other seats are bots

        // Host's tiles ended up at the seat to the right (seat 0 wraps from seat 3).
        let receiverIds = Set(vm.players[0].hand.map(\.id))
        #expect(passingIds.isSubset(of: receiverIds))

        // Every player still holds 13, pending passes cleared, phase advanced.
        for player in vm.players { #expect(player.hand.count == 13) }
        #expect(vm.charlestonPendingPasses.isEmpty)
        #expect(vm.charlestonPhase == .firstAcross)
    }

    @Test func confirmCharlestonPass_online_secondCharlestonReversesDirection() async throws {
        let vm = GameViewModel()
        vm.isOnlineMode = true
        vm.localSeatIndex = 3 // host
        vm.startOnlineGame(participants: [makeParticipant(seat: 3, name: "Host")])

        // Three host passes finalize the 1st Charleston (right → across → left).
        let expectedAfterEachPass: [CharlestonPhase] = [.firstAcross, .firstLeft, .secondLeft]
        for expected in expectedAfterEachPass {
            vm.toggleCharlestonSelection(at: 0)
            vm.toggleCharlestonSelection(at: 1)
            vm.toggleCharlestonSelection(at: 2)
            vm.confirmCharlestonPass()
            #expect(vm.charlestonPhase == expected)
            #expect(vm.charlestonPendingPasses.isEmpty)
        }

        // Reversal point: 2nd Charleston starts going LEFT, mirroring the 1st's last leg.
        #expect(vm.charlestonPhase == .secondLeft)
        #expect(vm.charlestonPhase.direction == .left)
        #expect(vm.charlestonPhase.isSecondCharleston)
        #expect(vm.showStopCharlestonOption)

        // Host passes 3 tiles LEFT — receiver of seat 3's pass is (3+3)%4 = 2.
        vm.continueCharleston()
        let preHostHand = vm.players[3].hand
        let passingIds = Set([0, 1, 2].map { preHostHand[$0].id })

        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()

        let leftReceiverIds = Set(vm.players[2].hand.map(\.id))
        #expect(passingIds.isSubset(of: leftReceiverIds))
        #expect(vm.charlestonPhase == .secondAcross)
        for player in vm.players { #expect(player.hand.count == 13) }

        // Final leg of 2nd Charleston winds back to the right.
        vm.toggleCharlestonSelection(at: 0)
        vm.toggleCharlestonSelection(at: 1)
        vm.toggleCharlestonSelection(at: 2)
        vm.confirmCharlestonPass()
        #expect(vm.charlestonPhase == .secondRight)
        #expect(vm.charlestonPhase.direction == .right)
    }

    @Test func startOnlineGame_resetsStaleStateFromPriorGame() async throws {
        let vm = GameViewModel()
        // Simulate stale state from a previous round.
        vm.discardPile = [MahjongTile(suit: .bamboo, value: 1)]
        vm.moveHistory = [GameMove(playerId: UUID(), moveType: .discard, tiles: [])]
        vm.charlestonComplete = true
        vm.showEndGameOverlay = true
        vm.winnerName = "Old Winner"
        vm.isWallGame = true

        vm.startOnlineGame(participants: [makeParticipant(seat: 0)])

        #expect(vm.discardPile.isEmpty)
        #expect(vm.moveHistory.isEmpty)
        #expect(vm.charlestonComplete == false)
        #expect(vm.showEndGameOverlay == false)
        #expect(vm.winnerName == "")
        #expect(vm.isWallGame == false)
    }
}
