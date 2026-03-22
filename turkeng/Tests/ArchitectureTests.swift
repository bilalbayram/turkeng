import Foundation
import Testing
@testable import turkeng

struct ArchitectureTests {
    @Test
    @MainActor
    func translationServiceUsesInjectedBackendContracts() async {
        let backend = StubTranslationBackend(
            provider: .google,
            translationResult: .success([
                TranslationMatch(
                    id: "google-en|tr-merhaba",
                    translation: "merhaba",
                    matchScore: 1.0,
                    contextHint: nil,
                    isPrimary: false
                )
            ]),
            directionResult: .detected(.englishToTurkish)
        )
        let apiKey = ""

        let service = TranslationService(
            settingsProvider: {
                TranslationRuntimeSettings(
                    usesAppleTranslation: false,
                    serviceProvider: .google,
                    googleAPIKey: apiKey
                )
            },
            backendProvider: { _ in [backend] }
        )

        await service.translateNow("hello")

        #expect(service.currentDirection == .englishToTurkish)
        #expect(service.translatedText == "merhaba")
        #expect(service.matches.map(\.translation) == ["merhaba"])
        #expect(service.statusMessage == nil)
        #expect(!service.isTranslating)
    }

    @Test
    @MainActor
    func translationServiceSurfacesExplicitBackendFailures() async {
        let backend = StubTranslationBackend(
            provider: .google,
            translationResult: .failure(.missingAPIKey),
            directionResult: .failure(.missingAPIKey)
        )

        let service = TranslationService(
            settingsProvider: {
                TranslationRuntimeSettings(
                    usesAppleTranslation: false,
                    serviceProvider: .google,
                    googleAPIKey: ""
                )
            },
            backendProvider: { _ in [backend] }
        )

        await service.translateNow("hello")

        #expect(service.matches.isEmpty)
        #expect(service.statusMessage?.contains("API key") == true)
        #expect(!service.isTranslating)
    }

    @Test
    func appSettingsReadsLegacyBackendPreference() {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("appleAndGoogle", forKey: "backend")

        let settings = AppSettings(userDefaults: defaults)

        #expect(settings.translationMode == .appleWithGoogle)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    @MainActor
    func updateCheckerShowsManualFailureFeedback() async {
        let alertPresenter = UpdateAlertPresenterSpy()
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            releaseFetcher: { .failure(.networkFailure("offline")) },
            alertPresenter: alertPresenter
        )

        await checker.checkForUpdates()

        #expect(alertPresenter.failureMessage == "The update request failed: offline")
    }

    @Test
    @MainActor
    func updateCheckerSkipsRecentLaunchChecks() async {
        let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let now = Date()
        defaults.set(now, forKey: "lastUpdateCheckDate")

        let alertPresenter = UpdateAlertPresenterSpy()
        var fetchCalls = 0
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            userDefaults: defaults,
            now: { now },
            releaseFetcher: {
                fetchCalls += 1
                return .failure(.networkFailure("should not be called"))
            },
            alertPresenter: alertPresenter
        )

        await checker.checkOnLaunchIfNeeded()

        #expect(fetchCalls == 0)
        #expect(alertPresenter.failureMessage == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct StubTranslationBackend: TranslationBackend {
    let provider: TranslationServiceProvider
    let translationResult: TranslationBackendTranslationResult
    let directionResult: TranslationDirectionDetectionResult

    func translate(text: String, direction: TranslationDirection) async -> TranslationBackendTranslationResult {
        translationResult
    }

    func detectDirection(for text: String) async -> TranslationDirectionDetectionResult {
        directionResult
    }
}

@MainActor
private final class UpdateAlertPresenterSpy: UpdateAlertPresenting {
    private(set) var failureMessage: String?

    func showUpdateAvailable(version: String, currentVersion: String, downloadURL: String) {}
    func showUpToDate(currentVersion: String) {}

    func showFailure(message: String) {
        failureMessage = message
    }
}
