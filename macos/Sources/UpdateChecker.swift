import AppKit

final class UpdateChecker {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let htmlUrl: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlUrl = "html_url"
            case assets
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/sasukefrontenddev/orbitdrop/releases/latest")!
    private var timer: Timer?
    private var displayedVersion: String?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("OrbitDrop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard self.isNewer(latest, than: self.currentVersion), self.displayedVersion != latest else { return }
            self.displayedVersion = latest
            DispatchQueue.main.async { self.present(release: release, version: latest) }
        }.resume()
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = installed.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let candidatePart = index < left.count ? left[index] : 0
            let installedPart = index < right.count ? right[index] : 0
            if candidatePart != installedPart { return candidatePart > installedPart }
        }
        return false
    }

    private func present(release: Release, version: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OrbitDrop \(version) is available"
        alert.informativeText = "You have version \(currentVersion). Download the latest release from the official OrbitDrop repository?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let download = release.assets.first(where: {
            $0.name.localizedCaseInsensitiveContains("macOS-universal.zip")
        })?.browserDownloadUrl ?? release.htmlUrl
        NSWorkspace.shared.open(download)
    }
}
