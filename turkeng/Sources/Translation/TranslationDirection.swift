import Foundation
import NaturalLanguage

enum TranslationDirection: Equatable {
    case turkishToEnglish
    case englishToTurkish

    var langPair: String {
        switch self {
        case .turkishToEnglish:
            "tr|en"
        case .englishToTurkish:
            "en|tr"
        }
    }

    var sourceCode: String {
        switch self {
        case .turkishToEnglish:
            "tr"
        case .englishToTurkish:
            "en"
        }
    }

    var targetCode: String {
        switch self {
        case .turkishToEnglish:
            "en"
        case .englishToTurkish:
            "tr"
        }
    }

    var sourceLocaleLanguage: Locale.Language {
        Locale.Language(identifier: sourceCode)
    }

    var targetLocaleLanguage: Locale.Language {
        Locale.Language(identifier: targetCode)
    }

    var targetNLLanguage: NLLanguage {
        switch self {
        case .turkishToEnglish:
            .english
        case .englishToTurkish:
            .turkish
        }
    }

    var badgeLabel: String {
        switch self {
        case .turkishToEnglish:
            "TR → EN"
        case .englishToTurkish:
            "EN → TR"
        }
    }

    func reversed() -> TranslationDirection {
        switch self {
        case .turkishToEnglish:
            .englishToTurkish
        case .englishToTurkish:
            .turkishToEnglish
        }
    }

    static func fromDetectedLanguageCode(_ languageCode: String?) -> TranslationDirection {
        switch languageCode?.lowercased() {
        case "tr":
            .turkishToEnglish
        default:
            .englishToTurkish
        }
    }
}
