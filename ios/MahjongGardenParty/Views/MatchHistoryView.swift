import SwiftUI

struct MatchHistoryView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case wins = "Wins"
        case losses = "Losses"
        case draws = "Draws"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all

    private var filteredMatches: [RecentMatch] {
        switch filter {
        case .all: return appViewModel.recentMatches
        case .wins: return appViewModel.recentMatches.filter { $0.result == .win }
        case .losses: return appViewModel.recentMatches.filter { $0.result == .loss }
        case .draws: return appViewModel.recentMatches.filter { $0.result == .draw }
        }
    }

    private var totalWins: Int { appViewModel.recentMatches.filter { $0.result == .win }.count }
    private var totalLosses: Int { appViewModel.recentMatches.filter { $0.result == .loss }.count }
    private var totalDraws: Int { appViewModel.recentMatches.filter { $0.result == .draw }.count }
    private var winRate: Double {
        let total = appViewModel.recentMatches.count
        guard total > 0 else { return 0 }
        return Double(totalWins) / Double(total)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !appViewModel.recentMatches.isEmpty {
                    statsCard
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if filteredMatches.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMatches) { match in
                            RecentMatchRow(match: match)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Match History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statTile(value: "\(appViewModel.recentMatches.count)", label: "Played", color: themeManager.currentTheme.primary)
            Divider().frame(height: 36)
            statTile(value: "\(totalWins)", label: "Wins", color: .green)
            Divider().frame(height: 36)
            statTile(value: "\(totalLosses)", label: "Losses", color: .red)
            Divider().frame(height: 36)
            statTile(value: "\(Int(winRate * 100))%", label: "Win Rate", color: themeManager.currentTheme.accent)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No matches yet")
                .font(.headline)
            Text("Play a game to see your results here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
