import SwiftUI

struct TranslationPanelView: View {
    @Bindable var service: TranslationService
    @FocusState private var isInputFocused: Bool
    @State private var copiedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Search row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .leading) {
                    // Ghost text overlay
                    HStack(spacing: 0) {
                        Text(service.inputText)
                            .font(.system(size: 20, weight: .light))
                            .opacity(0) // invisible spacer matching input width
                        Text(service.computeGhostText())
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                    .allowsHitTesting(false)

                    TextField("Translate Turkish ↔ English…", text: $service.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .light))
                        .focused($isInputFocused)
                        .onChange(of: service.inputText) {
                            service.onInputChanged()
                        }
                        .onSubmit {
                            performCopy()
                        }
                }

                if !service.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    languageBadge
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Results area
            if !service.matches.isEmpty || service.isTranslating {
                Divider()
                    .padding(.horizontal, 16)

                if service.isTranslating && service.matches.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Translating…")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.matches.enumerated()), id: \.element.id) { index, match in
                            ResultRow(
                                match: match,
                                isSelected: index == service.selectedIndex,
                                isCopied: copiedIndex == index
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 680)
        .onKeyPress(.downArrow) {
            service.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            service.selectPrevious()
            return .handled
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private func performCopy() {
        guard let _ = service.copySelected() else { return }
        let idx = service.selectedIndex
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedIndex = idx
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                if copiedIndex == idx {
                    copiedIndex = nil
                }
            }
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

// MARK: - Result Row

private struct ResultRow: View {
    let match: TranslationMatch
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(match.translation)
                .font(.system(size: 18))
                .lineLimit(2)

            Spacer()

            if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                    .transition(.scale.combined(with: .opacity))
            } else if isSelected {
                Text("↵ copy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            scoreBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private var scoreBadge: some View {
        let pct = Int(match.matchScore * 100)
        return Text("\(pct)%")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}
