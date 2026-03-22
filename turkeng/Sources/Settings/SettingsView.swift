import SwiftUI
import Translation

struct SettingsView: View {
    private struct LanguagePack {
        let title: String
        let sourceLanguage: Locale.Language
        let targetLanguage: Locale.Language
    }

    @Bindable private var settings: AppSettings
    @State private var turkishToEnglishInstalled = false
    @State private var englishToTurkishInstalled = false
    @State private var isChecking = true
    @State private var downloadConfig: TranslationSession.Configuration?
    @State private var downloadErrorMessage: String?

    private let turkishToEnglishPack = LanguagePack(
        title: "Turkish → English",
        sourceLanguage: Locale.Language(identifier: "tr"),
        targetLanguage: Locale.Language(identifier: "en")
    )
    private let englishToTurkishPack = LanguagePack(
        title: "English → Turkish",
        sourceLanguage: Locale.Language(identifier: "en"),
        targetLanguage: Locale.Language(identifier: "tr")
    )

    init(settings: AppSettings) {
        self.settings = settings
    }

    var body: some View {
        Form {
            // MARK: - Hotkey
            Section {
                HStack {
                    Picker("Modifier", selection: $settings.hotkeyModifier) {
                        ForEach(HotkeyModifier.allCases) { mod in
                            Text(mod.label).tag(mod)
                        }
                    }
                    .frame(width: 200)

                    Text("+")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $settings.hotkeyLetter) {
                        ForEach(HotkeyLetter.allCases) { letter in
                            Text(letter.label).tag(letter)
                        }
                    }
                    .frame(width: 80)
                }
                .labelsHidden()

                Text("Current: \(settings.hotkeyModifier.symbol)\(settings.hotkeyLetter.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Changes apply immediately. The hotkey toggles the translation panel from anywhere.")
            }

            // MARK: - Translation Backend
            Section {
                Picker("Engine", selection: $settings.translationMode) {
                    ForEach(TranslationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            } header: {
                Text("Translation Backend")
            } footer: {
                Text(
                    "Apple Translation runs on-device with high quality. "
                        + "MyMemory provides crowdsourced alternatives. "
                        + "Google Translate uses your own API key and adds a network-backed machine translation option."
                )
            }

            if settings.translationMode.requiresGoogleAPIKey {
                Section {
                    SecureField("API key", text: $settings.googleAPIKey)
                        .textFieldStyle(.roundedBorder)

                    if settings.googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Google Translate requires an API key.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Google Translate")
                } footer: {
                    Text(
                        "Create a Cloud Translation API key in Google Cloud Console and paste it here. "
                            + "The key is stored locally on this Mac."
                    )
                }
            }

            // MARK: - Menu Bar
            Section {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("When hidden, use the gear icon in the translation panel or \u{2318}, to access settings.")
            }

            // MARK: - Apple Translation Languages
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turkishToEnglishPack.title)
                        statusLabel(installed: turkishToEnglishInstalled)
                    }
                    Spacer()
                    downloadButton(installed: turkishToEnglishInstalled, pack: turkishToEnglishPack)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(englishToTurkishPack.title)
                        statusLabel(installed: englishToTurkishInstalled)
                    }
                    Spacer()
                    downloadButton(installed: englishToTurkishInstalled, pack: englishToTurkishPack)
                }

                if let downloadErrorMessage {
                    Label(downloadErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Language Packs")
            } footer: {
                Text("Required for Apple Translation. Download once, works offline.")
            }
        }
        .formStyle(.grouped)
        .translationTask(downloadConfig) { session in
            do {
                _ = try await session.translate("hello")
                downloadErrorMessage = nil
            } catch {
                downloadErrorMessage = "Could not download the selected language pack: \(error.localizedDescription)"
            }
            await refreshStatus()
        }
        .task {
            await refreshStatus()
        }
        .frame(width: 460)
        .frame(minHeight: 420)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statusLabel(installed: Bool) -> some View {
        if isChecking {
            Text("Checking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if installed {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("Not installed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func downloadButton(installed: Bool, pack: LanguagePack) -> some View {
        if !isChecking && !installed {
            Button("Download…") {
                downloadErrorMessage = nil
                downloadConfig = .init(
                    source: pack.sourceLanguage,
                    target: pack.targetLanguage
                )
            }
        }
    }

    // MARK: - Availability Check

    @MainActor
    private func refreshStatus() async {
        isChecking = true
        let availability = LanguageAvailability()
        let turkishToEnglishStatus = await availability.status(
            from: turkishToEnglishPack.sourceLanguage,
            to: turkishToEnglishPack.targetLanguage
        )
        let englishToTurkishStatus = await availability.status(
            from: englishToTurkishPack.sourceLanguage,
            to: englishToTurkishPack.targetLanguage
        )

        turkishToEnglishInstalled = (turkishToEnglishStatus == .installed)
        englishToTurkishInstalled = (englishToTurkishStatus == .installed)
        isChecking = false
    }
}
