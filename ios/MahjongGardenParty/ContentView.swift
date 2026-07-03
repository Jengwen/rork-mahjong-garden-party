import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager
    @State private var selectedTab: AppTab = .home
    @State private var socialVM: SocialViewModel = SocialViewModel()

    var body: some View {
        Group {
            if appViewModel.isCheckingAuth {
                ZStack {
                    Color(red: 250/255, green: 243/255, blue: 214/255)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200)
                        ProgressView()
                    }
                }
            } else if !appViewModel.isAuthenticated {
                AuthView {
                    appViewModel.handleAuthenticated()
                }
            } else {
                mainTabView
            }
        }
        .task {
            await appViewModel.checkAuthStatus()
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(selectedTab: $selectedTab)
            }

            Tab("Play", systemImage: "gamecontroller.fill", value: .play) {
                PlayView()
            }

            Tab("Social", systemImage: "person.2.fill", value: .social) {
                SocialView()
            }
            .badge(socialVM.totalNotificationCount)

            Tab("Shop", systemImage: "bag.fill", value: .shop) {
                ShopView()
            }

            Tab("Profile", systemImage: "person.crop.circle.fill", value: .profile) {
                ProfileView()
            }
        }
        .tint(themeManager.currentTheme.primary)
        .task {
            await socialVM.loadFriends()
            GameInviteWatcher.shared.start()
        }
        .environment(socialVM)
    }
}

enum AppTab: Hashable {
    case home, play, social, shop, profile
}
