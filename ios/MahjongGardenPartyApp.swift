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
                    // Password-reset links open the app at mahjonggardenparty://reset-callback?code=...
                    // Depending on the exact URL, "reset-callback" can parse as the
                    // host OR the first path component, so accept either — matching
                    // only on scheme + host was letting valid links fall through to
                    // the login screen.
                    let isResetCallback = url.scheme == "mahjonggardenparty"
                        && (url.host == "reset-callback"
                            || url.path.contains("reset-callback")
                            || url.absoluteString.contains("reset-callback"))
                    guard isResetCallback else { return }
                    print("🔑 reset deep link received: \(url.absoluteString)")

                    // Present the new-password screen IMMEDIATELY. Don't gate it on
                    // the session exchange finishing — if that's slow or the screen
                    // only appears on success, the user is left on the login screen
                    // (exactly the reported symptom). The screen itself waits for
                    // the recovery session before it will submit.
                    appViewModel.showSetNewPassword = true
                    Task {
                        do {
                            try await SupabaseService.shared.handlePasswordResetURL(url)
                            print("🔑 recovery session established")
                            appViewModel.recoverySessionReady = true
                        } catch {
                            print("🔑 recovery session failed: \(error)")
                            appViewModel.passwordResetError = error.localizedDescription
                        }
                    }
                }
                .fullScreenCover(isPresented: $appViewModel.showSetNewPassword) {
                    ResetPasswordView {
                        appViewModel.showSetNewPassword = false
                        appViewModel.recoverySessionReady = false
                    }
                    .environment(themeManager)
                    .environment(appViewModel)
                }
        }
    }
}
