import Foundation
import NaturalLanguage

struct GoogleTranslateBackend: ServiceTranslationBackend {
    let backendId = "google"

    func translate(text: String, direction: TranslationDirection) async -> [TranslationMatch] {
        guard let apiKey = apiKey else { return [] }

        guard var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            GoogleTranslateRequest(
                q: text,
                source: direction.sourceCode,
                target: direction.targetCode,
                format: "text"
            )
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
                    id: "\(backendId)-\(direction.langPair)-\(translatedText.lowercased())",
                    translation: translatedText,
                    matchScore: 1.0,
                    contextHint: partOfSpeech(for: translatedText, language: direction.targetNLLanguage),
                    isPrimary: false
                )
            ]
        } catch {
            return []
        }
    }

    func detectDirection(for text: String) async -> TranslationDirection? {
        guard let apiKey = apiKey else { return nil }
        guard var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2/detect") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: text),
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let payload = try JSONDecoder().decode(GoogleDetectResponse.self, from: data)
            let languageCode = payload.data.detections.first?.first?.language
            return TranslationDirection.fromDetectedLanguageCode(languageCode)
        } catch {
            return nil
        }
    }

    private var apiKey: String? {
        let trimmed = AppSettings.shared.googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private struct GoogleDetectResponse: Decodable {
    let data: DetectionData

    struct DetectionData: Decodable {
        let detections: [[Entry]]
    }

    struct Entry: Decodable {
        let language: String
    }
}
