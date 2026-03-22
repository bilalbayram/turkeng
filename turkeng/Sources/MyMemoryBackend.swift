import Foundation
import NaturalLanguage

struct MyMemoryBackend: ServiceTranslationBackend {
    let backendId = "myMemory"
    private static let maxMatches = 5
    private static let fallbackThreshold = 0.85

    func translate(text: String, direction: TranslationDirection) async -> [TranslationMatch] {
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: direction.langPair),
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return [] }
            return try Self.matches(from: data, inputText: text, targetLanguage: direction.targetNLLanguage)
        } catch {
            return []
        }
    }

    static func matches(from data: Data, inputText: String, targetLanguage: NLLanguage) throws -> [TranslationMatch] {
        let response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        let rawMatches = response.matches ?? []
        let inputLower = inputText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let exactMatches = rawMatches
            .filter { entry in
                normalizedText(entry.segment) == inputLower &&
                normalizedText(entry.translation) != normalizedText(entry.segment)
            }
            .sorted { $0.matchScore > $1.matchScore }

        let fallbackMatches = rawMatches
            .filter { entry in
                normalizedText(entry.translation) != normalizedText(entry.segment) &&
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
        exactMatches: [MyMemoryResponse.MatchEntry],
        fallbackMatches: [MyMemoryResponse.MatchEntry],
        targetLanguage: NLLanguage
    ) -> [TranslationMatch] {
        var results: [TranslationMatch] = []
        var seenTranslations = Set<String>()

        func append(_ entry: MyMemoryResponse.MatchEntry) {
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
    let responseData: ResponseData
    let matches: [MatchEntry]?

    struct ResponseData: Decodable {
        let translatedText: String
    }

    struct MatchEntry: Decodable {
        let id: String
        let segment: String
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

            segment = try container.decodeIfPresent(String.self, forKey: .segment) ?? ""
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
}
