import Foundation
import NaturalLanguage

struct MyMemoryBackend: TranslationBackend {
    let provider: TranslationServiceProvider = .myMemory
    private static let maxMatches = 5
    private static let fallbackThreshold = 0.85

    func translate(text: String, direction: TranslationDirection) async -> TranslationBackendTranslationResult {
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else {
            return .failure(.invalidRequest)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: direction.langPair)
        ]
        guard let url = components.url else {
            return .failure(.invalidRequest)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else {
                return .failure(.cancelled)
            }

            let matches = try Self.matches(from: data, inputText: text, targetLanguage: direction.targetNLLanguage)
            return .success(matches)
        } catch {
            if let backendError = error as? TranslationBackendError {
                return .failure(backendError)
            }
            return .failure(.networkFailure(error.localizedDescription))
        }
    }

    static func matches(from data: Data, inputText: String, targetLanguage: NLLanguage) throws -> [TranslationMatch] {
        let response: MyMemoryResponse
        do {
            response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        } catch {
            throw TranslationBackendError.invalidPayload(error.localizedDescription)
        }
        let rawMatches = response.matches ?? []
        let inputLower = inputText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let exactMatches = rawMatches
            .filter { entry in
                guard let segment = entry.segment else { return false }
                return normalizedText(segment) == inputLower &&
                    normalizedText(entry.translation) != normalizedText(segment)
            }
            .sorted { $0.matchScore > $1.matchScore }

        let fallbackMatches = rawMatches
            .filter { entry in
                normalizedText(entry.translation) != normalizedText(entry.segment ?? "") &&
                entry.matchScore >= Self.fallbackThreshold
            }
            .sorted { $0.matchScore > $1.matchScore }

        return dedupeAndRank(
            exactMatches: exactMatches,
            fallbackMatches: fallbackMatches,
            targetLanguage: targetLanguage
        )
    }

    private static func dedupeAndRank(
        exactMatches: [MyMemoryMatchEntry],
        fallbackMatches: [MyMemoryMatchEntry],
        targetLanguage: NLLanguage
    ) -> [TranslationMatch] {
        var results: [TranslationMatch] = []
        var seenTranslations = Set<String>()

        func append(_ entry: MyMemoryMatchEntry) {
            guard results.count < Self.maxMatches else { return }

            let trimmedTranslation = entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTranslation = normalizedText(trimmedTranslation)
            guard !normalizedTranslation.isEmpty else { return }
            guard seenTranslations.insert(normalizedTranslation).inserted else { return }

            results.append(
                TranslationMatch(
                    id: entry.id,
                    translation: trimmedTranslation,
                    matchScore: entry.matchScore,
                    contextHint: partOfSpeech(for: trimmedTranslation, language: targetLanguage),
                    isPrimary: false
                )
            )
        }

        for entry in exactMatches {
            append(entry)
        }

        for entry in fallbackMatches {
            append(entry)
        }

        return results
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct MyMemoryResponse: Decodable {
    let responseData: MyMemoryResponseData
    let matches: [MyMemoryMatchEntry]?
}

struct MyMemoryResponseData: Decodable {
    let translatedText: String
}

struct MyMemoryMatchEntry: Decodable {
    let id: String
    let segment: String?
    let translation: String
    let matchScore: Double

    private enum CodingKeys: String, CodingKey {
        case id, translation, quality, match, source, target, segment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = UUID().uuidString
        }

        segment = try container.decodeIfPresent(String.self, forKey: .segment)
        translation = try container.decode(String.self, forKey: .translation)

        if let matchValue = try? container.decode(Double.self, forKey: .match) {
            matchScore = matchValue
        } else if let matchString = try? container.decode(String.self, forKey: .match),
                  let parsed = Double(matchString) {
            matchScore = parsed
        } else {
            matchScore = 0.0
        }
    }
}
