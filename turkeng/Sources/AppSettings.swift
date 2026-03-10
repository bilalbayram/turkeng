import Foundation

enum TranslationBackend: String, CaseIterable, Identifiable {
    case appleAndMyMemory = "appleAndMyMemory"
    case appleOnly = "appleOnly"
    case myMemoryOnly = "myMemoryOnly"
    case appleAndGoogle = "appleAndGoogle"
    case googleOnly = "googleOnly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleAndMyMemory: "Apple Translation + MyMemory"
        case .appleOnly: "Apple Translation only"
        case .myMemoryOnly: "MyMemory only"
        case .appleAndGoogle: "Apple Translation + Google Translate"
        case .googleOnly: "Google Translate only"
        }
    }

    var includesApple: Bool {
        switch self {
        case .appleAndMyMemory, .appleOnly, .appleAndGoogle:
            true
        case .myMemoryOnly, .googleOnly:
            false
        }
    }

    var includesGoogle: Bool {
        switch self {
        case .appleAndGoogle, .googleOnly:
            true
        case .appleAndMyMemory, .appleOnly, .myMemoryOnly:
            false
        }
    }

    var includesMyMemory: Bool {
        switch self {
        case .appleAndMyMemory, .myMemoryOnly:
            true
        case .appleOnly, .appleAndGoogle, .googleOnly:
            false
        }
    }
}

enum HotkeyModifier: String, CaseIterable, Identifiable {
    case option = "option"
    case command = "command"
    case control = "control"
    case shift = "shift"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .option: "⌥"
        case .command: "⌘"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var label: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        case .control: "Control (⌃)"
        case .shift: "Shift (⇧)"
        }
    }
}

enum HotkeyLetter: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var backend: TranslationBackend {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend") }
    }

    var hotkeyModifier: HotkeyModifier {
        didSet { UserDefaults.standard.set(hotkeyModifier.rawValue, forKey: "hotkeyModifier") }
    }

    var hotkeyLetter: HotkeyLetter {
        didSet { UserDefaults.standard.set(hotkeyLetter.rawValue, forKey: "hotkeyLetter") }
    }

    var googleAPIKey: String {
        didSet { UserDefaults.standard.set(googleAPIKey, forKey: "googleAPIKey") }
    }

    var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    private init() {
        let backendRaw = UserDefaults.standard.string(forKey: "backend") ?? TranslationBackend.appleAndMyMemory.rawValue
        self.backend = TranslationBackend(rawValue: backendRaw) ?? .appleAndMyMemory

        let modRaw = UserDefaults.standard.string(forKey: "hotkeyModifier") ?? HotkeyModifier.option.rawValue
        self.hotkeyModifier = HotkeyModifier(rawValue: modRaw) ?? .option

        let letterRaw = UserDefaults.standard.string(forKey: "hotkeyLetter") ?? HotkeyLetter.t.rawValue
        self.hotkeyLetter = HotkeyLetter(rawValue: letterRaw) ?? .t

        self.googleAPIKey = UserDefaults.standard.string(forKey: "googleAPIKey") ?? ""
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
    }
}
