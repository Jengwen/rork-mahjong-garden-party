import SwiftUI
import UniformTypeIdentifiers

struct GameBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(OnlineGameViewModel.self) private var onlineVM
    @State private var showMenu: Bool = false
    @State private var activeSheet: GameBoardSheet?
    // Suggested Hands uses fullScreenCover (not .sheet) because the game board
    // locks landscape on iPhone (compact vertical size class) where SwiftUI
    // sheets misbehave — they were auto-dismissing immediately on present.
    @State private var showSuggestedHands: Bool = false

    @State private var draggedTileID: UUID?
    @State private var draggedFromIndex: Int?
    @State private var hasRecordedResult: Bool = false

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var smallTile: TileSize { isIPad ? .iPadSmall : .small }
    private var compactTile: TileSize { isIPad ? .iPadCompact : .compact }
    private var btnFont: Font { isIPad ? .callout.bold() : .caption.bold() }
    private var btnIconFont: Font { isIPad ? .caption : .caption2 }
    private var btnHPad: CGFloat { isIPad ? 18 : 12 }
    private var btnVPad: CGFloat { isIPad ? 12 : 8 }

    var body: some View {
        // IMPORTANT: keep all presentation modifiers (sheet / confirmationDialog)
        // attached to a STABLE outer container. `mainContent` is a ViewBuilder that
        // switches between CharlestonView and the landscape board based on
        // `gameStatus`. Attaching `.sheet` directly to that conditional caused the
        // sheet to be torn down (and "auto-close upon open") whenever the status
        // flipped — e.g. solo Charleston ending via the bot stop vote.
        ZStack {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            Color(red: 250/255, green: 243/255, blue: 214/255)
                .overlay {
                    Image("game_background")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.15)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
        }
        .confirmationDialog("Game Menu", isPresented: $showMenu) {
            Button("Resume") {}
            Button("Diagnostics") { activeSheet = .diagnostics }
            Button("Leave Game", role: .destructive) { performExit() }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .tileGuide:
                TileGuideView()
            case .diagnostics:
                GameDiagnosticsView()
            }
        }
        .fullScreenCover(isPresented: $showSuggestedHands) {
            SuggestedHandsView()
        }
        .task(id: gameViewModel.isOnlineMode) {
            guard gameViewModel.isOnlineMode else { return }
            // Immediate sync on board entry so an invitee that landed on a stale
            // initial state (e.g. they joined right as the host transitioned out
            // of Charleston) pulls the host's current state right away — instead
            // of waiting the full pull cycle and looking "skipped".
            onlineVM.attachSyncHandlerIfNeeded(gameViewModel: gameViewModel)
            await onlineVM.forceResync(gameViewModel: gameViewModel)
            // Keep the play-phase heartbeats alive even after a transient cancel.
            // The OnlineGameVM's heartbeat tasks can end if the channel
            // briefly reconnects or the app backgrounds — without this watchdog
            // they would never restart and the table would freeze.
            while !Task.isCancelled {
                onlineVM.attachSyncHandlerIfNeeded(gameViewModel: gameViewModel)
                if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
                    if onlineVM.isHost {
                        onlineVM.ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
                    } else {
                        onlineVM.ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
                    }
                    // Auto-recover: if no realtime traffic in a while, ask peers
                    // to re-broadcast their state. Cheap and idempotent.
                    if let at = onlineVM.lastStateUpdateAt,
                       Date().timeIntervalSince(at) > 20 {
                        await onlineVM.forceResync(gameViewModel: gameViewModel)
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if gameViewModel.gameStatus == .charleston {
            CharlestonView(
                onShowSuggestedHands: { showSuggestedHands = true },
                onShowTileGuide: { activeSheet = .tileGuide }
            )
        } else {
            landscapeGameBoard
        }
    }

    private var landscapeGameBoard: some View {
        ZStack {
            tableBackground

            HStack(spacing: 0) {
                leftOpponent
                
                VStack(spacing: 0) {
                    topBarAndOpponent
                    centerArea
                    playerSection
                }
                .frame(maxWidth: .infinity)

                rightOpponent
            }
            .padding(isIPad ? 12 : 8)

            if gameViewModel.showEndGameOverlay {
                endGameOverlay
            }

            if gameViewModel.shouldAutoShowCallPrompt {
                callPromptPopup
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(50)
            }

            VStack {
                HStack {
                    SeatFlagsHUD()
                        .padding(.leading, isIPad ? 60 : 48)
                        .padding(.top, 4)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(true)
        }
    }

    // MARK: - Table Background

    private var tableBackground: some View {
        Color(red: 250/255, green: 243/255, blue: 214/255)
            .overlay {
                Image("game_background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.15)
                    .allowsHitTesting(false)
            }
            .clipped()
            .ignoresSafeArea()
    }

    // MARK: - Top Bar + Across Opponent

    private var topBarAndOpponent: some View {
        HStack(spacing: 0) {
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(isIPad ? .body.bold() : .subheadline.bold())
                    .foregroundStyle(.primary)
                    .frame(width: isIPad ? 44 : 36, height: isIPad ? 44 : 36)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: isIPad ? 10 : 8))
            }

            Spacer()

            if let across = opponentAt(relativeOffset: 1) {
                CompactOpponentView(player: across, isIPad: isIPad)
            }

            Spacer()

            HStack(spacing: isIPad ? 10 : 6) {
                Button { activeSheet = .tileGuide } label: {
                    HStack(spacing: isIPad ? 5 : 3) {
                        Image(systemName: "rectangle.grid.3x2.fill")
                        Text("Tiles")
                    }
                    .font(isIPad ? .caption.bold() : .caption2.bold())
                    .padding(.horizontal, isIPad ? 12 : 8)
                    .padding(.vertical, isIPad ? 8 : 5)
                    .background(themeManager.currentTheme.secondary.opacity(0.15))
                    .foregroundStyle(themeManager.currentTheme.secondary)
                    .clipShape(.rect(cornerRadius: isIPad ? 8 : 6))
                }

                Button { showSuggestedHands = true } label: {
                    HStack(spacing: isIPad ? 5 : 3) {
                        Image(systemName: "lightbulb.fill")
                        Text("Hands")
                    }
                    .font(isIPad ? .caption.bold() : .caption2.bold())
                    .padding(.horizontal, isIPad ? 12 : 8)
                    .padding(.vertical, isIPad ? 8 : 5)
                    .background(themeManager.currentTheme.accent.opacity(0.15))
                    .foregroundStyle(themeManager.currentTheme.accent)
                    .clipShape(.rect(cornerRadius: isIPad ? 8 : 6))
                }

                Label("\(gameViewModel.wallCount)", systemImage: "square.stack.fill")
                Label("\(gameViewModel.discardCount)", systemImage: "tray.fill")
            }
            .font(isIPad ? .caption : .caption2)
            .foregroundStyle(.secondary)

            Button { performExit() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(isIPad ? .body : .subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: isIPad ? 44 : 36, height: isIPad ? 44 : 36)
            }
        }
        .padding(.horizontal, isIPad ? 16 : 12)
        .padding(.top, 4)
    }

    // MARK: - Left / Right Opponents

    private var leftOpponent: some View {
        VStack {
            if let player = opponentAt(relativeOffset: 3) {
                SideOpponentView(player: player, side: .left, isIPad: isIPad)
            }
        }
        .padding(.leading, isIPad ? 8 : 4)
        .offset(x: 32)
    }

    private var rightOpponent: some View {
        VStack {
            if let player = opponentAt(relativeOffset: 2) {
                SideOpponentView(player: player, side: .right, isIPad: isIPad)
            }
        }
        .padding(.trailing, isIPad ? 8 : 4)
        .offset(x: -8)
    }

    /// Returns the opponent at a seat offset relative to the local player.
    /// Offsets: 1 = across, 2 = right, 3 = left. This keeps the host (and every
    /// other player) visible to invitees regardless of which seat they hold.
    private func opponentAt(relativeOffset offset: Int) -> GamePlayer? {
        let local = gameViewModel.localSeatIndex
        let target = ((local + offset) % 4 + 4) % 4
        guard target < gameViewModel.players.count else { return nil }
        let player = gameViewModel.players[target]
        if gameViewModel.isLocalPlayer(player) { return nil }
        return player
    }

    // MARK: - Center Area (Discards + Message)

    private var centerArea: some View {
        VStack(spacing: isIPad ? 10 : 6) {
            Spacer()

            VStack(spacing: 4) {
                Text(gameViewModel.gameMessage)
                    .font(isIPad ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .animation(.smooth, value: gameViewModel.gameMessage)

                if let invalid = gameViewModel.invalidMahjongMessage {
                    Text(invalid)
                        .font(isIPad ? .caption : .caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: gameViewModel.invalidMahjongMessage)

            if let lastTile = gameViewModel.lastDiscardedTile {
                HStack(spacing: 6) {
                    Text("Last:")
                        .font(isIPad ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                    TileView(tile: lastTile, size: smallTile)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            discardPilePreview

            Spacer()
        }
    }

    private var discardPilePreview: some View {
        let allDiscards = gameViewModel.discardPile
        let discardWidth: CGFloat = isIPad ? 44 : 32
        let discardSpacing: CGFloat = isIPad ? 5 : 3
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(discardWidth), spacing: discardSpacing), count: 8), spacing: discardSpacing) {
                ForEach(allDiscards) { tile in
                    DiscardTileView(
                        tile: tile,
                        discardedBy: gameViewModel.discardPlayerMap[tile.id],
                        isIPad: isIPad
                    )
                }
            }
            .padding(.horizontal, isIPad ? 12 : 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: isIPad ? 180 : 120)
    }

    private func playerExposedSets(_ player: GamePlayer) -> some View {
        Group {
            if !player.exposedSets.isEmpty {
                HStack(spacing: isIPad ? 10 : 6) {
                    ForEach(Array(player.exposedSets.enumerated()), id: \.offset) { _, set in
                        HStack(spacing: isIPad ? 2 : 1) {
                            ForEach(set) { tile in
                                TileView(tile: tile, size: smallTile)
                            }
                        }
                        .padding(isIPad ? 5 : 3)
                        .background(.ultraThinMaterial)
                        .clipShape(.rect(cornerRadius: isIPad ? 6 : 4))
                    }
                }
            }
        }
    }

    // MARK: - Player Section (Hand + Actions)

    private var playerSection: some View {
        VStack(spacing: isIPad ? 6 : 4) {
            if let human = gameViewModel.humanPlayer, !human.exposedSets.isEmpty {
                ScrollView(.horizontal) {
                    playerExposedSets(human)
                }
                .contentMargins(.horizontal, isIPad ? 12 : 8)
                .scrollIndicators(.hidden)
                .frame(height: isIPad ? 52 : 34)
            }
            if gameViewModel.showCallTileSelection {
                callSelectionPreview
            }
            playerHand
            actionBar
        }
    }

    private var playerHand: some View {
        ScrollView(.horizontal) {
            HStack(spacing: isIPad ? 4 : 2) {
                if let player = gameViewModel.humanPlayer {
                    ForEach(Array(player.hand.enumerated()), id: \.element.id) { index, tile in
                        TileView(
                            tile: tile,
                            isSelected: gameViewModel.selectedTileIndex == index,
                            size: compactTile
                        )
                        .onDrag {
                            draggedTileID = tile.id
                            draggedFromIndex = index
                            gameViewModel.selectedTileIndex = nil
                            return NSItemProvider(object: tile.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDropDelegate(
                            targetIndex: index,
                            gameViewModel: gameViewModel,
                            draggedTileID: $draggedTileID,
                            draggedFromIndex: $draggedFromIndex
                        ))
                        .overlay(
                            gameViewModel.callSelectedIndices.contains(index) ?
                            RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
                                .fill(themeManager.currentTheme.accent.opacity(0.3))
                                .allowsHitTesting(false)
                            : nil
                        )
                        .offset(y: gameViewModel.showCallTileSelection && gameViewModel.callSelectedIndices.contains(index) ? (isIPad ? -10 : -6) : 0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: gameViewModel.callSelectedIndices.contains(index))
                        .onTapGesture {
                            if gameViewModel.showCallTileSelection {
                                gameViewModel.toggleCallTileSelection(at: index)
                            } else if gameViewModel.gameStatus == .charleston {
                                gameViewModel.toggleCharlestonSelection(at: index)
                            } else {
                                gameViewModel.selectTile(at: index)
                            }
                        }
                    }
                }
            }
        }
        .contentMargins(.horizontal, isIPad ? 12 : 8)
        .scrollIndicators(.hidden)
    }

    private var callSelectionPreview: some View {
        HStack(spacing: isIPad ? 12 : 8) {
            if let discarded = gameViewModel.lastDiscardedTile {
                VStack(spacing: 2) {
                    Text("Called")
                        .font(.system(size: isIPad ? 11 : 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TileView(tile: discarded, size: smallTile)
                }
            }

            Image(systemName: "plus")
                .font(isIPad ? .caption.bold() : .caption2.bold())
                .foregroundStyle(.secondary)

            ForEach(0..<gameViewModel.callRequiredCount, id: \.self) { idx in
                let selectedIndices = Array(gameViewModel.callSelectedIndices.sorted())
                if idx < selectedIndices.count,
                   let player = gameViewModel.humanPlayer,
                   selectedIndices[idx] < player.hand.count {
                    TileView(
                        tile: player.hand[selectedIndices[idx]],
                        size: smallTile
                    )
                    .transition(.scale.combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
                        .strokeBorder(themeManager.currentTheme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .frame(width: isIPad ? 40 : 28, height: isIPad ? 52 : 38)
                }
            }

            if let type = gameViewModel.callTileSelectionType {
                Image(systemName: "arrow.right")
                    .font(isIPad ? .caption.bold() : .caption2.bold())
                    .foregroundStyle(.secondary)

                Text(type.rawValue)
                    .font(isIPad ? .callout.bold() : .caption.bold())
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .padding(.horizontal, isIPad ? 12 : 8)
                    .padding(.vertical, isIPad ? 6 : 4)
                    .background(themeManager.currentTheme.primary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: isIPad ? 8 : 6))
            }
        }
        .padding(.horizontal, isIPad ? 16 : 12)
        .padding(.vertical, isIPad ? 10 : 6)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: isIPad ? 14 : 10))
        .animation(.spring(response: 0.3), value: gameViewModel.callSelectedIndices)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func isCallEligibleTile(_ tile: MahjongTile) -> Bool {
        guard let discarded = gameViewModel.lastDiscardedTile else { return false }
        return tile.matchesForGrouping(discarded) || tile.suit == .joker
    }

    private var actionBar: some View {
        HStack(spacing: isIPad ? 12 : 8) {
            if !gameViewModel.showCallTileSelection {
                standardActions
            }

            if gameViewModel.showCallTileSelection {
                Divider()
                    .frame(height: isIPad ? 32 : 24)

                callButtons
            }

            Spacer()

            Button {
                gameViewModel.declareMahjong()
            } label: {
                Text("Mahjong!")
                    .font(btnFont)
                    .padding(.horizontal, isIPad ? 20 : 14)
                    .padding(.vertical, btnVPad)
                    .background(themeManager.currentTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .sensoryFeedback(.success, trigger: gameViewModel.showMahjongAnimation)
        }
        .padding(.horizontal, isIPad ? 12 : 8)
        .padding(.bottom, isIPad ? 10 : 6)
    }

    private var standardActions: some View {
        HStack(spacing: isIPad ? 12 : 8) {
            Button {
                gameViewModel.drawTile()
            } label: {
                Label("Draw", systemImage: "arrow.down.circle.fill")
                    .font(btnFont)
                    .padding(.horizontal, btnHPad)
                    .padding(.vertical, btnVPad)
                    .background(gameViewModel.canDrawTile
                                ? themeManager.currentTheme.secondary
                                : Color(.tertiarySystemFill))
                    .foregroundStyle(gameViewModel.canDrawTile ? .white : .secondary)
                    .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .disabled(!gameViewModel.canDrawTile)
            .sensoryFeedback(.impact(weight: .light), trigger: gameViewModel.wallCount)

            Button {
                gameViewModel.discardSelectedTile()
            } label: {
                Label("Discard", systemImage: "arrow.up.circle.fill")
                    .font(btnFont)
                    .padding(.horizontal, btnHPad)
                    .padding(.vertical, btnVPad)
                    .background(gameViewModel.selectedTileIndex != nil && gameViewModel.hasDrawnThisTurn
                                ? themeManager.currentTheme.primary
                                : Color(.tertiarySystemFill))
                    .foregroundStyle(gameViewModel.selectedTileIndex != nil && gameViewModel.hasDrawnThisTurn ? .white : .secondary)
                    .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .disabled(gameViewModel.selectedTileIndex == nil || !gameViewModel.hasDrawnThisTurn)
            .sensoryFeedback(.impact(weight: .medium), trigger: gameViewModel.discardCount)

            Divider()
                .frame(height: isIPad ? 32 : 24)

            Button {
                gameViewModel.startJokerSwap()
            } label: {
                HStack(spacing: isIPad ? 6 : 4) {
                    Image(systemName: "star.fill")
                        .font(btnIconFont)
                    Text("Joker Swap")
                        .font(btnFont)
                }
                .padding(.horizontal, isIPad ? 16 : 10)
                .padding(.vertical, btnVPad)
                .background(gameViewModel.jokerSwapMode
                            ? themeManager.currentTheme.accent
                            : themeManager.currentTheme.accent.opacity(0.15))
                .foregroundStyle(gameViewModel.jokerSwapMode ? .white : themeManager.currentTheme.accent)
                .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .sensoryFeedback(.selection, trigger: gameViewModel.jokerSwapMode)

            if gameViewModel.jokerSwapMode {
                Button {
                    gameViewModel.cancelJokerSwap()
                } label: {
                    Text("Cancel")
                        .font(btnFont)
                        .padding(.horizontal, isIPad ? 14 : 8)
                        .padding(.vertical, btnVPad)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    gameViewModel.expandManualCall()
                }
            } label: {
                HStack(spacing: isIPad ? 6 : 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(btnIconFont)
                    Text("Call")
                        .font(btnFont)
                }
                .padding(.horizontal, isIPad ? 16 : 10)
                .padding(.vertical, btnVPad)
                .background(gameViewModel.canUseManualCallButton
                            ? themeManager.currentTheme.accent.opacity(0.15)
                            : Color(.tertiarySystemFill))
                .foregroundStyle(gameViewModel.canUseManualCallButton
                                 ? themeManager.currentTheme.accent
                                 : .secondary)
                .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .disabled(!gameViewModel.canUseManualCallButton)
            .sensoryFeedback(.impact(weight: .light), trigger: gameViewModel.manualCallExpanded)

            // SKIP, shown only for a joker-only call.
            //
            // That case (2+ jokers, no natural match) deliberately SUPPRESSES the
            // auto-popup, so this row is the player's only affordance — and until now it
            // offered "Call" and nothing else. The only way to DECLINE was to open the
            // call popup you didn't want and press Skip *inside* it. A player who didn't
            // know that had no visible way to say no, and no way to even tell the game
            // was waiting on them: the table just sat there.
            //
            // Skip is destructive-ish (it gives up a legal call), so it reads as the
            // quiet, secondary action next to Call rather than competing with it.
            if gameViewModel.canUseManualCallButton {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        gameViewModel.dismissCallOptions()
                    }
                } label: {
                    HStack(spacing: isIPad ? 6 : 4) {
                        Image(systemName: "xmark")
                            .font(btnIconFont)
                        Text("Skip")
                            .font(btnFont)
                    }
                    .padding(.horizontal, isIPad ? 16 : 10)
                    .padding(.vertical, btnVPad)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: gameViewModel.callAvailable)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private var callButtons: some View {
        HStack(spacing: isIPad ? 12 : 8) {
            Button {
                gameViewModel.confirmCallSelection()
            } label: {
                HStack(spacing: isIPad ? 6 : 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(btnIconFont)
                    Text("Confirm")
                        .font(btnFont)
                }
                .padding(.horizontal, btnHPad)
                .padding(.vertical, btnVPad)
                .background(gameViewModel.canConfirmCallSelection
                            ? themeManager.currentTheme.primary
                            : Color(.tertiarySystemFill))
                .foregroundStyle(gameViewModel.canConfirmCallSelection ? .white : .secondary)
                .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
            }
            .disabled(!gameViewModel.canConfirmCallSelection)

            Button {
                gameViewModel.cancelCallSelection()
            } label: {
                Text("Cancel")
                    .font(btnFont)
                    .padding(.horizontal, isIPad ? 16 : 10)
                    .padding(.vertical, btnVPad)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Call Prompt Popup

    private var callPromptPopup: some View {
        VStack {
            VStack(spacing: isIPad ? 12 : 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(isIPad ? .subheadline : .caption)
                        .foregroundStyle(themeManager.currentTheme.accent)
                    Text("Call available")
                        .font(isIPad ? .subheadline.bold() : .caption.bold())
                        .foregroundStyle(.primary)
                    if let tile = gameViewModel.lastDiscardedTile {
                        Text("on")
                            .font(isIPad ? .caption : .caption2)
                            .foregroundStyle(.secondary)
                        TileView(tile: tile, size: isIPad ? .iPadSmall : .small)
                            .scaleEffect(0.85)
                            .frame(height: isIPad ? 36 : 26)
                    }
                }

                HStack(spacing: isIPad ? 10 : 6) {
                    if gameViewModel.availableCalls.contains(.mahjong) {
                        Button {
                            gameViewModel.callTile(type: .mahjong)
                        } label: {
                            HStack(spacing: isIPad ? 6 : 4) {
                                Image(systemName: "sparkles")
                                    .font(btnIconFont)
                                Text("Mahjong")
                                    .font(btnFont)
                            }
                            .padding(.horizontal, btnHPad)
                            .padding(.vertical, btnVPad)
                            .background(themeManager.currentTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                        }
                        .sensoryFeedback(.impact(weight: .heavy), trigger: "mahjong")
                    }

                    let nonMahjong = gameViewModel.availableCalls.filter { $0 != .mahjong }
                    ForEach(nonMahjong, id: \.rawValue) { callType in
                        Button {
                            gameViewModel.beginCallTileSelection(type: callType)
                        } label: {
                            HStack(spacing: isIPad ? 6 : 4) {
                                Image(systemName: "hand.raised.fill")
                                    .font(btnIconFont)
                                Text(callType.rawValue)
                                    .font(btnFont)
                            }
                            .padding(.horizontal, btnHPad)
                            .padding(.vertical, btnVPad)
                            .background(themeManager.currentTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                        }
                    }

                    if gameViewModel.isOnlineMode && !gameViewModel.localCallOnHold {
                        Button {
                            gameViewModel.holdCall()
                        } label: {
                            HStack(spacing: isIPad ? 6 : 4) {
                                Image(systemName: "pause.circle.fill")
                                    .font(btnIconFont)
                                Text("Hold")
                                    .font(btnFont)
                            }
                            .padding(.horizontal, btnHPad)
                            .padding(.vertical, btnVPad)
                            .background(Color.orange.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                        }
                        .sensoryFeedback(.impact(weight: .light), trigger: "hold")
                    }

                    Button {
                        gameViewModel.dismissCallOptions()
                    } label: {
                        Text("Skip")
                            .font(btnFont)
                            .padding(.horizontal, isIPad ? 16 : 10)
                            .padding(.vertical, btnVPad)
                            .background(Color(.tertiarySystemFill))
                            .foregroundStyle(.primary)
                            .clipShape(.rect(cornerRadius: isIPad ? 12 : 10))
                    }
                }

                if gameViewModel.localCallOnHold {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("On hold — take your time, then call or skip")
                            .font(isIPad ? .caption : .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, isIPad ? 18 : 14)
            .padding(.vertical, isIPad ? 14 : 10)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: isIPad ? 18 : 14))
            .overlay(
                RoundedRectangle(cornerRadius: isIPad ? 18 : 14)
                    .strokeBorder(themeManager.currentTheme.accent.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.top, isIPad ? 60 : 44)
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(true)
    }

    // MARK: - End Game Overlay

    private var endGameOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            if gameViewModel.isWallGame {
                wallGameContent
            } else {
                mahjongWinContent
            }
        }
        .transition(.opacity)
    }

    private var isHumanWinner: Bool {
        gameViewModel.winnerName == (gameViewModel.humanPlayer?.profile.displayName ?? "You")
    }

    private var mahjongWinContent: some View {
        VStack(spacing: 16) {
            Text("🎉")
                .font(.system(size: 56))

            Text("MAHJONG!")
                .font(.system(.largeTitle, design: .serif, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [themeManager.currentTheme.accent, themeManager.currentTheme.primary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(isHumanWinner ? "You win!" : "\(gameViewModel.winnerName) wins!")
                .font(.title3)
                .foregroundStyle(.white)

            if let hand = gameViewModel.winningHand {
                VStack(spacing: 6) {
                    Text(hand.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(hand.category) • \(hand.points) points")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.white.opacity(0.15))
                .clipShape(.rect(cornerRadius: 10))
            }

            Button {
                recordGameResultIfNeeded()
                performExit()
            } label: {
                Text("Return to Lobby")
                    .font(.headline)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 14)
                    .background(.white)
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .clipShape(.rect(cornerRadius: 14))
            }
        }
    }

    private var wallGameContent: some View {
        VStack(spacing: 16) {
            Text("🧱")
                .font(.system(size: 56))

            Text("WALL GAME")
                .font(.system(.largeTitle, design: .serif, weight: .black))
                .foregroundStyle(.white)

            Text("No tiles remaining")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))

            Text("Nobody wins this round.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Button {
                recordGameResultIfNeeded()
                performExit()
            } label: {
                Text("Return to Lobby")
                    .font(.headline)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 14)
                    .background(.white)
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .clipShape(.rect(cornerRadius: 14))
            }
        }
    }

    /// Cleanly tears down the active game and dismisses the board. For online games
    /// we MUST call `leaveGame()` first — otherwise lingering realtime broadcasts
    /// keep flipping `currentGame.status`, which the parent's `.onChange` handler
    /// re-presents the board against, trapping the user on the board.
    private func performExit() {
        let wasOnline = gameViewModel.isOnlineMode
        gameViewModel.resetOnlineMode()
        if wasOnline {
            Task { await onlineVM.leaveGame() }
        }
        dismiss()
    }

    private func recordGameResultIfNeeded() {
        guard !hasRecordedResult, gameViewModel.gameStatus == .completed else { return }
        hasRecordedResult = true

        let opponents = gameViewModel.players.filter { !gameViewModel.isLocalPlayer($0) }.map { $0.profile.displayName }
        let humanIsWinner = gameViewModel.winnerName == (gameViewModel.humanPlayer?.profile.displayName ?? "You")

        let result: MatchResult
        let score: Int
        let handName: String?

        if gameViewModel.isWallGame {
            result = .draw
            score = 0
            handName = nil
        } else if humanIsWinner {
            result = .win
            score = gameViewModel.winningHand?.points ?? 0
            handName = gameViewModel.winningHand?.name
        } else {
            result = .loss
            score = 0
            handName = gameViewModel.winningHand?.name
        }

        appViewModel.recordGameResult(
            opponents: opponents,
            result: result,
            score: score,
            gameMode: gameViewModel.gameMode.rawValue,
            winningHandName: handName
        )
    }
}

// MARK: - Tile Drop Delegate

struct TileDropDelegate: DropDelegate {
    let targetIndex: Int
    let gameViewModel: GameViewModel
    @Binding var draggedTileID: UUID?
    @Binding var draggedFromIndex: Int?

    func performDrop(info: DropInfo) -> Bool {
        guard let fromIndex = draggedFromIndex else { return false }
        if fromIndex != targetIndex {
            gameViewModel.moveTileInHand(fromIndex: fromIndex, toIndex: targetIndex)
        }
        draggedTileID = nil
        draggedFromIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromIndex = draggedFromIndex, fromIndex != targetIndex else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            gameViewModel.moveTileInHand(fromIndex: fromIndex, toIndex: targetIndex)
            draggedFromIndex = targetIndex
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTileID != nil
    }
}

// MARK: - Compact Opponent Views

struct CompactOpponentView: View {
    @Environment(ThemeManager.self) private var themeManager
    let player: GamePlayer
    var isIPad: Bool = false

    var body: some View {
        VStack(spacing: isIPad ? 6 : 4) {
            HStack(spacing: isIPad ? 8 : 6) {
                Image(player.profile.avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: isIPad ? 28 : 20, height: isIPad ? 28 : 20)
                    .clipShape(Circle())
                Text(player.profile.displayName)
                    .font(isIPad ? .caption.bold() : .caption2.bold())
                    .lineLimit(1)

                HStack(spacing: isIPad ? 2 : 1) {
                    ForEach(0..<min(player.hand.count, 13), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeManager.currentTheme.primary.opacity(0.5))
                            .frame(width: isIPad ? 7 : 5, height: isIPad ? 14 : 10)
                    }
                }

                if player.isCurrentTurn {
                    Circle()
                        .fill(themeManager.currentTheme.accent)
                        .frame(width: isIPad ? 8 : 6, height: isIPad ? 8 : 6)
                }
            }
            .padding(.horizontal, isIPad ? 14 : 10)
            .padding(.vertical, isIPad ? 8 : 6)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: isIPad ? 10 : 8))

            if !player.exposedSets.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: isIPad ? 6 : 4) {
                        ForEach(Array(player.exposedSets.enumerated()), id: \.offset) { _, set in
                            HStack(spacing: isIPad ? 2 : 1) {
                                ForEach(set) { tile in
                                    TileView(tile: tile, size: isIPad ? .iPadSmall : .small)
                                }
                            }
                            .padding(isIPad ? 4 : 2)
                            .background(.ultraThinMaterial)
                            .clipShape(.rect(cornerRadius: isIPad ? 5 : 3))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: isIPad ? 48 : 30)
            }
        }
    }
}

nonisolated enum SidePosition: Sendable {
    case left, right
}

nonisolated enum GameBoardSheet: String, Identifiable, Sendable {
    case tileGuide
    case diagnostics
    var id: String { rawValue }
}

struct SideOpponentView: View {
    @Environment(ThemeManager.self) private var themeManager
    let player: GamePlayer
    var side: SidePosition = .left
    var isIPad: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: isIPad ? 6 : 4) {
            if side == .right {
                exposedSetsColumn
            }

            VStack(spacing: isIPad ? 5 : 3) {
                Image(player.profile.avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: isIPad ? 40 : 28, height: isIPad ? 40 : 28)
                    .clipShape(Circle())

                Text(player.profile.displayName)
                    .font(.system(size: isIPad ? 12 : 9, weight: .bold))
                    .lineLimit(1)

                if player.isCurrentTurn {
                    Circle()
                        .fill(themeManager.currentTheme.accent)
                        .frame(width: isIPad ? 8 : 6, height: isIPad ? 8 : 6)
                }

                VStack(spacing: isIPad ? 2 : 1) {
                    ForEach(0..<min(player.hand.count, 13), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeManager.currentTheme.primary.opacity(0.5))
                            .frame(width: isIPad ? 20 : 14, height: isIPad ? 7 : 5)
                    }
                }
            }
            .frame(width: isIPad ? 60 : 44)

            if side == .left {
                exposedSetsColumn
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var exposedSetsColumn: some View {
        if !player.exposedSets.isEmpty {
            let tileW: CGFloat = isIPad ? 22 : 16
            let tileH: CGFloat = isIPad ? 30 : 22
            let tileSpacing: CGFloat = isIPad ? 2 : 1
            let setPadding: CGFloat = isIPad ? 3 : 2
            let rotation: Double = side == .left ? 270 : 90

            ScrollView(.vertical) {
                VStack(spacing: isIPad ? 10 : 8) {
                    ForEach(Array(player.exposedSets.enumerated()), id: \.offset) { _, set in
                        let count = CGFloat(set.count)
                        let unrotatedWidth = count * tileW + max(count - 1, 0) * tileSpacing + setPadding * 2
                        let unrotatedHeight = tileH + setPadding * 2

                        HStack(spacing: tileSpacing) {
                            ForEach(set) { tile in
                                TileView(tile: tile, size: isIPad ? .iPadSmall : .small)
                                    .scaleEffect(isIPad ? 0.7 : 0.6)
                                    .frame(width: tileW, height: tileH)
                            }
                        }
                        .padding(setPadding)
                        .background(.ultraThinMaterial)
                        .clipShape(.rect(cornerRadius: isIPad ? 5 : 3))
                        .frame(width: unrotatedWidth, height: unrotatedHeight)
                        .rotationEffect(.degrees(rotation))
                        .frame(width: unrotatedHeight, height: unrotatedWidth)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: isIPad ? 80 : 60, maxHeight: isIPad ? 220 : 150)
        }
    }
}
