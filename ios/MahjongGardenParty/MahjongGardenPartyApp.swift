import SwiftUI

@main
struct MahjongGardenPartyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appViewModel = AppViewModel()
    @State private var themeManager = ThemeManager()
    @State private var gameViewModel = GameViewModel()
    @State private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            @Bindable var appViewModel = appViewModel
            ContentView()
                .environment(appViewModel)
                .environment(themeManager)
                .environment(gameViewModel)
                .environment(settingsManager)
                .onAppear {
                    appViewModel.settingsManagerRef = settingsManager
                    settingsManager.onSettingsChanged = { [weak appViewModel] in
                        guard let appViewModel else { return }
                        appViewModel.syncSettingsFromManager(settingsManager)
                    }
                }
                .onOpenURL { url in
                    // Password-reset links open the app at mahjonggardenparty://reset-callback
                    guard url.scheme == "mahjonggardenparty",
                          url.host == "reset-callback" else { return }
                    Task {
                        do {
                            try await SupabaseService.shared.handlePasswordResetURL(url)
                            appViewModel.showSetNewPassword = true
                        } catch {
                            appViewModel.passwordResetError = error.localizedDescription
                        }
                    }
                }
                .fullScreenCover(isPresented: $appViewModel.showSetNewPassword) {
                    ResetPasswordView {
                        appViewModel.showSetNewPassword = false
                    }
                    .environment(themeManager)
                }
        }
    }
}
