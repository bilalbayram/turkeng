import Testing
@testable import turkeng

struct TurkengTests {

    @Test
    @MainActor
    func inputChangeClearsVisibleMatchesWhileTranslating() {
        let service = TranslationService()
        service.matches = [
            TranslationMatch(id: "1", translation: "eski sonuc", matchScore: 1.0)
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

}
