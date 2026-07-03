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
        }
    }
}
