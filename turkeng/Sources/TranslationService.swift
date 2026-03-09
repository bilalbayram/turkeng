import AppKit
import Foundation
import NaturalLanguage
import Translation

struct TranslationMatch: Identifiable, Equatable {
    let id: String
    let translation: String
    let matchScore: Double // 0.0–1.0
    let contextHint: String? // "Noun", "Verb", "Adjective", etc.
    let isPrimary: Bool // true = Apple Translation result
}

@Observable
final class TranslationService {
    var inputText: String = ""
    var translatedText: String = ""
    var isTranslating: Bool = false
    var matches: [TranslationMatch] = []
    var selectedIndex: Int = 0
    private(set) var queryHistory: [String] = []

    // Apple Translation integration
    var translationConfig: TranslationSession.Configuration?
    var pendingTranslationText: String?

    private var debounceTask: Task<Void, Never>?
    private var myMemoryTask: Task<Void, Never>?
    private var appleResult: TranslationMatch?
    private var myMemoryResults: [TranslationMatch]?

    func onInputChanged() {
        debounceTask?.cancel()
        myMemoryTask?.cancel()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            matches = []
            selectedIndex = 0
            isTranslating = false
            appleResult = nil
            myMemoryResults = nil
            pendingTranslationText = nil
            return
        }

        translatedText = ""
        matches = []
        selectedIndex = 0
        isTranslating = true

        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await translate(trimmed)
        }
    }

    func reset() {
        debounceTask?.cancel()
        myMemoryTask?.cancel()
        inputText = ""
        translatedText = ""
        matches = []
        selectedIndex = 0
        isTranslating = false
        appleResult = nil
        myMemoryResults = nil
        pendingTranslationText = nil
    }

    /// Detects whether input is Turkish and returns the langpair string for MyMemory.
    func detectLangPair(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage

        if detected == .turkish {
            return "tr|en"
        } else {
            return "en|tr"
        }
    }

    /// Detects source/target as `Locale.Language` for Apple Translation.
    private func detectLanguages(for text: String) -> (source: Locale.Language, target: Locale.Language) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage

        if detected == .turkish {
            return (source: Locale.Language(identifier: "tr"), target: Locale.Language(identifier: "en"))
        } else {
            return (source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "tr"))
        }
    }

    // MARK: - POS Tagging

    private func partOfSpeech(for text: String, language: NLLanguage) -> String? {
        let words = text.split(separator: " ")
        guard words.count <= 3 else { return nil } // skip long phrases

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
            default: return true // skip determiners, punctuation, etc.
            }
        }
        return result
    }

    // MARK: - Navigation

    func selectNext() {
        guard !matches.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, matches.count - 1)
    }

    func selectPrevious() {
        guard !matches.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    // MARK: - Copy

    func copySelected() -> String? {
        guard selectedIndex < matches.count else { return nil }
        let text = matches[selectedIndex].translation
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    // MARK: - Ghost Text Autocomplete

    private static let seedWords: [String] = [
        // Common Turkish words/phrases
        "merhaba", "günaydın", "iyi akşamlar", "iyi geceler", "hoşgeldiniz",
        "teşekkürler", "teşekkür ederim", "nasılsın", "nasıl gidiyor",
        "evet", "hayır", "lütfen", "özür dilerim", "affedersiniz",
        "güzel", "güle güle", "görüşürüz", "arkadaş", "aile",
        "sevgi", "mutlu", "üzgün", "büyük", "küçük",
        "yeni", "eski", "güneş", "yağmur", "kar",
        "su", "yemek", "kahvaltı", "öğle yemeği", "akşam yemeği",
        "çay", "kahve", "ekmek", "peynir", "zeytin",
        "okul", "kitap", "öğrenci", "öğretmen", "çalışmak",
        "başlamak", "bitirmek", "anlamak", "bilmek", "istemek",
        "gelmek", "gitmek", "yapmak", "vermek", "almak",
        "bugün", "yarın", "dün", "şimdi", "sonra",
        // Common English words/phrases
        "hello", "good morning", "good evening", "good night", "welcome",
        "thank you", "thanks", "how are you", "how is it going",
        "yes", "no", "please", "sorry", "excuse me",
        "beautiful", "goodbye", "see you", "friend", "family",
        "love", "happy", "sad", "big", "small",
        "new", "old", "sun", "rain", "snow",
        "water", "food", "breakfast", "lunch", "dinner",
        "tea", "coffee", "bread", "cheese", "olive",
        "school", "book", "student", "teacher", "work",
        "start", "finish", "understand", "know", "want",
        "come", "go", "make", "give", "take",
        "today", "tomorrow", "yesterday", "now", "later",
    ]

    func computeGhostText() -> String {
        let input = inputText
        guard !input.isEmpty else { return "" }

        let normalizedInput = turkishASCIINormalize(input).lowercased()

        // 1. Search history in reverse (most recent first) — personalized
        for entry in queryHistory.reversed() {
            let normalizedEntry = turkishASCIINormalize(entry).lowercased()
            if normalizedEntry.hasPrefix(normalizedInput) && entry.count > input.count {
                let suffixStart = entry.index(entry.startIndex, offsetBy: input.count)
                return String(entry[suffixStart...])
            }
        }

        // 2. Search seed dictionary — works on first launch
        for entry in Self.seedWords {
            let normalizedEntry = turkishASCIINormalize(entry).lowercased()
            if normalizedEntry.hasPrefix(normalizedInput) && entry.count > input.count {
                let suffixStart = entry.index(entry.startIndex, offsetBy: input.count)
                return String(entry[suffixStart...])
            }
        }

        return ""
    }

    @discardableResult
    func acceptGhostText() -> Bool {
        let ghost = computeGhostText()
        guard !ghost.isEmpty else { return false }
        inputText += ghost
        onInputChanged()
        return true
    }

    // MARK: - Turkish ASCII Normalization

    private func turkishASCIINormalize(_ s: String) -> String {
        let map: [Character: Character] = [
            "ç": "c", "Ç": "C", "ğ": "g", "Ğ": "G",
            "ı": "i", "İ": "I", "ö": "o", "Ö": "O",
            "ş": "s", "Ş": "S", "ü": "u", "Ü": "U",
        ]
        return String(s.map { map[$0] ?? $0 })
    }

    // MARK: - Translation Orchestration

    @MainActor
    private func translate(_ text: String) async {
        let langs = detectLanguages(for: text)
        let backend = AppSettings.shared.backend

        // Reset intermediate state
        appleResult = nil
        myMemoryResults = nil
        pendingTranslationText = nil

        // 1. Apple Translation (if enabled and installed)
        if backend != .myMemoryOnly {
            let availability = LanguageAvailability()
            let status = await availability.status(from: langs.source, to: langs.target)

            if status == .installed {
                pendingTranslationText = text
                if translationConfig?.source == langs.source,
                   translationConfig?.target == langs.target {
                    translationConfig?.invalidate()
                } else {
                    translationConfig = .init(source: langs.source, target: langs.target)
                }
            }
        }

        // 2. MyMemory (if enabled)
        if backend != .appleOnly {
            myMemoryTask?.cancel()
            myMemoryTask = Task { @MainActor in
                let results = await fetchMyMemoryAlternatives(text: text)
                guard !Task.isCancelled else { return }
                myMemoryResults = results
                mergeResults()
            }
        } else {
            myMemoryResults = []
        }

        // Append to query history (avoid consecutive duplicates)
        if queryHistory.last != text {
            queryHistory.append(text)
        }
    }

    // MARK: - Apple Translation Callbacks

    @MainActor
    func handleAppleResult(_ targetText: String, for text: String) {
        guard pendingTranslationText == text else { return } // stale result

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let sourceLang = recognizer.dominantLanguage ?? .english
        let hint = partOfSpeech(for: targetText, language: sourceLang == .turkish ? .english : .turkish)

        appleResult = TranslationMatch(
            id: "apple-primary",
            translation: targetText,
            matchScore: 1.0,
            contextHint: hint,
            isPrimary: true
        )
        translatedText = targetText
        pendingTranslationText = nil
        mergeResults()
    }

    @MainActor
    func handleAppleFailure() {
        appleResult = nil
        pendingTranslationText = nil
        mergeResults()
    }

    // MARK: - Result Merging

    @MainActor
    private func mergeResults() {
        var merged: [TranslationMatch] = []

        // Apple result always first
        if let apple = appleResult {
            merged.append(apple)
        }

        // Append MyMemory alternatives, excluding duplicates of Apple's result
        if let mmResults = myMemoryResults {
            let appleTranslationLower = appleResult?.translation.lowercased()
            for m in mmResults {
                if let appleLower = appleTranslationLower,
                   m.translation.lowercased() == appleLower {
                    continue // skip duplicate
                }
                merged.append(m)
            }
        }

        // If both sources completed with nothing, show failure
        let appleFinished = appleResult != nil || pendingTranslationText == nil
        let mmFinished = myMemoryResults != nil
        if merged.isEmpty && appleFinished && mmFinished {
            translatedText = "Translation failed"
        }

        matches = merged
        selectedIndex = 0

        // Mark loading done once we have at least one result or both sources finished
        if !merged.isEmpty || (appleFinished && mmFinished) {
            isTranslating = false
        }
    }

    // MARK: - MyMemory Alternatives

    @MainActor
    private func fetchMyMemoryAlternatives(text: String) async -> [TranslationMatch] {
        let langPair = detectLangPair(for: text)

        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair),
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return [] }

            let response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)

            // Process matches — filter by source segment similarity
            let rawMatches = response.matches ?? []
            let inputLower = text.lowercased()

            let relevant: [MyMemoryResponse.MatchEntry]
            let exactSegment = rawMatches.filter { entry in
                let seg = entry.segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let trans = entry.translation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return seg == inputLower && trans != seg
            }
            if !exactSegment.isEmpty {
                relevant = exactSegment
            } else {
                let highScore = rawMatches.filter { entry in
                    let trans = entry.translation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let seg = entry.segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return entry.matchScore >= 0.85 && trans != seg
                }
                relevant = highScore
            }

            // Detect source language for POS tagging on target text
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let sourceLang = recognizer.dominantLanguage ?? .english
            let targetLang: NLLanguage = sourceLang == .turkish ? .english : .turkish

            var deduped: [String: TranslationMatch] = [:]

            for m in relevant {
                let trimmed = m.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if let existing = deduped[key] {
                    if m.matchScore > existing.matchScore {
                        let hint = partOfSpeech(for: trimmed, language: targetLang)
                        deduped[key] = TranslationMatch(
                            id: m.id, translation: trimmed, matchScore: m.matchScore,
                            contextHint: hint, isPrimary: false
                        )
                    }
                } else {
                    let hint = partOfSpeech(for: trimmed, language: targetLang)
                    deduped[key] = TranslationMatch(
                        id: m.id, translation: trimmed, matchScore: m.matchScore,
                        contextHint: hint, isPrimary: false
                    )
                }
            }

            var sorted = deduped.values.sorted { $0.matchScore > $1.matchScore }
            sorted = Array(sorted.prefix(3))
            return sorted
        } catch {
            return []
        }
    }
}

// MARK: - API Response Models

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    let matches: [MatchEntry]?

    struct ResponseData: Decodable {
        let translatedText: String
    }

    struct MatchEntry: Decodable {
        let id: String
        let segment: String // source text from the translation memory
        let translation: String
        let matchScore: Double

        private enum CodingKeys: String, CodingKey {
            case id, translation, quality, match, source, target, segment
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // id can be String or Int in the API
            if let stringId = try? container.decode(String.self, forKey: .id) {
                id = stringId
            } else if let intId = try? container.decode(Int.self, forKey: .id) {
                id = String(intId)
            } else {
                id = UUID().uuidString
            }

            segment = try container.decodeIfPresent(String.self, forKey: .segment) ?? ""
            translation = try container.decode(String.self, forKey: .translation)

            // match is a Double 0.0–1.0
            if let matchVal = try? container.decode(Double.self, forKey: .match) {
                matchScore = matchVal
            } else if let matchStr = try? container.decode(String.self, forKey: .match),
                      let parsed = Double(matchStr) {
                matchScore = parsed
            } else {
                matchScore = 0.0
            }
        }
    }
}
