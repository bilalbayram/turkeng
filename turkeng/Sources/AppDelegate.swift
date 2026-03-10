import AppKit
import HotKey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController()
        registerHotKey()
        observeSettings()

        Task { await UpdateChecker.shared.checkOnLaunchIfNeeded() }
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
