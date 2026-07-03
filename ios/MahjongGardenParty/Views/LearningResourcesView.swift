import SwiftUI

struct LearningResourcesView: View {
    @Environment(ThemeManager.self) private var themeManager

    private let videos: [VideoResource] = [
        VideoResource(
            title: "How to Play American Mahjong",
            subtitle: "Complete beginner's guide",
            icon: "play.rectangle.fill",
            urlString: "https://www.youtube.com/shorts/QXMz29oyIAs"
        ),
        VideoResource(
            title: "American Mahjong Tiles Explained",
            subtitle: "Get to know each tile in the set",
            icon: "square.grid.3x3.fill",
            urlString: "https://www.youtube.com/shorts/BYhdlm0dUKQ"
        ),
        VideoResource(
            title: "The Charleston Explained",
            subtitle: "Tile passing strategy tips",
            icon: "arrow.triangle.swap",
            urlString: "https://www.youtube.com/shorts/8NJDs1-JzIg"
        ),
        VideoResource(
            title: "Understanding the NMJL Card",
            subtitle: "Learn to read the card of hands",
            icon: "menucard.fill",
            urlString: "https://www.youtube.com/shorts/eKE41OjGjSs"
        ),
        VideoResource(
            title: "Calling, Exposing & Winning",
            subtitle: "Pungs, kongs, quints & Mahjong",
            icon: "hand.raised.fill",
            urlString: "https://www.youtube.com/results?search_query=american+mahjong+calling+exposing+tutorial"
        ),
        VideoResource(
            title: "Tips for New Players",
            subtitle: "Common mistakes and how to improve",
            icon: "lightbulb.fill",
            urlString: "https://www.youtube.com/results?search_query=american+mahjong+tips+for+beginners"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    Label("Video Tutorials", systemImage: "film.stack")
                        .font(.title3.bold())
                        .foregroundStyle(themeManager.currentTheme.primary)

                    ForEach(videos) { video in
                        VideoResourceCard(video: video)
                    }
                }

                tipsSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(red: 250/255, green: 243/255, blue: 214/255).ignoresSafeArea())
        .navigationTitle("Learn to Play")
        .navigationBarTitleDisplayMode(.large)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.and.wrench.fill")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.currentTheme.primary)

            Text("Learning & Resources")
                .font(.title2.bold())

            Text("Everything you need to master American Mahjong, from the basics to advanced strategy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Tips", systemImage: "star.fill")
                .font(.title3.bold())
                .foregroundStyle(themeManager.currentTheme.accent)

            TipRow(icon: "1.circle.fill", text: "Start with Solo Practice mode to learn at your own pace.", color: themeManager.currentTheme.primary)
            TipRow(icon: "2.circle.fill", text: "Use the Card Reference to study winning hands before each game.", color: themeManager.currentTheme.primary)
            TipRow(icon: "3.circle.fill", text: "During the Charleston, pass tiles that don't fit your target hand.", color: themeManager.currentTheme.primary)
            TipRow(icon: "4.circle.fill", text: "Keep your options open early — don't commit to one hand too soon.", color: themeManager.currentTheme.primary)
            TipRow(icon: "5.circle.fill", text: "Watch what others discard to figure out what hands they're building.", color: themeManager.currentTheme.primary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct VideoResource: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let urlString: String
}

struct VideoResourceCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let video: VideoResource

    var body: some View {
        Button {
            if let url = URL(string: video.urlString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: video.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(themeManager.currentTheme.primary)
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(video.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.subheadline)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
