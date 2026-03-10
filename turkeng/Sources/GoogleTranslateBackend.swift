import Foundation
import NaturalLanguage

struct GoogleTranslateBackend: ServiceTranslationBackend {
    let backendId = "google"

    func translate(text: String, langPair: String, targetLanguage: NLLanguage) async -> [TranslationMatch] {
        let apiKey = AppSettings.shared.googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return [] }

        let languages = langPair.split(separator: "|", maxSplits: 1).map(String.init)
        guard languages.count == 2 else { return [] }

        guard var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            GoogleTranslateRequest(q: text, source: languages[0], target: languages[1], format: "text")
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return [] }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return []
            }

            let payload = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)
            guard let translatedText = payload.data.translations.first?.translatedText
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !translatedText.isEmpty
            else {
                return []
            }

            return [
                TranslationMatch(
                    id: "\(backendId)-\(langPair)-\(translatedText.lowercased())",
                    translation: translatedText,
                    matchScore: 1.0,
                    contextHint: partOfSpeech(for: translatedText, language: targetLanguage),
                    isPrimary: false
                )
            ]
        } catch {
            return []
        }
    }
}

private struct GoogleTranslateRequest: Encodable {
    let q: String
    let source: String
    let target: String
    let format: String
}

private struct GoogleTranslateResponse: Decodable {
    let data: TranslationData

    struct TranslationData: Decodable {
        let translations: [Entry]
    }

    struct Entry: Decodable {
        let translatedText: String
    }
}
