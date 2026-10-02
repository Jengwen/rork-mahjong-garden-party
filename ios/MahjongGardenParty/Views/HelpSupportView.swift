import SwiftUI

struct HelpSupportView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var expandedFAQ: String?

    // MARK: - Contact details
    //
    // App Store Guideline 1.2 requires published contact information so users
    // (and App Review) can reach the developer about objectionable content.
    // ⚠️ This mailbox must actually receive mail before submission — Apple's
    // reviewers do write to it. Change it here and it changes everywhere.
    static let supportEmail = "support@mahjonggardenparty.com"

    private static var supportMailURL: URL {
        URL(string: "mailto:\(supportEmail)?subject=Mahjong%20Garden%20Party%20Support")!
    }

    private static var reportMailURL: URL {
        URL(string: "mailto:\(supportEmail)?subject=Report%20a%20Player%20or%20Content")!
    }

    private static var appStoreReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id6793677304?action=write-review")!
    }

    private let faqs: [(id: String, question: String, answer: String)] = [
        ("faq1", "How do I play Mahjong?",
         "Each player starts with 13 tiles. On your turn, draw a tile from the wall or claim a discard. Arrange your tiles into valid sets (pungs, kongs, quints) to complete a hand from the NMJL card."),
        ("faq2", "What are Jokers used for?",
         "Jokers can substitute for any tile in a pung, kong, or quint. They cannot be used as singles or in pairs. You can exchange a Joker from any exposure if you hold the tile it represents."),
        ("faq3", "What is the Charleston?",
         "The Charleston is a tile-passing phase at the start of each game. Players pass 3 tiles right, then 3 across, then 3 left. An optional courtesy pass of 0-3 tiles follows."),
        ("faq4", "How do I claim a discard?",
         "When another player discards a tile you need for a pung or kong, tap the claim button. For Mahjong, you can claim any discard. Single tiles and pairs from the NMJL card can only be called for Mahjong."),
        ("faq5", "How do I declare Mahjong?",
         "When your hand matches a valid pattern on the NMJL card, the Mahjong button will appear. Tap it to declare and win the round."),
        ("faq6", "What are themes and tile sets?",
         "Themes change the app's color scheme and visual style. Tile sets change the appearance of your Mahjong tiles. Visit the Shop to browse and unlock new options.")
    ]

    var body: some View {
        List {
            Section("Frequently Asked Questions") {
                ForEach(faqs, id: \.id) { faq in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                expandedFAQ = expandedFAQ == faq.id ? nil : faq.id
                            }
                        } label: {
                            HStack {
                                Text(faq.question)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expandedFAQ == faq.id ? 90 : 0))
                            }
                            .padding(.vertical, 4)
                        }

                        if expandedFAQ == faq.id {
                            Text(faq.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }

            Section("Game Rules") {
                Label("NMJL Rules Reference", systemImage: "book.fill")
                    .font(.subheadline)
                Label("Scoring Guide", systemImage: "list.number")
                    .font(.subheadline)
            }

            Section {
                Link(destination: Self.supportMailURL) {
                    Label("Contact Support", systemImage: "envelope.fill")
                        .font(.subheadline)
                }
                Link(destination: Self.reportMailURL) {
                    Label("Report a Player or Content", systemImage: "flag.fill")
                        .font(.subheadline)
                }
                Link(destination: Self.appStoreReviewURL) {
                    Label("Rate the App", systemImage: "star.fill")
                        .font(.subheadline)
                }
            } header: {
                Text("Contact")
            } footer: {
                Text("Questions, bug reports, or concerns about another player — email us at \(Self.supportEmail) and we'll get back to you.")
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
    }
}
