import SwiftUI
import Translation

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var trEnInstalled = false
    @State private var enTrInstalled = false
    @State private var isChecking = true
    @State private var downloadConfig: TranslationSession.Configuration?

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
                Picker("Engine", selection: $settings.backend) {
                    ForEach(TranslationBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            } header: {
                Text("Translation Backend")
            } footer: {
                Text("Apple Translation runs on-device with high quality. MyMemory provides crowdsourced alternatives. Google Translate uses your own API key and adds a network-backed machine translation option.")
            }

            if settings.backend.includesGoogle {
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
                    Text("Create a Cloud Translation API key in Google Cloud Console and paste it here. The key is stored locally on this Mac.")
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
                        Text("Turkish → English")
                        statusLabel(installed: trEnInstalled)
                    }
                    Spacer()
                    downloadButton(installed: trEnInstalled, source: "tr", target: "en")
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("English → Turkish")
                        statusLabel(installed: enTrInstalled)
                    }
                    Spacer()
                    downloadButton(installed: enTrInstalled, source: "en", target: "tr")
                }
            } header: {
                Text("Language Packs")
            } footer: {
                Text("Required for Apple Translation. Download once, works offline.")
            }
        }
        .formStyle(.grouped)
        .translationTask(downloadConfig) { session in
            _ = try? await session.translate("hello")
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
    private func downloadButton(installed: Bool, source: String, target: String) -> some View {
        if !isChecking && !installed {
            Button("Download…") {
                downloadConfig = .init(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
            }
        }
    }

    // MARK: - Availability Check

    @MainActor
    private func refreshStatus() async {
        isChecking = true
        let availability = LanguageAvailability()
        let tr = Locale.Language(identifier: "tr")
        let en = Locale.Language(identifier: "en")

        let s1 = await availability.status(from: tr, to: en)
        let s2 = await availability.status(from: en, to: tr)

        trEnInstalled = (s1 == .installed)
        enTrInstalled = (s2 == .installed)
        isChecking = false
    }
}
