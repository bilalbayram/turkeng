import SwiftUI
import Translation

struct TranslationPanelView: View {
    @Bindable var service: TranslationService
    @FocusState private var focusedField: FocusTarget?
    @State private var copiedIndex: Int?
    @State private var expandedMode = false

    private enum FocusTarget: Hashable {
        case shortInput
        case longInput
    }

    private var isLongInput: Bool {
        service.inputText.count > 50 || service.inputText.contains("\n")
    }

    private var hasInput: Bool {
        !service.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: expandedMode ? .top : .center, spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, expandedMode ? 4 : 0)

                inputView

                if hasInput {
                    languageBadge
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

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
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(service.matches.enumerated()), id: \.element.id) { index, match in
                                ResultRow(
                                    match: match,
                                    isSelected: index == service.selectedIndex,
                                    isCopied: copiedIndex == index,
                                    expandedMode: expandedMode
                                )
                                .onTapGesture {
                                    service.selectedIndex = index
                                    performCopy()
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 680)
        .onKeyPress(.downArrow) {
            if expandedMode { return .ignored }
            service.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if expandedMode { return .ignored }
            service.selectPrevious()
            return .handled
        }
        .translationTask(service.translationConfig) { session in
            guard let text = service.pendingTranslationText else { return }
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    service.handleAppleResult(response.targetText, for: text)
                }
            } catch {
                await MainActor.run {
                    service.handleAppleFailure()
                }
            }
        }
        .onChange(of: service.inputText) {
            if !expandedMode && isLongInput {
                expandedMode = true
            }
            service.onInputChanged()
        }
        .onChange(of: expandedMode) {
            focusedField = expandedMode ? .longInput : .shortInput
        }
        .onAppear {
            expandedMode = false
            focusedField = .shortInput
        }
    }

    @ViewBuilder
    private var inputView: some View {
        if expandedMode {
            TextEditor(text: $service.inputText)
                .font(.system(size: 18, weight: .light))
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 300)
                .focused($focusedField, equals: .longInput)
                .onAppear {
                    focusedField = .longInput
                }
                .onKeyPress(phases: [.down]) { keyPress in
                    guard keyPress.key == .return else { return .ignored }
                    guard keyPress.modifiers.isEmpty else { return .ignored }
                    performCopy()
                    return .handled
                }
        } else {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text(service.inputText)
                        .font(.system(size: 20, weight: .light))
                        .opacity(0)
                    Text(service.computeGhostText())
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .allowsHitTesting(false)

                TextField("Translate Turkish ↔ English…", text: $service.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .light))
                    .focused($focusedField, equals: .shortInput)
                    .onSubmit {
                        performCopy()
                    }
            }
        }
    }

    private func performCopy() {
        guard service.copySelected() != nil else { return }
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

private struct ResultRow: View {
    let match: TranslationMatch
    let isSelected: Bool
    let isCopied: Bool
    let expandedMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(match.translation)
                .font(.system(size: 18))
                .lineLimit(expandedMode ? nil : 2)

            if let hint = match.contextHint {
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

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

            if !match.isPrimary {
                scoreBadge
            }
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
