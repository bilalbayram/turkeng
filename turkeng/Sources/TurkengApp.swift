import SwiftUI

@main
struct TurkengApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("turkeng", systemImage: "character.book.closed", isInserted: $settings.showMenuBarIcon) {
            Button("Translate (\(settings.hotkeyModifier.symbol)\(settings.hotkeyLetter.label))") {
                appDelegate.togglePanel()
            }
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            Button("Check for Updates…") {
                Task { await UpdateChecker.shared.checkForUpdates() }
            }
            Divider()
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .foregroundStyle(.secondary)
            Button("Quit turkeng") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}
