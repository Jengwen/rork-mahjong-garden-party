import SwiftUI

struct CardReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    let card: NMJLCard

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(card.categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category)
                                .font(.system(.headline, design: .serif, weight: .bold))
                                .foregroundStyle(themeManager.currentTheme.primary)
                                .padding(.horizontal)

                            ForEach(card.handsInCategory(category)) { hand in
                                HandCardRow(hand: hand)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(red: 250/255, green: 243/255, blue: 214/255))
            .navigationTitle(card.year.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct HandCardRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let hand: NMJLHand

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(hand.name)
                    .font(.subheadline.bold())

                Spacer()

                HStack(spacing: 4) {
                    Text("\(hand.points) pts")
                        .font(.caption.bold())
                        .foregroundStyle(themeManager.currentTheme.accent)

                    if hand.concealed {
                        Label("Concealed", systemImage: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(hand.groups.enumerated()), id: \.offset) { _, group in
                        HandGroupView(group: group)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct HandGroupView: View {
    @Environment(ThemeManager.self) private var themeManager
    let group: HandGroup

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(0..<max(0, min(group.count, 14))), id: \.self) { _ in
                tileChip
            }
        }
        .padding(.horizontal, 2)
    }

    private var tileChip: some View {
        Text(tileLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tileForeground)
            .frame(width: 22, height: 30)
            .background(tileBackground)
            .clipShape(.rect(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(tileBorder, lineWidth: 0.5)
            )
    }

    private var tileLabel: String {
        switch group.tile {
        case .numbered(_, let value), .anySuit(_, let value):
            return "\(value)"
        case .dragon(let value):
            let labels = ["R", "G", "0"]
            return labels[max(0, min(value - 1, labels.count - 1))]
        case .matchingDragon:
            return "D"
        case .wind(let value):
            let labels = ["E", "S", "W", "N"]
            return labels[max(0, min(value - 1, labels.count - 1))]
        case .flower:
            return "F"
        case .anyWindSlot:
            return "W"
        case .anyDragonSlot:
            return "D"
        case .anyValueAnySuit(_, _, let allowedValues):
            if let first = allowedValues.first { return "\(first)" }
            return "#"
        }
    }

    private var tileForeground: Color {
        switch group.tile {
        case .numbered(let suit, _):
            return suit.color
        case .anySuit(let slot, _):
            return suitSlotColor(slot)
        case .dragon(let value):
            return value == 1 ? .red : value == 2 ? .green : .gray
        case .matchingDragon(let slot):
            return suitSlotColor(slot)
        case .wind:
            return Color(.darkGray)
        case .flower:
            return .pink
        case .anyWindSlot:
            return Color(.darkGray)
        case .anyDragonSlot(let slot):
            return suitSlotColor(slot)
        case .anyValueAnySuit(let suitSlot, _, _):
            return suitSlotColor(suitSlot)
        }
    }

    private func suitSlotColor(_ slot: Int) -> Color {
        switch slot {
        case 1: return .blue
        case 2: return .red
        case 3: return Color(.systemTeal)
        case 4: return .orange
        case 5: return .purple
        case 6: return .brown
        default: return .indigo
        }
    }

    private var tileBackground: Color {
        switch group.tile {
        case .flower:
            return .pink.opacity(0.1)
        case .dragon:
            return Color(.systemGray6)
        case .wind, .anyWindSlot:
            return Color(.systemGray6)
        default:
            return Color(.systemGray6)
        }
    }

    private var tileBorder: Color {
        switch group.tile {
        case .anySuit(let slot, _):
            return suitSlotColor(slot).opacity(0.3)
        case .anyValueAnySuit(let suitSlot, _, _):
            return suitSlotColor(suitSlot).opacity(0.3)
        default:
            return Color(.systemGray4)
        }
    }
}
