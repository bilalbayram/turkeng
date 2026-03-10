import AppKit
import Foundation

@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    var updateAvailable = false
    var latestVersion = ""
    var isChecking = false

    private let currentVersion: String
    private let lastCheckKey = "lastUpdateCheckDate"

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Always checks and shows an alert if an update is available.
    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        do {
            guard let release = try await fetchLatestRelease() else { return }
            let remote = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            if isNewer(remote: remote, local: currentVersion) {
                latestVersion = remote
                updateAvailable = true
                await MainActor.run {
                    showUpdateAlert(version: remote, downloadURL: release.htmlURL)
                }
            } else {
                await MainActor.run {
                    showUpToDateAlert()
                }
            }
        } catch {
            // Network error — silent no-op
        }
    }

    /// Throttled check: once per 24 hours, no UI if already up to date.
    func checkOnLaunchIfNeeded() async {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86400 {
            return
        }

        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        do {
            guard let release = try await fetchLatestRelease() else { return }
            let remote = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            if isNewer(remote: remote, local: currentVersion) {
                latestVersion = remote
                updateAvailable = true
                await MainActor.run {
                    showUpdateAlert(version: remote, downloadURL: release.htmlURL)
                }
            }
        } catch {
            // Silent failure
        }
    }

    // MARK: - Private

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/bilalbayram/turkeng/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    @MainActor
    private func showUpdateAlert(version: String, downloadURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "turkeng v\(version) is available. You are currently on v\(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @MainActor
    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "turkeng v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
