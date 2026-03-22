import Foundation
import NaturalLanguage
import OSLog
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
    private struct AppleTranslationRequest {
        let text: String
        let direction: TranslationDirection
        let configuration: TranslationSession.Configuration
    }

    var inputText: String = ""
    var translatedText: String = ""
    var isTranslating: Bool = false
    var matches: [TranslationMatch] = []
    var selectedIndex: Int = 0
    var currentDirection: TranslationDirection?
    var isDirectionReversed = false
    private(set) var statusMessage: String?

    var appleTranslationConfiguration: TranslationSession.Configuration? {
        appleTranslationRequest?.configuration
    }

    var queryHistory: [String] {
        autocomplete.queryHistory
    }

    private var debounceTask: Task<Void, Never>?
    private var serviceBackendTasks: [Task<Void, Never>] = []
    private var appleResult: TranslationMatch?
    private var appleTranslationRequest: AppleTranslationRequest?
    private var appleFailureMessage: String?
    private var serviceBackendResults: [TranslationServiceProvider: [TranslationMatch]] = [:]
    private var serviceBackendFailures: [TranslationServiceProvider: TranslationBackendError] = [:]
    private var activeServiceProviders: [TranslationServiceProvider] = []
    private var currentRequestText: String?
    private var autocomplete = TranslationAutocomplete()
    private let debounceDuration: Duration
    private let settingsProvider: () -> TranslationRuntimeSettings
    private let backendProvider: (TranslationRuntimeSettings) -> [any TranslationBackend]
    private let clipboardWriter: any TranslationClipboardWriting
    private let languageAvailabilityProvider: () -> LanguageAvailability
    private let logger: Logger

    init(
        debounceDuration: Duration = .milliseconds(300),
        settingsProvider: @escaping () -> TranslationRuntimeSettings,
        backendProvider: @escaping (TranslationRuntimeSettings) -> [any TranslationBackend] =
            TranslationService.liveBackends,
        clipboardWriter: any TranslationClipboardWriting = NoopTranslationClipboardWriter(),
        languageAvailabilityProvider: @escaping () -> LanguageAvailability = { LanguageAvailability() },
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.bilalbayram.turkeng",
            category: "TranslationService"
        )
    ) {
        self.debounceDuration = debounceDuration
        self.settingsProvider = settingsProvider
        self.backendProvider = backendProvider
        self.clipboardWriter = clipboardWriter
        self.languageAvailabilityProvider = languageAvailabilityProvider
        self.logger = logger
    }
}

extension TranslationService {
    func onInputChanged() {
        debounceTask?.cancel()
        cancelActiveTranslation()
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            resetVisibleResults()
            currentDirection = nil
            isDirectionReversed = false
            return
        }

        currentDirection = previewDirection(for: trimmed)
        beginTranslation()

        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }

            await translateNow(trimmed)
        }
    }

    func reset() {
        debounceTask?.cancel()
        cancelActiveTranslation()
        inputText = ""
        resetVisibleResults()
        currentDirection = nil
        isDirectionReversed = false
    }

    func detectDirectionUsingNaturalLanguage(for text: String) -> TranslationDirection {
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
        return applyReverseOverride(to: detectDirectionUsingNaturalLanguage(for: trimmed))
    }

    func toggleReverseDirection() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        debounceTask?.cancel()
        cancelActiveTranslation()

        isDirectionReversed.toggle()
        currentDirection = previewDirection(for: trimmed)
        beginTranslation()

        debounceTask = Task { @MainActor in
            await translateNow(trimmed)
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
        clipboardWriter.copy(text)
        return text
    }

    func computeGhostText() -> String {
        autocomplete.suggestion(for: inputText)
    }

    @discardableResult
    func acceptGhostText() -> Bool {
        let ghost = computeGhostText()
        guard !ghost.isEmpty else { return false }
        inputText += ghost
        onInputChanged()
        return true
    }
}

extension TranslationService {
    // MARK: - Translation Orchestration
    @MainActor
    func translateNow(_ text: String) async {
        let settings = settingsProvider()
        let serviceBackends = backendProvider(settings)

        cancelActiveTranslation()
        currentRequestText = text
        appleFailureMessage = nil
        activeServiceProviders = serviceBackends.map(\.provider)

        let direction = await resolveDirection(for: text, backends: serviceBackends)
        guard !Task.isCancelled else { return }
        guard currentRequestText == text else { return }

        currentDirection = direction
        await prepareAppleTranslationIfNeeded(text: text, direction: direction, settings: settings)
        guard currentRequestText == text else { return }

        for serviceBackend in serviceBackends {
            let task = Task { @MainActor in
                let result = await serviceBackend.translate(text: text, direction: direction)
                guard !Task.isCancelled else { return }
                guard currentRequestText == text else { return }
                handleBackendCompletion(result, from: serviceBackend.provider)
                mergeResults()
            }
            serviceBackendTasks.append(task)
        }

        mergeResults()

        autocomplete.record(text)
    }

    @MainActor
    func performAppleTranslation(using session: TranslationSession) async {
        guard let request = appleTranslationRequest else { return }
        guard currentRequestText == request.text else { return }

        do {
            let response = try await session.translate(request.text)
            guard currentRequestText == request.text else { return }
            applyAppleResult(response.targetText, for: request)
        } catch {
            guard currentRequestText == request.text else { return }
            appleTranslationRequest = nil
            appleResult = nil
            appleFailureMessage = "Apple Translation failed: \(error.localizedDescription)"
            logger.error("Apple Translation request failed: \(error.localizedDescription)")
            mergeResults()
        }
    }

    @MainActor
    private func applyAppleResult(_ targetText: String, for request: AppleTranslationRequest) {
        appleResult = TranslationMatch(
            id: "apple-primary",
            translation: targetText,
            matchScore: 1.0,
            contextHint: partOfSpeech(
                for: targetText,
                language: request.direction.targetNLLanguage
            ),
            isPrimary: true
        )
        translatedText = targetText
        appleFailureMessage = nil
        appleTranslationRequest = nil
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

        for provider in activeServiceProviders {
            guard let backendResults = serviceBackendResults[provider] else { continue }
            for result in backendResults {
                let translationKey = result.translation.lowercased()
                if seenTranslations.contains(translationKey) {
                    continue
                }
                seenTranslations.insert(translationKey)
                merged.append(result)
            }
        }

        let appleFinished = appleResult != nil || appleTranslationRequest == nil
        let serviceBackendsFinished = activeServiceProviders.allSatisfy { serviceBackendResults[$0] != nil }

        if let firstTranslation = appleResult?.translation ?? merged.first?.translation {
            translatedText = firstTranslation
            statusMessage = nil
        } else if appleFinished && serviceBackendsFinished {
            translatedText = ""
            statusMessage = failureMessage() ?? "No translation found."
        }

        matches = merged
        selectedIndex = 0

        if !merged.isEmpty || (appleFinished && serviceBackendsFinished) {
            isTranslating = false
        }
    }

    private func cancelActiveTranslation() {
        serviceBackendTasks.forEach { $0.cancel() }
        serviceBackendTasks.removeAll()
        appleResult = nil
        appleTranslationRequest = nil
        appleFailureMessage = nil
        serviceBackendResults = [:]
        serviceBackendFailures = [:]
        activeServiceProviders = []
        currentRequestText = nil
    }

    private func resetVisibleResults() {
        translatedText = ""
        matches = []
        selectedIndex = 0
        isTranslating = false
        statusMessage = nil
    }

    private func beginTranslation() {
        resetVisibleResults()
        isTranslating = true
    }

    private func applyReverseOverride(to direction: TranslationDirection) -> TranslationDirection {
        isDirectionReversed ? direction.reversed() : direction
    }

    private func resolveDirection(
        for text: String,
        backends: [any TranslationBackend]
    ) async -> TranslationDirection {
        let fallback = applyReverseOverride(to: detectDirectionUsingNaturalLanguage(for: text))
        currentDirection = fallback

        for backend in backends {
            switch await backend.detectDirection(for: text) {
            case .detected(let detectedDirection):
                guard !Task.isCancelled else { return fallback }
                return applyReverseOverride(to: detectedDirection)
            case .unavailable:
                continue
            case .failure(let error):
                guard error != .cancelled else { continue }
                serviceBackendFailures[backend.provider] = error
                logger.error(
                    "Direction detection failed for \(backend.provider.rawValue): \(error.localizedDescription)"
                )
            }
        }

        return fallback
    }

    @MainActor
    private func prepareAppleTranslationIfNeeded(
        text: String,
        direction: TranslationDirection,
        settings: TranslationRuntimeSettings
    ) async {
        guard settings.usesAppleTranslation else {
            appleTranslationRequest = nil
            return
        }

        let availability = languageAvailabilityProvider()
        let status = await availability.status(
            from: direction.sourceLocaleLanguage,
            to: direction.targetLocaleLanguage
        )

        guard !Task.isCancelled else { return }
        guard currentRequestText == text else { return }

        if status == .installed {
            appleTranslationRequest = AppleTranslationRequest(
                text: text,
                direction: direction,
                configuration: .init(
                    source: direction.sourceLocaleLanguage,
                    target: direction.targetLocaleLanguage
                )
            )
            appleFailureMessage = nil
        } else {
            appleTranslationRequest = nil
            appleFailureMessage = "Download the \(direction.badgeLabel) Apple language pack in Settings."
        }
    }

    private func handleBackendCompletion(
        _ result: TranslationBackendTranslationResult,
        from provider: TranslationServiceProvider
    ) {
        switch result {
        case .success(let backendMatches):
            serviceBackendResults[provider] = backendMatches
            serviceBackendFailures.removeValue(forKey: provider)
        case .failure(let error):
            serviceBackendResults[provider] = []
            if error != .cancelled {
                serviceBackendFailures[provider] = error
                logger.error("Translation failed for \(provider.rawValue): \(error.localizedDescription)")
            }
        }
    }

    private func failureMessage() -> String? {
        if let appleFailureMessage, activeServiceProviders.isEmpty {
            return appleFailureMessage
        }

        if activeServiceProviders.count == 1,
           let provider = activeServiceProviders.first,
           let backendFailure = serviceBackendFailures[provider] {
            return "\(provider.label): \(backendFailure.localizedDescription)"
        }

        if let appleFailureMessage, !serviceBackendFailures.isEmpty {
            return appleFailureMessage
        }

        return serviceBackendFailures.first?.value.localizedDescription
    }

    private static func liveBackends(for settings: TranslationRuntimeSettings) -> [any TranslationBackend] {
        guard let serviceProvider = settings.serviceProvider else {
            return []
        }

        switch serviceProvider {
        case .myMemory:
            return [MyMemoryBackend()]
        case .google:
            return [GoogleTranslateBackend(apiKey: settings.trimmedGoogleAPIKey)]
        }
    }
}
