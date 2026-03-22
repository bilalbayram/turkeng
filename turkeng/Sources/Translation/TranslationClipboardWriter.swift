protocol TranslationClipboardWriting {
    func copy(_ text: String)
}

struct NoopTranslationClipboardWriter: TranslationClipboardWriting {
    func copy(_ text: String) {}
}
