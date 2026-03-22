import Foundation

enum HotkeyModifier: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift

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

// swiftlint:disable identifier_name
enum HotkeyLetter: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}
// swiftlint:enable identifier_name

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private static let translationEngineKey = "translationEngine"
    private static let legacyBackendKey = "backend"
    private let userDefaults: UserDefaults

    var translationMode: TranslationMode {
        didSet { userDefaults.set(translationMode.rawValue, forKey: Self.translationEngineKey) }
    }

    var hotkeyModifier: HotkeyModifier {
        didSet { userDefaults.set(hotkeyModifier.rawValue, forKey: "hotkeyModifier") }
    }

    var hotkeyLetter: HotkeyLetter {
        didSet { userDefaults.set(hotkeyLetter.rawValue, forKey: "hotkeyLetter") }
    }

    var googleAPIKey: String {
        didSet { userDefaults.set(googleAPIKey, forKey: "googleAPIKey") }
    }

    var showMenuBarIcon: Bool {
        didSet { userDefaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    var translationSettings: TranslationRuntimeSettings {
        translationMode.runtimeSettings(googleAPIKey: googleAPIKey)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let engineRawValue = userDefaults.string(forKey: Self.translationEngineKey)
            ?? userDefaults.string(forKey: Self.legacyBackendKey)
            ?? TranslationMode.appleWithMyMemory.rawValue
        self.translationMode = TranslationMode(rawValue: engineRawValue) ?? .appleWithMyMemory

        let modRaw = userDefaults.string(forKey: "hotkeyModifier") ?? HotkeyModifier.option.rawValue
        self.hotkeyModifier = HotkeyModifier(rawValue: modRaw) ?? .option

        let letterRaw = userDefaults.string(forKey: "hotkeyLetter") ?? HotkeyLetter.t.rawValue
        self.hotkeyLetter = HotkeyLetter(rawValue: letterRaw) ?? .t

        self.googleAPIKey = userDefaults.string(forKey: "googleAPIKey") ?? ""
        self.showMenuBarIcon = userDefaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
    }
}
