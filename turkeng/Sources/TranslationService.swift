import Foundation
import NaturalLanguage

@Observable
final class TranslationService {
    var inputText: String = ""
    var translatedText: String = ""
    var isTranslating: Bool = false

    private var debounceTask: Task<Void, Never>?

    func onInputChanged() {
        debounceTask?.cancel()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            isTranslating = false
            return
        }

        isTranslating = true

        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await translate(trimmed)
        }
    }

    func reset() {
        debounceTask?.cancel()
        inputText = ""
        translatedText = ""
        isTranslating = false
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

    @MainActor
    private func translate(_ text: String) async {
        let langPair = detectLangPair(for: text)

        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair),
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }

            let response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            translatedText = response.responseData.translatedText
        } catch {
            if !Task.isCancelled {
                translatedText = "Translation failed"
            }
        }

        isTranslating = false
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData

    struct ResponseData: Decodable {
        let translatedText: String
    }
}
