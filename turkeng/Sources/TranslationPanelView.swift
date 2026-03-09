import SwiftUI

struct TranslationPanelView: View {
    @Bindable var service: TranslationService
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)

                TextField("Translate Turkish ↔ English…", text: $service.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .light))
                    .focused($isInputFocused)
                    .onChange(of: service.inputText) {
                        service.onInputChanged()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Result area
            if !service.translatedText.isEmpty || service.isTranslating {
                Divider()
                    .padding(.horizontal, 16)

                HStack {
                    if service.isTranslating && service.translatedText.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Translating…")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    } else {
                        Text(service.translatedText)
                            .font(.system(size: 20))
                            .textSelection(.enabled)
                    }

                    Spacer()

                    if !service.translatedText.isEmpty {
                        languageBadge
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 680)
        .onAppear {
            isInputFocused = true
        }
    }

    private var languageBadge: some View {
        let trimmed = service.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let langPair = service.detectLangPair(for: trimmed)
        let directionText = langPair == "tr|en" ? "TR → EN" : "EN → TR"
        return Text(directionText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
