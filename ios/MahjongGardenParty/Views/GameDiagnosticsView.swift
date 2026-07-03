import SwiftUI
import Combine

/// Game-freeze diagnostics overlay. Shows a snapshot of local + online state and
/// exposes recovery actions (force sync, force-resolve call window, clear stale
/// call UI) so a stuck multiplayer table can be unblocked without restarting.
struct GameDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(OnlineGameViewModel.self) private var onlineVM

    @State private var isWorking: Bool = false
    @State private var lastAction: String?
    @State private var tick: Int = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusBanner

                    section("Game state") {
                        Text(gameViewModel.diagnosticsSnapshot)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if gameViewModel.isOnlineMode {
                        section("Realtime") {
                            Text(onlineVM.diagnosticsSnapshot)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        section("Participants") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(onlineVM.currentParticipants.sorted(by: { $0.seatIndex < $1.seatIndex }), id: \.seatIndex) { p in
                                    Text("seat \(p.seatIndex): \(p.displayName)")
                                        .font(.system(.footnote, design: .monospaced))
                                }
                                if onlineVM.currentParticipants.isEmpty {
                                    Text("no participants loaded")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        recoveryActions
                    }

                    Text("Use these tools only when the game appears stuck or frozen. They re-push your local state to every player and can force the host to advance a stalled call window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(timer) { _ in tick &+= 1 }
        }
    }

    private var statusBanner: some View {
        let frozen = looksFrozen
        return HStack(spacing: 10) {
            Image(systemName: frozen ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(frozen ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(frozen ? "Game may be stuck" : "No obvious issues")
                    .font(.subheadline.bold())
                Text(frozen ? "Try Force Sync, then Resolve Call Window if you're the host." : "Use Force Sync if other players appear out of date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var looksFrozen: Bool {
        guard gameViewModel.isOnlineMode else { return false }
        if let at = onlineVM.lastStateUpdateAt {
            if Date().timeIntervalSince(at) > 20 { return true }
        } else if onlineVM.stateUpdatesReceived == 0 {
            return true
        }
        if gameViewModel.callResponseDiscardId != nil && gameViewModel.isOnlineHost {
            // Host has an open call window — check whether any eligible seat hasn't responded.
            let waiting = gameViewModel.eligibleCallSeats.filter { gameViewModel.callResponses[$0] == nil }
            if !waiting.isEmpty { return true }
        }
        if gameViewModel.canHostForceAdvanceRemoteTurn { return true }
        return false
    }

    private var recoveryActions: some View {
        VStack(spacing: 10) {
            actionButton(
                title: "Force Sync",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .blue
            ) {
                lastAction = "Re-broadcasting state…"
                isWorking = true
                Task {
                    await onlineVM.forceResync(gameViewModel: gameViewModel)
                    lastAction = "State re-broadcast sent."
                    isWorking = false
                }
            }

            if gameViewModel.isOnlineHost {
                actionButton(
                    title: "Force Resolve Call Window",
                    systemImage: "bell.slash.fill",
                    tint: .orange
                ) {
                    lastAction = "Forcing call window to resolve…"
                    gameViewModel.hostForceResolveCallWindow()
                    lastAction = "Call window resolved."
                }
                .disabled(gameViewModel.callResponseDiscardId == nil)
                .opacity(gameViewModel.callResponseDiscardId == nil ? 0.5 : 1)

                actionButton(
                    title: "Force Advance Turn",
                    systemImage: "forward.end.fill",
                    tint: .purple
                ) {
                    lastAction = "Force-advancing stalled seat…"
                    gameViewModel.hostForceAdvanceRemoteTurn()
                    lastAction = "Turn advanced."
                }
                .disabled(!gameViewModel.canHostForceAdvanceRemoteTurn)
                .opacity(gameViewModel.canHostForceAdvanceRemoteTurn ? 1 : 0.5)
            }

            actionButton(
                title: "Clear Local Call UI",
                systemImage: "xmark.circle.fill",
                tint: .secondary
            ) {
                gameViewModel.clearLocalCallWindowState()
                lastAction = "Cleared local call UI."
            }

            if let lastAction {
                Text(lastAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}
