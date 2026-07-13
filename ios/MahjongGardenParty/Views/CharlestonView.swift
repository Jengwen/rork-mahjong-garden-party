import SwiftUI
import UniformTypeIdentifiers

struct CharlestonView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(OnlineGameViewModel.self) private var onlineVM
    @Environment(ThemeManager.self) private var themeManager
    var onShowSuggestedHands: () -> Void
    var onShowTileGuide: () -> Void
    @State private var draggedTileID: UUID?
    @State private var draggedFromIndex: Int?
    @State private var showDiagnostics: Bool = false
    @State private var showExitConfirm: Bool = false

    /// Measured at layout time so sizing follows the space we actually have,
    /// rather than a coarse "is it an iPad" guess. Seeded with a standard iPhone
    /// portrait size so the very first frame is sensible before measurement lands.
    @State private var availableSize: CGSize = CGSize(width: 390, height: 700)

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var L: CharlestonLayout { CharlestonLayout(available: availableSize, isPad: isIPad) }
    private var mediumTile: TileSize { L.tile }
    private var btnFont: Font { isIPad ? .callout.bold() : .caption.bold() }

    /// Layout metrics derived from the real available space.
    ///
    /// The Charleston screen stacks a header, a phase/direction indicator, a
    /// suggested-hands button, a selected-tiles row, the full hand row and a
    /// confirm button — enough vertical content that the previous fixed sizing
    /// (one set of numbers for every iPhone, another for every iPad) overflowed
    /// short screens and clipped the confirm button off the bottom. Anything
    /// shorter than a standard iPhone portrait — an SE, or *any* iPhone in
    /// landscape — hit that. Everything now scales off the measured height.
    struct CharlestonLayout {
        /// How much larger Charleston tiles are than the surrounding chrome's scale.
        static let tileBoost: CGFloat = 1.28

        let tile: TileSize
        let scale: CGFloat
        let hPadding: CGFloat
        let vPadding: CGFloat
        let sectionSpacing: CGFloat
        let tileSpacing: CGFloat
        let isPad: Bool

        init(available: CGSize, isPad: Bool) {
            self.isPad = isPad

            // Height the screen was originally laid out against (standard iPhone
            // portrait content area). Everything scales off the ratio to it.
            let designHeight: CGFloat = 700
            let raw = available.height / max(designHeight, 1)

            // Clamped both ways: the floor keeps tiles tappable (~27pt wide) on a
            // landscape iPhone, the ceiling stops an iPad blowing tiles up past the
            // old .iPadMedium preset they used to be pinned to.
            let s = min(isPad ? 1.4 : 1.0, max(0.62, raw))
            self.scale = s

            // Tiles take the layout scale AND a deliberate boost on top of it.
            //
            // The chrome (header, indicator, buttons, paddings) keeps plain `scale`;
            // only the tiles get `tileBoost`. They're the thing you actually read and
            // tap here — you're picking three specific tiles out of thirteen — and at
            // 1:1 with the chrome they came out no bigger than the play-phase rack,
            // where you're only glancing at them. The horizontal hand row already
            // scrolls, so widening them costs nothing there, and the enclosing
            // ScrollView absorbs the extra height on short screens.
            self.tile = TileSize.fitting(width: TileSize.referenceWidth * s * Self.tileBoost)
            self.tileSpacing = (isPad ? 5 : 3) * s
            self.hPadding = (isPad ? 48 : 32) * min(s, 1.0)
            self.vPadding = (isPad ? 28 : 22) * s
            self.sectionSpacing = (isPad ? 16 : 12) * s
        }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: L.sectionSpacing)
                    if gameViewModel.hasSubmittedCharlestonPass {
                        // Once this player has submitted (including a courtesy pick), keep them on
                        // the "tiles passed" waiting screen no matter what stale broadcasts arrive.
                        waitingForOthersSection
                    } else if gameViewModel.showCourtesyOptions && (!gameViewModel.isOnlineMode || gameViewModel.localSeatIndex == 0) {
                        courtesyOptionsSection
                    } else if gameViewModel.showCourtesyOptions && gameViewModel.isOnlineMode {
                        waitingForEastCourtesySection
                    } else if gameViewModel.charlestonPhase.isCourtesy && gameViewModel.courtesyTileCount > 0 && gameViewModel.isOnlineMode && !gameViewModel.isMyCourtesyTurn {
                        waitingForCourtesyTurnSection
                    } else {
                        directionIndicator
                    }

                    suggestedHandsButton
                    Spacer(minLength: L.sectionSpacing)
                    if !gameViewModel.showCourtesyOptions && !gameViewModel.hasSubmittedCharlestonPass && gameViewModel.isMyCourtesyTurn && !(gameViewModel.charlestonPhase.isCourtesy && gameViewModel.courtesyTileCount > 0 && gameViewModel.isOnlineMode && gameViewModel.courtesyCurrentSeat != gameViewModel.localSeatIndex) {
                        if gameViewModel.requiredTileCount > 0 {
                            selectedTilesPreview
                        }
                        playerHandSection
                        confirmButton
                    }
                }
                .padding(.horizontal, L.hPadding)
                .padding(.vertical, L.vPadding)
                // minHeight makes the stack fill the screen (so the Spacers still
                // centre things) when there IS room, while the enclosing ScrollView
                // catches the cases scaling alone can't save — landscape plus large
                // Dynamic Type — so content is never silently clipped.
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { availableSize = geo.size }
            .onChange(of: geo.size) { _, newSize in availableSize = newSize }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tableBackground)
        .overlay(alignment: .topLeading) {
            diagnosticsOverlay
                .padding(.horizontal, isIPad ? 24 : 12)
                .padding(.top, isIPad ? 12 : 6)
        }
    }

    @ViewBuilder
    private var diagnosticsOverlay: some View {
        if showDiagnostics {
            charlestonDiagnosticsPanel
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation(.spring(response: 0.3)) { showDiagnostics = true }
            } label: {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var charlestonDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "stethoscope").font(.caption2)
                Text("Charleston Diagnostics").font(.caption2.bold())
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) { showDiagnostics = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Group {
                diagRow("Mode", gameViewModel.isOnlineMode ? (gameViewModel.isOnlineHost ? "ONLINE • HOST" : "ONLINE • INVITEE") : "SOLO")
                diagRow("My seat", "\(gameViewModel.localSeatIndex)")
                diagRow("Status", "\(gameViewModel.gameStatus)")
                diagRow("Phase", "\(gameViewModel.charlestonPhase.rawValue) • \(gameViewModel.charlestonPhase.displayName)")
                diagRow("Required", "\(gameViewModel.requiredTileCount)")
                diagRow("Selected", "\(gameViewModel.charlestonSelectedIndices.count)")
                diagRow("My pass", gameViewModel.hasSubmittedCharlestonPass ? "submitted" : "pending")
                diagRow("Pending seats", gameViewModel.charlestonPendingPasses.keys.sorted().map(String.init).joined(separator: ","))
                diagRow("Players", gameViewModel.players.enumerated().map { "\($0.offset)\($0.element.isBot ? "B" : "H")" }.joined(separator: " "))
                diagRow("Courtesy", gameViewModel.showCourtesyOptions ? "chooser" : (gameViewModel.charlestonPhase.isCourtesy ? "turn=\(gameViewModel.courtesyCurrentSeat) count=\(gameViewModel.courtesyTileCount)" : "no"))
                if gameViewModel.isOnlineMode {
                    diagRow("Realtime", onlineVM.realtimeStatus)
                    diagRow("State RX", "\(onlineVM.stateUpdatesReceived)")
                    diagRow("Last RX seat", onlineVM.lastStateUpdateSenderSeat >= 0 ? "\(onlineVM.lastStateUpdateSenderSeat)" : "—")
                    diagRow("Last RX age", lastRxAgeText)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            if gameViewModel.isOnlineMode {
                Button {
                    Task { await onlineVM.forceCharlestonSync(gameViewModel: gameViewModel) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Force Sync")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: isIPad ? 360 : 260, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var lastRxAgeText: String {
        guard let date = onlineVM.lastStateUpdateAt else { return "—" }
        let secs = Int(Date().timeIntervalSince(date))
        return secs < 1 ? "<1s ago" : "\(secs)s ago"
    }

    private var suggestedHandsButton: some View {
        HStack(spacing: (isIPad ? 12 : 8) * L.scale) {
            Button {
                onShowTileGuide()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.grid.3x2.fill")
                    Text("Tile Guide")
                }
                .font(btnFont)
                .padding(.horizontal, isIPad ? 20 : 14)
                .padding(.vertical, (isIPad ? 12 : 8) * L.scale)
                .background(themeManager.currentTheme.secondary.opacity(0.15))
                .foregroundStyle(themeManager.currentTheme.secondary)
                .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }

            Button {
                onShowSuggestedHands()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                    Text("Suggested Hands")
                }
                .font(btnFont)
                .padding(.horizontal, isIPad ? 20 : 14)
                .padding(.vertical, (isIPad ? 12 : 8) * L.scale)
                .background(themeManager.currentTheme.accent.opacity(0.15))
                .foregroundStyle(themeManager.currentTheme.accent)
                .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }

            // Gated on `canStopCharleston`, not the raw flag: the button must vanish
            // on EVERY device the moment any seat commits a 2nd-Charleston pass.
            if gameViewModel.canStopCharleston {
                Button {
                    gameViewModel.stopCharlestonEarly()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.raised.fill")
                        Text("Stop Charleston")
                    }
                    .font(btnFont)
                    .padding(.horizontal, isIPad ? 20 : 14)
                    .padding(.vertical, (isIPad ? 12 : 8) * L.scale)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: gameViewModel.canStopCharleston)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: (isIPad ? 16 : 12) * L.scale) {
            Button {
                showExitConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(isIPad ? .body.bold() : .subheadline.bold())
                    .foregroundStyle(.primary)
                    .frame(width: (isIPad ? 44 : 36) * L.scale, height: (isIPad ? 44 : 36) * L.scale)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit Charleston")

            VStack(alignment: .leading, spacing: 2) {
                Text(gameViewModel.charlestonPhase.groupLabel)
                    .font(isIPad ? .system(.title2, design: .serif, weight: .bold) : .system(.title3, design: .serif, weight: .bold))
                Text("Step \(gameViewModel.charlestonPhase.stepInGroup + 1) of \(gameViewModel.charlestonPhase.totalSteps)")
                    .font(isIPad ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            phaseIndicator
        }
        .padding(.horizontal, (isIPad ? 28 : 20) * L.scale)
        .padding(.top, 12 * L.scale)
        .confirmationDialog("Exit Charleston?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button(gameViewModel.isOnlineMode ? "Leave Game" : "Exit to Lobby", role: .destructive) {
                Task {
                    if gameViewModel.isOnlineMode {
                        await onlineVM.leaveGame()
                    }
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(gameViewModel.isOnlineMode
                 ? "Leaving will end the Charleston for you and return you to the lobby."
                 : "Your current game progress will be lost.")
        }
    }

    private var phaseIndicator: some View {
        HStack(spacing: isIPad ? 8 : 6) {
            ForEach(0..<7, id: \.self) { step in
                let isCurrent = step == gameViewModel.charlestonPhase.rawValue
                let isCompleted = step < gameViewModel.charlestonPhase.rawValue
                let isCourtesy = step == 6

                Circle()
                    .fill(
                        isCompleted
                        ? themeManager.currentTheme.primary
                        : isCurrent
                        ? themeManager.currentTheme.primary.opacity(0.7)
                        : themeManager.currentTheme.primary.opacity(0.15)
                    )
                    .frame(width: isCurrent ? (isIPad ? 16 : 12) : (isIPad ? 10 : 8), height: isCurrent ? (isIPad ? 16 : 12) : (isIPad ? 10 : 8))
                    .overlay {
                        if isCourtesy && !isCompleted && !isCurrent {
                            Circle()
                                .strokeBorder(themeManager.currentTheme.primary.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .animation(.spring(response: 0.3), value: gameViewModel.charlestonPhase)

                if step == 2 || step == 5 {
                    Rectangle()
                        .fill(themeManager.currentTheme.primary.opacity(0.2))
                        .frame(width: 1, height: isIPad ? 16 : 12)
                }
            }
        }
    }

    private var directionIndicator: some View {
        VStack(spacing: L.sectionSpacing) {
            Image(systemName: gameViewModel.charlestonPhase.direction.systemImage)
                .font(.system(size: (isIPad ? 48 : 36) * L.scale, weight: .medium))
                .foregroundStyle(themeManager.currentTheme.primary)
                .symbolEffect(.pulse, options: .repeating)

            Text(gameViewModel.charlestonPhase.displayName)
                .font(isIPad ? .system(.title3, design: .serif) : .system(.headline, design: .serif))
                .foregroundStyle(themeManager.currentTheme.primary)

            Text("Select \(gameViewModel.requiredTileCount) tile\(gameViewModel.requiredTileCount == 1 ? "" : "s") to pass")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
        }
        .padding((isIPad ? 24 : 16) * L.scale)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 20 : 16))
        .padding(.horizontal, (isIPad ? 60 : 40) * L.scale)
    }


    private var courtesyOptionsSection: some View {
        VStack(spacing: (isIPad ? 24 : 20) * L.scale) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: (isIPad ? 48 : 36) * L.scale, weight: .medium))
                .foregroundStyle(themeManager.currentTheme.primary)

            Text("Courtesy Pass")
                .font(isIPad ? .system(.title2, design: .serif, weight: .bold) : .system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(themeManager.currentTheme.primary)

            Text("How many tiles would you like to pass across?")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: (isIPad ? 16 : 12) * L.scale) {
                ForEach(0...3, id: \.self) { count in
                    Button {
                        gameViewModel.selectCourtesyCount(count)
                    } label: {
                        VStack(spacing: (isIPad ? 6 : 4) * L.scale) {
                            Text("\(count)")
                                .font(isIPad ? .system(.title, weight: .bold) : .system(.title2, weight: .bold))
                            Text(count == 0 ? "Skip" : (count == 1 ? "tile" : "tiles"))
                                .font(isIPad ? .caption : .caption2)
                        }
                        .frame(width: (isIPad ? 80 : 64) * L.scale, height: (isIPad ? 80 : 64) * L.scale)
                        .background(
                            count == 0
                            ? Color(.tertiarySystemFill)
                            : themeManager.currentTheme.primary.opacity(0.12)
                        )
                        .foregroundStyle(
                            count == 0
                            ? .secondary
                            : themeManager.currentTheme.primary
                        )
                        .clipShape(.rect(cornerRadius: isIPad ? 18 : 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding((isIPad ? 32 : 24) * L.scale)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 24 : 20))
        .padding(.horizontal, (isIPad ? 48 : 32) * L.scale)
    }

    private var selectedTilesPreview: some View {
        HStack(spacing: (isIPad ? 12 : 8) * L.scale) {
            ForEach(0..<gameViewModel.requiredTileCount, id: \.self) { idx in
                let selectedIndices = Array(gameViewModel.charlestonSelectedIndices.sorted())
                if idx < selectedIndices.count,
                   let player = gameViewModel.humanPlayer,
                   selectedIndices[idx] < player.hand.count {
                    TileView(
                        tile: player.hand[selectedIndices[idx]],
                        size: mediumTile
                    )
                    .transition(.scale.combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: isIPad ? 9 : 7)
                        .strokeBorder(themeManager.currentTheme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: mediumTile.width, height: mediumTile.height)
                }
            }
        }
        .padding(.bottom, (isIPad ? 16 : 12) * L.scale)
        .animation(.spring(response: 0.3), value: gameViewModel.charlestonSelectedIndices)
    }

    private var playerHandSection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: L.tileSpacing) {
                if let player = gameViewModel.humanPlayer {
                    ForEach(Array(player.hand.enumerated()), id: \.element.id) { index, tile in
                        TileView(
                            tile: tile,
                            size: mediumTile,
                            isCharlestonSelected: gameViewModel.charlestonSelectedIndices.contains(index)
                        )
                        .onDrag {
                            draggedTileID = tile.id
                            draggedFromIndex = index
                            return NSItemProvider(object: tile.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDropDelegate(
                            targetIndex: index,
                            gameViewModel: gameViewModel,
                            draggedTileID: $draggedTileID,
                            draggedFromIndex: $draggedFromIndex
                        ))
                        .onTapGesture {
                            gameViewModel.toggleCharlestonSelection(at: index)
                        }
                    }
                }
            }
        }
        .contentMargins(.horizontal, (isIPad ? 20 : 12) * L.scale)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: gameViewModel.charlestonSelectedIndices.count)
    }

    private var confirmButton: some View {
        Button {
            gameViewModel.confirmCharlestonPass()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: gameViewModel.charlestonPhase.direction.systemImage)
                Text("Pass \(gameViewModel.charlestonPhase.direction.rawValue)")
                    .fontWeight(.bold)
            }
            .font(isIPad ? .title3 : .headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, (isIPad ? 18 : 14) * L.scale)
            .background(gameViewModel.canConfirmCharleston
                        ? themeManager.currentTheme.primary
                        : Color(.tertiarySystemFill))
            .foregroundStyle(gameViewModel.canConfirmCharleston ? .white : .secondary)
            .clipShape(.rect(cornerRadius: isIPad ? 16 : 14))
        }
        .disabled(!gameViewModel.canConfirmCharleston)
        .padding(.horizontal, (isIPad ? 32 : 20) * L.scale)
        .padding(.bottom, (isIPad ? 16 : 12) * L.scale)
        .sensoryFeedback(.impact(weight: .medium), trigger: gameViewModel.charlestonPhase)
    }

    private var waitingForOthersSection: some View {
        VStack(spacing: L.sectionSpacing) {
            ProgressView()
                .scaleEffect(isIPad ? 1.4 : 1.1)
                .tint(themeManager.currentTheme.primary)
            Text("Tiles passed")
                .font(isIPad ? .system(.title3, design: .serif, weight: .bold) : .system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(themeManager.currentTheme.primary)
            Text("Waiting for other players to pass their tiles...")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if gameViewModel.isOnlineMode {
                playerSubmissionStatus
                    .padding(.top, isIPad ? 8 : 4)
            }
        }
        .padding((isIPad ? 32 : 24) * L.scale)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 24 : 20))
        .padding(.horizontal, (isIPad ? 48 : 32) * L.scale)
    }

    private var playerSubmissionStatus: some View {
        VStack(spacing: isIPad ? 10 : 8) {
            ForEach(Array(gameViewModel.players.enumerated()), id: \.element.id) { index, player in
                let submitted = gameViewModel.charlestonPendingPasses[index] != nil
                HStack(spacing: isIPad ? 12 : 10) {
                    Image(systemName: submitted ? "checkmark.circle.fill" : "clock")
                        .font(isIPad ? .title3 : .subheadline)
                        .foregroundStyle(submitted ? Color.green : themeManager.currentTheme.primary.opacity(0.5))
                        .symbolEffect(.pulse, options: .repeating, isActive: !submitted)
                    Text(player.profile.displayName)
                        .font(isIPad ? .callout : .footnote)
                        .foregroundStyle(.primary)
                    if player.isBot {
                        Text("Bot")
                            .font(isIPad ? .caption : .caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(themeManager.currentTheme.secondary.opacity(0.15))
                            .foregroundStyle(themeManager.currentTheme.secondary)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                    Text(submitted ? "Passed" : "Picking…")
                        .font(isIPad ? .caption : .caption2)
                        .foregroundStyle(submitted ? .green : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.spring(response: 0.3), value: gameViewModel.charlestonPendingPasses.keys)
    }

    private var waitingForEastCourtesySection: some View {
        VStack(spacing: L.sectionSpacing) {
            ProgressView()
                .scaleEffect(isIPad ? 1.4 : 1.1)
                .tint(themeManager.currentTheme.primary)
            Text("Courtesy Pass")
                .font(isIPad ? .system(.title3, design: .serif, weight: .bold) : .system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(themeManager.currentTheme.primary)
            Text("Waiting for East to choose how many tiles to pass…")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding((isIPad ? 32 : 24) * L.scale)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 24 : 20))
        .padding(.horizontal, (isIPad ? 48 : 32) * L.scale)
    }

    private var waitingForCourtesyTurnSection: some View {
        let currentSeat = gameViewModel.courtesyCurrentSeat
        let name: String = currentSeat < gameViewModel.players.count
            ? gameViewModel.players[currentSeat].profile.displayName
            : "next player"
        return VStack(spacing: L.sectionSpacing) {
            Image(systemName: "hourglass")
                .font(.system(size: (isIPad ? 44 : 32) * L.scale, weight: .medium))
                .foregroundStyle(themeManager.currentTheme.primary)
                .symbolEffect(.pulse, options: .repeating)
            Text("Courtesy Pass")
                .font(isIPad ? .system(.title3, design: .serif, weight: .bold) : .system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(themeManager.currentTheme.primary)
            Text("Waiting for \(name) to pick \(gameViewModel.courtesyTileCount) tile\(gameViewModel.courtesyTileCount == 1 ? "" : "s")…")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            playerSubmissionStatus
                .padding(.top, isIPad ? 8 : 4)
        }
        .padding((isIPad ? 32 : 24) * L.scale)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 24 : 20))
        .padding(.horizontal, (isIPad ? 48 : 32) * L.scale)
    }

    private var tableBackground: some View {
        ZStack {
            themeManager.currentTheme.secondary.opacity(0.1)
                .ignoresSafeArea()
            RadialGradient(
                colors: [
                    themeManager.currentTheme.secondary.opacity(0.06),
                    themeManager.currentTheme.primary.opacity(0.03),
                    Color(.systemBackground).opacity(0.95)
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}
