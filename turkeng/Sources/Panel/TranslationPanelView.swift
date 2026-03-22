import SwiftUI
import Translation

struct TranslationPanelView: View {
    @Bindable var service: TranslationService
    @FocusState private var focusedField: FocusTarget?
    @State private var copiedIndex: Int?
    @State private var expandedMode = false
    @State private var gearHovered = false

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

                settingsGear
                    .padding(.top, expandedMode ? 4 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if !service.matches.isEmpty || service.isTranslating || service.statusMessage != nil {
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
                } else if let statusMessage = service.statusMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
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
                    .frame(minHeight: expandedMode ? 120 : 0, maxHeight: expandedMode ? 600 : 400)
                }
            }
        }
        .frame(width: 680)
        .onKeyPress(phases: [.down]) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            guard keyPress.characters.lowercased() == "r" else { return .ignored }
            service.toggleReverseDirection()
            return .handled
        }
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
        .translationTask(service.appleTranslationConfiguration) { session in
            await service.performAppleTranslation(using: session)
        }
        .onChange(of: service.inputText) {
            if isLongInput && !expandedMode {
                expandedMode = true
            } else if !isLongInput && expandedMode {
                expandedMode = false
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

    private var settingsGear: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(gearHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { gearHovered = $0 }
    }

    @ViewBuilder
    private var languageBadge: some View {
        if let direction = service.currentDirection {
            Text(direction.badgeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }
}

private struct ResultRow: View {
    let match: TranslationMatch
    let isSelected: Bool
    let isCopied: Bool
    let expandedMode: Bool

    var body: some View {
        Group {
            if expandedMode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(match.translation)
                        .font(.system(size: 18))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if let hint = match.contextHint { hintBadge(hint) }
                        Spacer()
                        if isCopied {
                            copiedIcon
                        } else if isSelected {
                            copyLabel
                        }
                        if !match.isPrimary { scoreBadge }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(match.translation)
                        .font(.system(size: 18))
                        .lineLimit(2)

                    if let hint = match.contextHint { hintBadge(hint) }
                    Spacer()
                    if isCopied {
                        copiedIcon
                    } else if isSelected {
                        copyLabel
                    }
                    if !match.isPrimary { scoreBadge }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private func hintBadge(_ hint: String) -> some View {
        Text(hint)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private var copiedIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.system(size: 14))
            .transition(.scale.combined(with: .opacity))
    }

    private var copyLabel: some View {
        Text("↵ copy")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
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
