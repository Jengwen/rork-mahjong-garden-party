import SwiftUI

struct ShopView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bag.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(themeManager.currentTheme.primary.opacity(0.3))
                    .symbolEffect(.pulse, options: .repeating)

                VStack(spacing: 8) {
                    Text("Coming Soon")
                        .font(.title.bold())

                    Text("Themes, tile sets, and table decor\nwill be available here shortly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Shop")
        }
    }
}
