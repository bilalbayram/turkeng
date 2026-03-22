import AppKit

struct PasteboardTranslationClipboardWriter: TranslationClipboardWriting {
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
