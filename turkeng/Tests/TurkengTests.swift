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

}
