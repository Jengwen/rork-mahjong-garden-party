import SwiftUI

/// On-screen seat-flags HUD. Lets the host (or any player) confirm at a glance
/// which seat owns the turn, who is eligible to call, who has responded, and
/// which seats are bots — all without opening the full Diagnostics sheet.
///
/// Tap the small badge to expand the per-seat detail; tap again to collapse.
struct SeatFlagsHUD: View {
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(OnlineGameViewModel.self) private var onlineVM

    @State private var expanded: Bool = false

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 6) {
                header
                if expanded {
                    Divider().background(.white.opacity(0.2))
                    seatRows
                    footer
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.65))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .foregroundStyle(.white)
            .font(.system(.caption2, design: .monospaced))
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Seat flags diagnostic")
        }
    }

    // MARK: - Visibility

    /// Show during play (not Charleston) and only when the underlying state is
    /// meaningful. Hidden in solo non-online single-bot debug runs to keep the
    /// table uncluttered for normal users.
    private var shouldShow: Bool {
        // Hidden from UI per design — kept in code for future diagnostics toggling.
        return false
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.caption2)
            Text("SEATS")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
            Text("turn=\(gameViewModel.currentPlayerIndex)")
            if gameViewModel.isOnlineMode {
                Text("me=\(gameViewModel.localSeatIndex)\(gameViewModel.isOnlineHost ? "*" : "")")
            }
            if gameViewModel.callResponseDiscardId != nil {
                Text("call")
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.6))
                    .clipShape(.rect(cornerRadius: 3))
            }
            Spacer(minLength: 0)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Per-seat rows

    private var seatRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<gameViewModel.players.count, id: \.self) { idx in
                seatRow(idx)
            }
        }
    }

    @ViewBuilder
    private func seatRow(_ idx: Int) -> some View {
        let player = gameViewModel.players[idx]
        let isTurn = gameViewModel.currentPlayerIndex == idx
        let isMe = gameViewModel.isOnlineMode && gameViewModel.localSeatIndex == idx
        let isHostSeat = gameViewModel.isOnlineMode && idx == 0
        let isBot = player.isBot
        let isEligible = gameViewModel.eligibleCallSeats.contains(idx)
        let response = gameViewModel.callResponses[idx]
        let nameSource: String? = gameViewModel.isOnlineMode
            ? onlineVM.currentParticipants.first(where: { $0.seatIndex == idx })?.displayName
            : nil
        let name = nameSource ?? player.profile.displayName

        HStack(spacing: 6) {
            Text("\(idx)")
                .frame(width: 12, alignment: .leading)
                .foregroundStyle(isTurn ? .yellow : .white)
                .fontWeight(isTurn ? .bold : .regular)

            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 70, alignment: .leading)

            flagBadges(isTurn: isTurn, isMe: isMe, isHostSeat: isHostSeat, isBot: isBot, isEligible: isEligible, response: response)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func flagBadges(isTurn: Bool, isMe: Bool, isHostSeat: Bool, isBot: Bool, isEligible: Bool, response: String?) -> some View {
        HStack(spacing: 3) {
            if isTurn { badge("TURN", color: .yellow) }
            if isMe { badge("ME", color: .blue) }
            if isHostSeat { badge("HOST", color: .purple) }
            if isBot { badge("BOT", color: .gray) }
            if isEligible { badge("ELIG", color: .orange) }
            if let response { badge(response.uppercased(), color: response == "called" ? .red : .green) }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.7))
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 3))
    }

    // MARK: - Footer (turn-level flags)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                flag("drawn", gameViewModel.hasDrawnThisTurn)
                flag("await", gameViewModel.awaitingCall)
                flag("avail", gameViewModel.callAvailable)
            }
            if let tile = gameViewModel.lastDiscardedTile {
                Text("last: \(tile.displayName) by seat \(gameViewModel.lastDiscardPlayerIndex.map(String.init) ?? "–")")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func flag(_ label: String, _ on: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(on ? .green : .white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(label)
        }
    }
}
