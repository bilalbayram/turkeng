import AppKit
import Foundation
import OSLog

protocol UpdateAlertPresenting {
    @MainActor func showUpdateAvailable(version: String, currentVersion: String, downloadURL: String)
    @MainActor func showUpToDate(currentVersion: String)
    @MainActor func showFailure(message: String)
}

struct AppKitUpdateAlertPresenter: UpdateAlertPresenting {
    @MainActor
    func showUpdateAvailable(version: String, currentVersion: String, downloadURL: String) {
        let alert = makeAlert(
            messageText: "Update Available",
            informativeText: "turkeng v\(version) is available. You are currently on v\(currentVersion).",
            style: .informational,
            buttonTitles: ["Download", "Later"]
        )

        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    func showUpToDate(currentVersion: String) {
        let alert = makeAlert(
            messageText: "You're Up to Date",
            informativeText: "turkeng v\(currentVersion) is the latest version.",
            style: .informational,
            buttonTitles: ["OK"]
        )
        alert.runModal()
    }

    @MainActor
    func showFailure(message: String) {
        let alert = makeAlert(
            messageText: "Update Check Failed",
            informativeText: message,
            style: .warning,
            buttonTitles: ["OK"]
        )
        alert.runModal()
    }

    @MainActor
    private func makeAlert(
        messageText: String,
        informativeText: String,
        style: NSAlert.Style,
        buttonTitles: [String]
    ) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = style
        for buttonTitle in buttonTitles {
            alert.addButton(withTitle: buttonTitle)
        }
        return alert
    }
}

enum UpdateCheckError: Equatable, LocalizedError {
    case invalidURL
    case invalidResponseStatus(Int)
    case networkFailure(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The release feed URL is invalid."
        case .invalidResponseStatus(let statusCode):
            "GitHub returned HTTP \(statusCode) while checking for updates."
        case .networkFailure(let description):
            "The update request failed: \(description)"
        case .invalidPayload(let description):
            "The latest release payload could not be decoded: \(description)"
        }
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion = ""
    var isChecking = false

    private let currentVersion: String
    private let lastCheckKey = "lastUpdateCheckDate"
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let releaseFetcher: () async -> Result<GitHubRelease, UpdateCheckError>
    private let alertPresenter: UpdateAlertPresenting
    private let logger: Logger

    init(
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        releaseFetcher: @escaping () async -> Result<GitHubRelease, UpdateCheckError> =
            UpdateChecker.fetchLatestRelease,
        alertPresenter: UpdateAlertPresenting = AppKitUpdateAlertPresenter(),
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.bilalbayram.turkeng",
            category: "UpdateChecker"
        )
    ) {
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
        self.now = now
        self.releaseFetcher = releaseFetcher
        self.alertPresenter = alertPresenter
        self.logger = logger
    }

    /// Always checks and shows an alert if an update is available.
    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }
        await handleReleaseCheck(showUpToDateAlert: true, showFailureAlert: true, failureLogPrefix: "Manual")
    }

    /// Throttled check: once per 24 hours, no UI if already up to date.
    func checkOnLaunchIfNeeded() async {
        if let lastCheck = userDefaults.object(forKey: lastCheckKey) as? Date,
           now().timeIntervalSince(lastCheck) < 86400 {
            return
        }

        userDefaults.set(now(), forKey: lastCheckKey)
        await handleReleaseCheck(showUpToDateAlert: false, showFailureAlert: false, failureLogPrefix: "Launch")
    }

    private static func fetchLatestRelease() async -> Result<GitHubRelease, UpdateCheckError> {
        guard let url = URL(string: "https://api.github.com/repos/bilalbayram/turkeng/releases/latest") else {
            return .failure(.invalidURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponseStatus(-1))
            }
            guard httpResponse.statusCode == 200 else {
                return .failure(.invalidResponseStatus(httpResponse.statusCode))
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                return .success(release)
            } catch {
                return .failure(.invalidPayload(error.localizedDescription))
            }
        } catch {
            return .failure(.networkFailure(error.localizedDescription))
        }
    }

    private func normalizedVersion(from tagName: String) -> String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private func handleReleaseCheck(
        showUpToDateAlert: Bool,
        showFailureAlert: Bool,
        failureLogPrefix: String
    ) async {
        switch await releaseFetcher() {
        case .success(let release):
            await applyRelease(release, showUpToDateAlert: showUpToDateAlert)
        case .failure(let error):
            logger.error("\(failureLogPrefix) update check failed: \(error.localizedDescription)")
            guard showFailureAlert else { return }
            await alertPresenter.showFailure(message: error.localizedDescription)
        }
    }

    private func applyRelease(_ release: GitHubRelease, showUpToDateAlert: Bool) async {
        let remoteVersion = normalizedVersion(from: release.tagName)

        if isNewer(remote: remoteVersion, local: currentVersion) {
            latestVersion = remoteVersion
            updateAvailable = true
            await alertPresenter.showUpdateAvailable(
                version: remoteVersion,
                currentVersion: currentVersion,
                downloadURL: release.htmlURL
            )
            return
        }

        guard showUpToDateAlert else { return }
        await alertPresenter.showUpToDate(currentVersion: currentVersion)
    }

    func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart > localPart { return true }
            if remotePart < localPart { return false }
        }
        return false
    }
}
