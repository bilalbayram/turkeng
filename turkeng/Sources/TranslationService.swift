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
    var currentDirection: TranslationDirection?
    var isDirectionReversed = false
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
            currentDirection = nil
            isDirectionReversed = false
            appleResult = nil
            serviceBackendResults = [:]
            activeServiceBackendIds = []
            currentRequestText = nil
            pendingTranslationText = nil
            return
        }

        currentDirection = previewDirection(for: trimmed)
        prepareForNewTranslation()

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
        currentDirection = nil
        isDirectionReversed = false
        appleResult = nil
        serviceBackendResults = [:]
        activeServiceBackendIds = []
        currentRequestText = nil
        pendingTranslationText = nil
    }

    func detectLocalDirection(for text: String) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage

        if detected == .turkish {
            return .turkishToEnglish
        } else {
            return .englishToTurkish
        }
    }

    func previewDirection(for text: String) -> TranslationDirection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return applyReverseOverride(to: detectLocalDirection(for: trimmed))
    }

    func toggleReverseDirection() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        debounceTask?.cancel()
        cancelServiceBackendTasks()

        isDirectionReversed.toggle()
        currentDirection = previewDirection(for: trimmed)
        prepareForNewTranslation()

        debounceTask = Task { @MainActor in
            await translate(trimmed)
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
        let backend = AppSettings.shared.backend
        let serviceBackends = activeServiceBackends(for: backend)

        cancelServiceBackendTasks()
        appleResult = nil
        serviceBackendResults = [:]
        currentRequestText = text
        pendingTranslationText = nil

        let direction = await resolveDirection(for: text, backend: backend)
        guard !Task.isCancelled else { return }
        guard currentRequestText == text else { return }

        currentDirection = direction
        activeServiceBackendIds = serviceBackends.map(\.backendId)

        if backend.includesApple {
            let availability = LanguageAvailability()
            let status = await availability.status(
                from: direction.sourceLocaleLanguage,
                to: direction.targetLocaleLanguage
            )
            guard !Task.isCancelled else { return }
            guard currentRequestText == text else { return }

            if status == .installed {
                pendingTranslationText = text
                if translationConfig?.source == direction.sourceLocaleLanguage,
                   translationConfig?.target == direction.targetLocaleLanguage {
                    translationConfig?.invalidate()
                } else {
                    translationConfig = .init(
                        source: direction.sourceLocaleLanguage,
                        target: direction.targetLocaleLanguage
                    )
                }
            }
        }

        for serviceBackend in serviceBackends {
            let task = Task { @MainActor in
                let results = await serviceBackend.translate(text: text, direction: direction)
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
            contextHint: partOfSpeech(
                for: targetText,
                language: currentDirection?.targetNLLanguage ?? previewDirection(for: text)?.targetNLLanguage ?? .turkish
            ),
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

    private func prepareForNewTranslation() {
        translatedText = ""
        matches = []
        selectedIndex = 0
        isTranslating = true
        appleResult = nil
        serviceBackendResults = [:]
        activeServiceBackendIds = []
        currentRequestText = nil
        pendingTranslationText = nil
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

    private func applyReverseOverride(to direction: TranslationDirection) -> TranslationDirection {
        isDirectionReversed ? direction.reversed() : direction
    }

    private func resolveDirection(for text: String, backend: TranslationBackend) async -> TranslationDirection {
        let fallback = applyReverseOverride(to: detectLocalDirection(for: text))
        currentDirection = fallback

        guard backend.includesGoogle else { return fallback }

        let googleBackend = GoogleTranslateBackend()
        guard let detected = await googleBackend.detectDirection(for: text) else {
            return fallback
        }

        guard !Task.isCancelled else { return fallback }
        return applyReverseOverride(to: detected)
    }
}
