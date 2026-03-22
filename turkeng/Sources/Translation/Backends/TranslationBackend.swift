import Foundation
import NaturalLanguage

enum TranslationServiceProvider: String, Identifiable, Equatable {
    case myMemory
    case google

    var id: String { rawValue }

    var label: String {
        switch self {
        case .myMemory:
            "MyMemory"
        case .google:
            "Google Translate"
        }
    }
}

enum TranslationBackendError: Equatable, LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponseStatus(Int)
    case invalidPayload(String)
    case networkFailure(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Google Translate API key in Settings to use Google Translate."
        case .invalidRequest:
            "The translation request could not be created."
        case .invalidResponseStatus(let statusCode):
            "The translation service returned HTTP \(statusCode)."
        case .invalidPayload(let description):
            "The translation response could not be decoded: \(description)"
        case .networkFailure(let description):
            "The translation request failed: \(description)"
        case .cancelled:
            "The translation request was cancelled."
        }
    }
}

enum TranslationBackendTranslationResult: Equatable {
    case success([TranslationMatch])
    case failure(TranslationBackendError)
}

enum TranslationDirectionDetectionResult: Equatable {
    case detected(TranslationDirection)
    case unavailable
    case failure(TranslationBackendError)
}

protocol TranslationBackend {
    var provider: TranslationServiceProvider { get }
    func translate(text: String, direction: TranslationDirection) async -> TranslationBackendTranslationResult
    func detectDirection(for text: String) async -> TranslationDirectionDetectionResult
}

extension TranslationBackend {
    func detectDirection(for text: String) async -> TranslationDirectionDetectionResult {
        .unavailable
    }
}

func partOfSpeech(for text: String, language: NLLanguage) -> String? {
    let words = text.split(separator: " ")
    guard words.count <= 3 else { return nil }

    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text
    tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

    var result: String?
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
        guard let tag else { return true }
        switch tag {
        case .noun: result = "Noun"; return false
        case .verb: result = "Verb"; return false
        case .adjective: result = "Adjective"; return false
        case .adverb: result = "Adverb"; return false
        default: return true
        }
    }
    return result
}
