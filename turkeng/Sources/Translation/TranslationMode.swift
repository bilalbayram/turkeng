import Foundation

struct TranslationMode: RawRepresentable, CaseIterable, Identifiable, Equatable, Hashable {
    let rawValue: String
    let label: String
    private let usesAppleTranslation: Bool
    private let serviceProvider: TranslationServiceProvider?

    var id: String { rawValue }

    var requiresGoogleAPIKey: Bool {
        serviceProvider == .google
    }

    init?(rawValue: String) {
        guard let mode = Self.allCases.first(where: { $0.rawValue == rawValue }) else {
            return nil
        }
        self = mode
    }

    private init(
        rawValue: String,
        label: String,
        usesAppleTranslation: Bool,
        serviceProvider: TranslationServiceProvider?
    ) {
        self.rawValue = rawValue
        self.label = label
        self.usesAppleTranslation = usesAppleTranslation
        self.serviceProvider = serviceProvider
    }

    func runtimeSettings(googleAPIKey: String) -> TranslationRuntimeSettings {
        TranslationRuntimeSettings(
            usesAppleTranslation: usesAppleTranslation,
            serviceProvider: serviceProvider,
            googleAPIKey: googleAPIKey
        )
    }

    static let appleWithMyMemory = Self(
        rawValue: "appleAndMyMemory",
        label: "Apple Translation + MyMemory",
        usesAppleTranslation: true,
        serviceProvider: .myMemory
    )
    static let appleOnly = Self(
        rawValue: "appleOnly",
        label: "Apple Translation only",
        usesAppleTranslation: true,
        serviceProvider: nil
    )
    static let myMemoryOnly = Self(
        rawValue: "myMemoryOnly",
        label: "MyMemory only",
        usesAppleTranslation: false,
        serviceProvider: .myMemory
    )
    static let appleWithGoogle = Self(
        rawValue: "appleAndGoogle",
        label: "Apple Translation + Google Translate",
        usesAppleTranslation: true,
        serviceProvider: .google
    )
    static let googleOnly = Self(
        rawValue: "googleOnly",
        label: "Google Translate only",
        usesAppleTranslation: false,
        serviceProvider: .google
    )

    static let allCases: [TranslationMode] = [
        .appleWithMyMemory,
        .appleOnly,
        .myMemoryOnly,
        .appleWithGoogle,
        .googleOnly
    ]
}

struct TranslationRuntimeSettings: Equatable {
    let usesAppleTranslation: Bool
    let serviceProvider: TranslationServiceProvider?
    let googleAPIKey: String

    static let defaultValue = TranslationMode.appleWithMyMemory.runtimeSettings(googleAPIKey: "")

    var trimmedGoogleAPIKey: String? {
        let trimmed = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
