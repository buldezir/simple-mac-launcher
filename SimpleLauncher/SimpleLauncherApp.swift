import SwiftUI

@main
struct SimpleLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: SettingsStore.shared)
                .frame(width: 560, height: 480)
        }
    }
}
