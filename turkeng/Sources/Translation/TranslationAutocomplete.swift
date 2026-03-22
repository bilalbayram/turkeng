import Foundation

struct TranslationAutocomplete {
    private static let seedWords: [String] = [
        "merhaba", "günaydın", "iyi akşamlar", "iyi geceler", "hoşgeldiniz",
        "teşekkürler", "teşekkür ederim", "nasılsın", "nasıl gidiyor",
        "evet", "hayır", "lütfen", "özür dilerim", "affedersiniz",
        "güzel", "güle güle", "görüşürüz", "arkadaş", "aile",
        "sevgi", "mutlu", "üzgün", "büyük", "küçük",
        "yeni", "eski", "güneş", "yağmur", "kar",
        "su", "yemek", "kahvaltı", "öğle yemeği", "akşam yemeği",
        "çay", "kahve", "ekmek", "peynir", "zeytin",
        "okul", "kitap", "öğrenci", "öğretmen", "çalışmak",
        "başlamak", "bitirmek", "anlamak", "bilmek", "istemek",
        "gelmek", "gitmek", "yapmak", "vermek", "almak",
        "bugün", "yarın", "dün", "şimdi", "sonra",
        "hello", "good morning", "good evening", "good night", "welcome",
        "thank you", "thanks", "how are you", "how is it going",
        "yes", "no", "please", "sorry", "excuse me",
        "beautiful", "goodbye", "see you", "friend", "family",
        "love", "happy", "sad", "big", "small",
        "new", "old", "sun", "rain", "snow",
        "water", "food", "breakfast", "lunch", "dinner",
        "tea", "coffee", "bread", "cheese", "olive",
        "school", "book", "student", "teacher", "work",
        "start", "finish", "understand", "know", "want",
        "come", "go", "make", "give", "take",
        "today", "tomorrow", "yesterday", "now", "later"
    ]

    private(set) var queryHistory: [String] = []

    mutating func record(_ query: String) {
        guard queryHistory.last != query else { return }
        queryHistory.append(query)
    }

    func suggestion(for input: String) -> String {
        guard !input.isEmpty else { return "" }
        guard input.count <= 50, !input.contains("\n") else { return "" }

        let normalizedInput = Self.turkishASCIINormalize(input).lowercased()

        for entry in queryHistory.reversed() {
            if let suffix = completionSuffix(in: entry, normalizedInput: normalizedInput, originalInput: input) {
                return suffix
            }
        }

        for entry in Self.seedWords {
            if let suffix = completionSuffix(in: entry, normalizedInput: normalizedInput, originalInput: input) {
                return suffix
            }
        }

        return ""
    }

    private func completionSuffix(
        in entry: String,
        normalizedInput: String,
        originalInput: String
    ) -> String? {
        let normalizedEntry = Self.turkishASCIINormalize(entry).lowercased()
        guard normalizedEntry.hasPrefix(normalizedInput) else { return nil }
        guard entry.count > originalInput.count else { return nil }

        let suffixStart = entry.index(entry.startIndex, offsetBy: originalInput.count)
        return String(entry[suffixStart...])
    }

    private static func turkishASCIINormalize(_ text: String) -> String {
        let characterMap: [Character: Character] = [
            "ç": "c", "Ç": "C", "ğ": "g", "Ğ": "G",
            "ı": "i", "İ": "I", "ö": "o", "Ö": "O",
            "ş": "s", "Ş": "S", "ü": "u", "Ü": "U"
        ]

        return String(text.map { characterMap[$0] ?? $0 })
    }
}
