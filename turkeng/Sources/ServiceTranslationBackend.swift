import Foundation
import NaturalLanguage

protocol ServiceTranslationBackend {
    var backendId: String { get }
    func translate(text: String, direction: TranslationDirection) async -> [TranslationMatch]
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
