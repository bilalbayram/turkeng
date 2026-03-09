import AppKit
import HotKey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()

        hotKey = HotKey(key: .t, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.panelController?.toggle()
        }
    }
}
