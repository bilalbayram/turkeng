import Foundation
import NaturalLanguage

struct GoogleTranslateBackend: TranslationBackend {
    let provider: TranslationServiceProvider = .google
    private let apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func translate(text: String, direction: TranslationDirection) async -> TranslationBackendTranslationResult {
        let request: URLRequest
        do {
            request = try makeTranslateRequest(text: text, direction: direction)
        } catch let error as TranslationBackendError {
            return .failure(error)
        } catch {
            return .failure(.invalidPayload(error.localizedDescription))
        }

        let dataResult = await perform(request)
        guard case .success(let data) = dataResult else {
            if case .failure(let error) = dataResult {
                return .failure(error)
            }
            return .failure(.invalidRequest)
        }

        let payload: GoogleTranslateResponse
        do {
            payload = try decode(GoogleTranslateResponse.self, from: data)
        } catch let error as TranslationBackendError {
            return .failure(error)
        } catch {
            return .failure(.invalidPayload(error.localizedDescription))
        }

        guard let translatedText = payload.data.translations.first?.translatedText
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !translatedText.isEmpty
        else {
            return .success([])
        }

        return .success([
            TranslationMatch(
                id: "\(provider.rawValue)-\(direction.langPair)-\(translatedText.lowercased())",
                translation: translatedText,
                matchScore: 1.0,
                contextHint: partOfSpeech(for: translatedText, language: direction.targetNLLanguage),
                isPrimary: false
            )
        ])
    }

    func detectDirection(for text: String) async -> TranslationDirectionDetectionResult {
        guard let apiKey, !apiKey.isEmpty else {
            return .failure(.missingAPIKey)
        }

        guard var components = URLComponents(
            string: "https://translation.googleapis.com/language/translate/v2/detect"
        ) else {
            return .failure(.invalidRequest)
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components.url else {
            return .failure(.invalidRequest)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        let dataResult = await perform(request)
        guard case .success(let data) = dataResult else {
            if case .failure(let error) = dataResult {
                return .failure(error)
            }
            return .failure(.invalidRequest)
        }

        let payload: GoogleDetectResponse
        do {
            payload = try decode(GoogleDetectResponse.self, from: data)
        } catch let error as TranslationBackendError {
            return .failure(error)
        } catch {
            return .failure(.invalidPayload(error.localizedDescription))
        }

        let languageCode = payload.data.detections.first?.first?.language
        return .detected(TranslationDirection.fromDetectedLanguageCode(languageCode))
    }

    private func makeTranslateRequest(text: String, direction: TranslationDirection) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else {
            throw TranslationBackendError.missingAPIKey
        }

        guard var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2") else {
            throw TranslationBackendError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw TranslationBackendError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GoogleTranslateRequest(
                query: text,
                source: direction.sourceCode,
                target: direction.targetCode,
                format: "text"
            )
        )
        return request
    }

    private func perform(_ request: URLRequest) async -> Result<Data, TranslationBackendError> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.networkFailure(error.localizedDescription))
        }

        guard !Task.isCancelled else {
            return .failure(.cancelled)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            return .failure(.invalidResponseStatus(httpResponse.statusCode))
        }

        return .success(data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TranslationBackendError.invalidPayload(error.localizedDescription)
        }
    }
}

private struct GoogleTranslateRequest: Encodable {
    let query: String
    let source: String
    let target: String
    let format: String

    private enum CodingKeys: String, CodingKey {
        case query = "q"
        case source
        case target
        case format
    }
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
