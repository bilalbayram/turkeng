import AppKit
import HotKey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotKey: HotKey?

    private static let showPanelNotificationName = "com.bilalbayram.turkeng.showPanel"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another copy is already running, tell it to show and quit
        if activateRunningInstanceIfNeeded() {
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()
        registerHotKey()
        observeSettings()
        listenForShowPanelNotification()

        Task { await UpdateChecker.shared.checkOnLaunchIfNeeded() }
    }

    /// Called when the user re-opens the app (e.g. from Dock or Finder)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return false
    }

    // MARK: - Single Instance

    /// Returns true if another instance was found and activated.
    private func activateRunningInstanceIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let others = running.filter { $0 != NSRunningApplication.current }
        guard let existing = others.first else { return false }

        // Tell the existing instance to show its panel
        DistributedNotificationCenter.default().postNotificationName(
            .init(Self.showPanelNotificationName),
            object: nil
        )
        existing.activate()
        return true
    }

    private func listenForShowPanelNotification() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowPanelNotification),
            name: .init(Self.showPanelNotificationName),
            object: nil
        )
    }

    @objc private func handleShowPanelNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.panelController?.show()
        }
    }

    func togglePanel() {
        panelController?.toggle()
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        hotKey = nil // unregister previous

        let settings = AppSettings.shared
        let key = hotkeyLetterToKey(settings.hotkeyLetter)
        let modifiers = hotkeyModifierToFlags(settings.hotkeyModifier)

        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.panelController?.toggle()
        }
    }

    private func observeSettings() {
        let settings = AppSettings.shared
        withObservationTracking {
            _ = settings.hotkeyModifier
            _ = settings.hotkeyLetter
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.registerHotKey()
                self?.observeSettings()
            }
        }
    }

    private func hotkeyLetterToKey(_ letter: HotkeyLetter) -> Key {
        switch letter {
        case .a: .a  case .b: .b  case .c: .c  case .d: .d
        case .e: .e  case .f: .f  case .g: .g  case .h: .h
        case .i: .i  case .j: .j  case .k: .k  case .l: .l
        case .m: .m  case .n: .n  case .o: .o  case .p: .p
        case .q: .q  case .r: .r  case .s: .s  case .t: .t
        case .u: .u  case .v: .v  case .w: .w  case .x: .x
        case .y: .y  case .z: .z
        }
    }

    private func hotkeyModifierToFlags(_ modifier: HotkeyModifier) -> NSEvent.ModifierFlags {
        switch modifier {
        case .option: .option
        case .command: .command
        case .control: .control
        case .shift: .shift
        }
    }
}
