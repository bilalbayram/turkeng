import AppKit
import HotKey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()

        hotKey = HotKey(key: .t, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.panelController?.toggle()
        }

        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "turkeng")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Translate (⌥T)", action: #selector(translateAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit turkeng", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func translateAction() {
        panelController?.toggle()
    }
}
