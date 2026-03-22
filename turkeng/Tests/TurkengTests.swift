import Foundation
import Testing
@testable import turkeng

struct TurkengTests {

    @Test
    @MainActor
    func inputChangeClearsVisibleMatchesWhileTranslating() {
        let service = TranslationService()
        service.matches = [
            TranslationMatch(id: "1", translation: "eski sonuc", matchScore: 1.0, contextHint: nil, isPrimary: true)
        ]
        service.selectedIndex = 0
        service.translatedText = "old result"
        service.inputText = "new query"

        service.onInputChanged()

        #expect(service.isTranslating)
        #expect(service.matches.isEmpty)
        #expect(service.selectedIndex == 0)
        #expect(service.translatedText.isEmpty)

        service.reset()
    }

    @Test
    func shortInputStillShowsGhostText() {
        let service = TranslationService()
        service.inputText = "merh"

        #expect(service.computeGhostText() == "aba")
    }

    @Test
    func longInputDisablesGhostText() {
        let service = TranslationService()
        service.inputText = String(repeating: "a", count: 51)

        #expect(service.computeGhostText().isEmpty)
    }

    @Test
    func multilineInputDisablesGhostText() {
        let service = TranslationService()
        service.inputText = "merhaba\nnasilsin"

        #expect(service.computeGhostText().isEmpty)
    }

    @Test
    func localDirectionDetectsTurkishInput() {
        let service = TranslationService()

        #expect(service.detectLocalDirection(for: "merhaba") == .turkishToEnglish)
    }

    @Test
    func localDirectionDetectsEnglishInput() {
        let service = TranslationService()

        #expect(service.detectLocalDirection(for: "hello") == .englishToTurkish)
    }

    @Test
    func previewDirectionAppliesReverseOverrideWithoutChangingInput() {
        let service = TranslationService()
        service.inputText = "merhaba"
        service.isDirectionReversed = true

        #expect(service.inputText == "merhaba")
        #expect(service.previewDirection(for: service.inputText) == .englishToTurkish)
    }

    @Test
    @MainActor
    func resetClearsReverseOverride() {
        let service = TranslationService()
        service.inputText = "merhaba"
        service.isDirectionReversed = true

        service.reset()

        #expect(service.inputText.isEmpty)
        #expect(!service.isDirectionReversed)
        #expect(service.currentDirection == nil)
    }

    @Test
    @MainActor
    func emptyInputClearsReverseOverride() {
        let service = TranslationService()
        service.inputText = ""
        service.isDirectionReversed = true
        service.currentDirection = .englishToTurkish

        service.onInputChanged()

        #expect(!service.isDirectionReversed)
        #expect(service.currentDirection == nil)
    }

    @Test
    func myMemoryKeepsExactMatchesFirstAndAppendsFallbackAlternatives() throws {
        let data = Data(
            """
            {
              "responseData": { "translatedText": "merhaba" },
              "matches": [
                { "id": "1", "segment": "hello", "translation": "merhaba", "match": 0.99 },
                { "id": "2", "segment": "hello", "translation": "selam", "match": 0.95 },
                { "id": "3", "segment": "greetings", "translation": "selamlar", "match": 0.93 },
                { "id": "4", "segment": "hi", "translation": "merhaba", "match": 0.92 },
                { "id": "5", "segment": "hey", "translation": "iyi günler", "match": 0.90 }
              ]
            }
            """.utf8
        )

        let matches = try MyMemoryBackend.matches(from: data, inputText: "hello", targetLanguage: .turkish)

        #expect(matches.map { $0.translation } == ["merhaba", "selam", "selamlar", "iyi günler"])
    }

    @Test
    func myMemoryCapsResultsAtFiveAfterDeduping() throws {
        let data = Data(
            """
            {
              "responseData": { "translatedText": "merhaba" },
              "matches": [
                { "id": "1", "segment": "hello", "translation": "merhaba", "match": 0.99 },
                { "id": "2", "segment": "hello", "translation": "selam", "match": 0.98 },
                { "id": "3", "segment": "greetings", "translation": "selamlar", "match": 0.97 },
                { "id": "4", "segment": "hey", "translation": "iyi günler", "match": 0.96 },
                { "id": "5", "segment": "hiya", "translation": "merhabalar", "match": 0.95 },
                { "id": "6", "segment": "yo", "translation": "merhaba dostum", "match": 0.94 },
                { "id": "7", "segment": "hi", "translation": "selam", "match": 0.93 }
              ]
            }
            """.utf8
        )

        let matches = try MyMemoryBackend.matches(from: data, inputText: "hello", targetLanguage: .turkish)

        #expect(matches.count == 5)
        #expect(matches.map { $0.translation } == ["merhaba", "selam", "selamlar", "iyi günler", "merhabalar"])
    }

}
