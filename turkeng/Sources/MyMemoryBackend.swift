import Foundation
import NaturalLanguage

struct MyMemoryBackend: ServiceTranslationBackend {
    let backendId = "myMemory"

    func translate(text: String, langPair: String, targetLanguage: NLLanguage) async -> [TranslationMatch] {
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair),
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return [] }

            let response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            let rawMatches = response.matches ?? []
            let inputLower = text.lowercased()

            let relevant: [MyMemoryResponse.MatchEntry]
            let exactSegment = rawMatches.filter { entry in
                let segment = entry.segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let translation = entry.translation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return segment == inputLower && translation != segment
            }
            if !exactSegment.isEmpty {
                relevant = exactSegment
            } else {
                relevant = rawMatches.filter { entry in
                    let translation = entry.translation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let segment = entry.segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return entry.matchScore >= 0.85 && translation != segment
                }
            }

            var deduped: [String: TranslationMatch] = [:]

            for match in relevant {
                let trimmed = match.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let key = trimmed.lowercased()
                let candidate = TranslationMatch(
                    id: match.id,
                    translation: trimmed,
                    matchScore: match.matchScore,
                    contextHint: partOfSpeech(for: trimmed, language: targetLanguage),
                    isPrimary: false
                )

                if let existing = deduped[key], existing.matchScore >= candidate.matchScore {
                    continue
                }

                deduped[key] = candidate
            }

            return Array(deduped.values.sorted { $0.matchScore > $1.matchScore }.prefix(3))
        } catch {
            return []
        }
    }
}

private struct MyMemoryResponse: Decodable {
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
