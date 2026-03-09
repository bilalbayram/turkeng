import SwiftUI

@main
struct TurkengApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("turkeng", systemImage: "character.book.closed") {
            Button("Translate (\(settings.hotkeyModifier.symbol)\(settings.hotkeyLetter.label))") {
                appDelegate.togglePanel()
            }
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            Divider()
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
