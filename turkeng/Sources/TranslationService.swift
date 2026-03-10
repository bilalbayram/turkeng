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
    private var serviceBackendTasks: [Task<Void, Never>] = []
    private var appleResult: TranslationMatch?
    private var serviceBackendResults: [String: [TranslationMatch]] = [:]
    private var activeServiceBackendIds: [String] = []
    private var currentRequestText: String?

    func onInputChanged() {
        debounceTask?.cancel()
        cancelServiceBackendTasks()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            matches = []
            selectedIndex = 0
            isTranslating = false
            appleResult = nil
            serviceBackendResults = [:]
            activeServiceBackendIds = []
            currentRequestText = nil
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
        cancelServiceBackendTasks()
        inputText = ""
        translatedText = ""
        matches = []
        selectedIndex = 0
        isTranslating = false
        appleResult = nil
        serviceBackendResults = [:]
        activeServiceBackendIds = []
        currentRequestText = nil
        pendingTranslationText = nil
    }

    /// Detects whether input is Turkish and returns the langpair string for service backends.
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
        guard input.count <= 50, !input.contains("\n") else { return "" }

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
        let langPair = detectLangPair(for: text)
        let targetLanguage = targetLanguage(for: text)
        let serviceBackends = activeServiceBackends(for: backend)

        cancelServiceBackendTasks()
        appleResult = nil
        serviceBackendResults = [:]
        activeServiceBackendIds = serviceBackends.map(\.backendId)
        currentRequestText = text
        pendingTranslationText = nil

        if backend.includesApple {
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

        for serviceBackend in serviceBackends {
            let task = Task { @MainActor in
                let results = await serviceBackend.translate(
                    text: text,
                    langPair: langPair,
                    targetLanguage: targetLanguage
                )
                guard !Task.isCancelled else { return }
                guard currentRequestText == text else { return }
                serviceBackendResults[serviceBackend.backendId] = results
                mergeResults()
            }
            serviceBackendTasks.append(task)
        }

        mergeResults()

        if queryHistory.last != text {
            queryHistory.append(text)
        }
    }

    // MARK: - Apple Translation Callbacks

    @MainActor
    func handleAppleResult(_ targetText: String, for text: String) {
        guard pendingTranslationText == text else { return }

        appleResult = TranslationMatch(
            id: "apple-primary",
            translation: targetText,
            matchScore: 1.0,
            contextHint: partOfSpeech(for: targetText, language: targetLanguage(for: text)),
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

        if let apple = appleResult {
            merged.append(apple)
        }

        let appleTranslationLower = appleResult?.translation.lowercased()
        var seenTranslations = Set(appleTranslationLower.map { [$0] } ?? [])

        for backendId in activeServiceBackendIds {
            guard let backendResults = serviceBackendResults[backendId] else { continue }
            for result in backendResults {
                let translationKey = result.translation.lowercased()
                if seenTranslations.contains(translationKey) {
                    continue
                }
                seenTranslations.insert(translationKey)
                merged.append(result)
            }
        }

        let appleFinished = appleResult != nil || pendingTranslationText == nil
        let serviceBackendsFinished = activeServiceBackendIds.allSatisfy { serviceBackendResults[$0] != nil }

        if let firstResult = appleResult?.translation ?? merged.first?.translation {
            translatedText = firstResult
        } else if appleFinished && serviceBackendsFinished {
            translatedText = "Translation failed"
        }

        matches = merged
        selectedIndex = 0

        if !merged.isEmpty || (appleFinished && serviceBackendsFinished) {
            isTranslating = false
        }
    }

    private func cancelServiceBackendTasks() {
        serviceBackendTasks.forEach { $0.cancel() }
        serviceBackendTasks.removeAll()
    }

    private func activeServiceBackends(for backend: TranslationBackend) -> [any ServiceTranslationBackend] {
        var backends: [any ServiceTranslationBackend] = []
        if backend.includesMyMemory {
            backends.append(MyMemoryBackend())
        }
        if backend.includesGoogle {
            backends.append(GoogleTranslateBackend())
        }
        return backends
    }

    private func targetLanguage(for text: String) -> NLLanguage {
        detectLangPair(for: text) == "tr|en" ? .english : .turkish
    }
}
