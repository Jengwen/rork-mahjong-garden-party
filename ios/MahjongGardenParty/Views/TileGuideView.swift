import SwiftUI

struct TileGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    suitSection(title: "Dots", suit: .dot, range: 1...9, dragon: (value: 3, label: "White"))
                    suitSection(title: "Bamboo", suit: .bamboo, range: 1...9, dragon: (value: 2, label: "Green"))
                    suitSection(title: "Cracks", suit: .character, range: 1...9, dragon: (value: 1, label: "Red"))
                    windsSection
                    flowersSection
                    jokersSection
                    tileCountInfo
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(red: 250/255, green: 243/255, blue: 214/255))
            .navigationTitle("Tile Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func suitSection(title: String, suit: TileSuit, range: ClosedRange<Int>, dragon: (value: Int, label: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .foregroundStyle(suit.color)
                Spacer()
                HStack(spacing: 4) {
                    Text("Dragon:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TileView(
                        tile: MahjongTile(suit: .dragon, value: dragon.value),
                        size: .small
                    )
                    Text(dragon.label)
                        .font(.caption2.bold())
                        .foregroundStyle(TileSuit.dragon.color)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(range, id: \.self) { value in
                        VStack(spacing: 3) {
                            TileView(
                                tile: MahjongTile(suit: suit, value: value),
                                size: .compact
                            )
                            Text("\(value)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 2)
            .scrollIndicators(.hidden)

            Text("4 of each number • 4 of each dragon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var windsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Winds")
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(TileSuit.wind.color)

            HStack(spacing: 8) {
                let windLabels = ["East", "South", "West", "North"]
                ForEach(1...4, id: \.self) { value in
                    VStack(spacing: 3) {
                        TileView(
                            tile: MahjongTile(suit: .wind, value: value),
                            size: .compact
                        )
                        Text(windLabels[value - 1])
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text("4 of each wind • 16 total")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var flowersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flowers")
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(TileSuit.flower.color)

            HStack(spacing: 8) {
                ForEach(1...8, id: \.self) { value in
                    VStack(spacing: 3) {
                        TileView(
                            tile: MahjongTile(suit: .flower, value: value),
                            size: .compact
                        )
                        Text("F\(value)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text("8 unique flowers")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var jokersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jokers")
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(TileSuit.joker.color)

            HStack(spacing: 8) {
                TileView(
                    tile: MahjongTile(suit: .joker, value: 1),
                    size: .compact
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wild tile")
                        .font(.caption.bold())
                    Text("Can substitute for any tile in a pung, kong, quint, or sextet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("8 jokers in the set")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var tileCountInfo: some View {
        VStack(spacing: 8) {
            Text("Tile Set Summary")
                .font(.system(.subheadline, design: .serif, weight: .bold))

            let counts: [(String, String, Color)] = [
                ("Dots + White Dragon", "40", TileSuit.dot.color),
                ("Bamboo + Green Dragon", "40", TileSuit.bamboo.color),
                ("Cracks + Red Dragon", "40", TileSuit.character.color),
                ("Winds", "16", TileSuit.wind.color),
                ("Flowers", "8", TileSuit.flower.color),
                ("Jokers", "8", TileSuit.joker.color),
            ]

            ForEach(counts, id: \.0) { name, count, color in
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(name)
                        .font(.caption)
                    Spacer()
                    Text(count)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.caption.bold())
                Spacer()
                Text("152 tiles")
                    .font(.caption.bold())
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }
}
