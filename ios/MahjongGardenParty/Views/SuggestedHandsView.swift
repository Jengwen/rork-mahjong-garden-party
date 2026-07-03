import SwiftUI

struct SuggestedHandsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(ThemeManager.self) private var themeManager
    @Environment(GameViewModel.self) private var gameViewModel
    @State private var showAllHands: Bool = false
    @State private var analyses: [HandMatcher.HandAnalysis] = []
    @State private var isLoading: Bool = true
    @State private var hasLoaded: Bool = false

    private var topSuggestions: [HandMatcher.HandAnalysis] {
        Array(analyses.prefix(8))
    }

    private var displayedAnalyses: [HandMatcher.HandAnalysis] {
        showAllHands ? analyses : topSuggestions
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    yourTilesSection

                    if isLoading {
                        loadingSection
                    } else if analyses.isEmpty {
                        emptySection
                    } else {
                        toggleSection

                        ForEach(Array(displayedAnalyses.enumerated()), id: \.offset) { index, analysis in
                            SuggestedHandRow(analysis: analysis, rank: index + 1)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(red: 250/255, green: 243/255, blue: 214/255))
            .navigationTitle("Suggested Hands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // On iPhone landscape (compact vertical size class) sheets cannot adopt
        // .medium/.large detents and iOS dismisses them immediately on present —
        // which manifested as the "suggested hands auto-closes on open" bug since
        // the game board locks landscape orientation. Only apply detents when the
        // environment actually supports them (iPad, or any non-compact-vertical).
        .applyDetentsIfSupported(vSizeClass: vSizeClass)
        .presentationContentInteraction(.scrolls)
        .task {
            await loadAnalyses()
        }
    }

    private func loadAnalyses() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let player = gameViewModel.humanPlayer else {
            isLoading = false
            analyses = []
            return
        }
        let hand = player.hand
        let exposed = player.exposedSets
        let card = gameViewModel.activeCard

        // Yield once so the sheet can present before we begin the (capped) analysis.
        await Task.yield()
        guard !Task.isCancelled else { return }

        let result = HandMatcher.analyzeAllHands(playerHand: hand, exposedSets: exposed, card: card)

        guard !Task.isCancelled else { return }
        analyses = result
        isLoading = false
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing hands…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptySection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No suggestions available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var yourTilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(themeManager.currentTheme.primary)
                Text("Your Tiles")
                    .font(.subheadline.bold())
                Spacer()
                if let player = gameViewModel.humanPlayer {
                    Text("\(player.hand.count + player.exposedSets.flatMap { $0 }.count) tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let player = gameViewModel.humanPlayer {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(player.hand) { tile in
                            TileView(tile: tile, size: .small)
                        }
                        if !player.exposedSets.isEmpty {
                            Divider()
                                .frame(height: 24)
                                .padding(.horizontal, 4)
                            ForEach(Array(player.exposedSets.enumerated()), id: \.offset) { _, set in
                                HStack(spacing: 1) {
                                    ForEach(set) { tile in
                                        TileView(tile: tile, size: .small)
                                    }
                                }
                                .padding(2)
                                .background(.ultraThinMaterial)
                                .clipShape(.rect(cornerRadius: 3))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var toggleSection: some View {
        HStack {
            Text(showAllHands ? "All Hands" : "Top \(topSuggestions.count) Closest")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    showAllHands.toggle()
                }
            } label: {
                Text(showAllHands ? "Show Top Only" : "Show All")
                    .font(.caption.bold())
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
        }
        .padding(.horizontal)
    }
}

struct SuggestedHandRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let analysis: HandMatcher.HandAnalysis
    let rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                rankBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.hand.name)
                        .font(.subheadline.bold())
                    Text(analysis.hand.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    tilesNeededBadge
                    HStack(spacing: 4) {
                        Text("\(analysis.hand.points) pts")
                            .font(.caption2.bold())
                            .foregroundStyle(themeManager.currentTheme.accent)
                        if analysis.hand.concealed {
                            Label("C", systemImage: "eye.slash.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.12))
                                .clipShape(.rect(cornerRadius: 3))
                        }
                    }
                }
            }

            progressBar

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(analysis.hand.groups.enumerated()), id: \.offset) { _, group in
                        HandGroupView(group: group)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if !analysis.missingDescriptions.isEmpty && analysis.tilesNeeded > 0 {
                missingTilesSection
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var rankBadge: some View {
        Text("#\(rank)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(rank <= 3 ? .white : .secondary)
            .frame(width: 28, height: 28)
            .background(
                rank == 1 ? Color.yellow.opacity(0.9) :
                rank == 2 ? Color.gray.opacity(0.6) :
                rank == 3 ? Color.orange.opacity(0.7) :
                Color(.tertiarySystemFill)
            )
            .clipShape(Circle())
    }

    private var tilesNeededBadge: some View {
        HStack(spacing: 3) {
            if analysis.tilesNeeded == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Ready!")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.caption2)
                Text("Need \(analysis.tilesNeeded)")
                    .font(.caption.bold())
            }
        }
        .foregroundStyle(analysis.tilesNeeded == 0 ? .green : analysis.tilesNeeded <= 3 ? themeManager.currentTheme.primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            analysis.tilesNeeded == 0
            ? Color.green.opacity(0.1)
            : analysis.tilesNeeded <= 3
            ? themeManager.currentTheme.primary.opacity(0.1)
            : Color(.tertiarySystemFill)
        )
        .clipShape(.rect(cornerRadius: 6))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.tertiarySystemFill))

                RoundedRectangle(cornerRadius: 3)
                    .fill(progressColor)
                    .frame(width: max(0, min(1, analysis.progress)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }

    private var progressColor: Color {
        if analysis.progress >= 1.0 { return .green }
        if analysis.progress >= 0.7 { return themeManager.currentTheme.primary }
        if analysis.progress >= 0.4 { return themeManager.currentTheme.accent }
        return .secondary
    }

    private var missingTilesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Still need:")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(Array(analysis.missingDescriptions.enumerated()), id: \.offset) { _, desc in
                    Text(desc)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
        }
        .padding(.top, 2)
    }
}

private extension View {
    @ViewBuilder
    func applyDetentsIfSupported(vSizeClass: UserInterfaceSizeClass?) -> some View {
        if vSizeClass == .compact {
            // iPhone landscape — let the sheet present as a full modal.
            self
        } else {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (CGSize(width: totalWidth, height: currentY + lineHeight), positions)
    }
}
