import AppKit

struct UpdateInteractionGate {
    private(set) var checking = false
    private(set) var promptVisible = false
    private(set) var installing = false
    private var manualCheckPending = false

    mutating func requestCheck(manual: Bool) -> Bool {
        if checking {
            manualCheckPending = manualCheckPending || manual
            return false
        }
        guard !installing, !promptVisible else { return false }
        manualCheckPending = manual
        checking = true
        return true
    }

    mutating func finishCheck() -> Bool {
        checking = false
        let wasManual = manualCheckPending
        manualCheckPending = false
        return wasManual
    }

    mutating func beginPrompt() -> Bool {
        guard !promptVisible, !installing else { return false }
        promptVisible = true
        return true
    }

    mutating func endPrompt() {
        promptVisible = false
    }

    mutating func beginInstall() -> Bool {
        guard !installing else { return false }
        installing = true
        return true
    }

    mutating func failInstall() {
        installing = false
    }
}

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
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private enum UpdateError: LocalizedError {
        case missingAssets, missingChecksum, checksumMismatch, invalidArchive
        case invalidVersion, invalidSignature, cannotInstall

        var errorDescription: String? {
            switch self {
            case .missingAssets: return "The release is missing its macOS app or checksum file."
            case .missingChecksum: return "The release checksum could not be read."
            case .checksumMismatch: return "The downloaded update did not pass its security check."
            case .invalidArchive: return "The downloaded update could not be opened."
            case .invalidVersion: return "The downloaded app version does not match the release."
            case .invalidSignature: return "The downloaded app did not pass its integrity check."
            case .cannotInstall: return "OrbitDrop could not start the updater."
            }
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/sasukefrontenddev/orbitdrop/releases/latest")!
    private static let pendingUpdateKey = "OrbitDropPendingUpdateVersion"
    private var timer: Timer?
    private var displayedVersion: String?
    private var interaction = UpdateInteractionGate()

    init() {
        if let pending = UserDefaults.standard.string(forKey: Self.pendingUpdateKey) {
            if isNewer(pending, than: currentVersion) {
                displayedVersion = pending
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
            }
        }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func check(showCurrent: Bool = false) {
        precondition(Thread.isMainThread)
        guard interaction.requestCheck(manual: showCurrent) else { return }
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("OrbitDrop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let release: Release?
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                release = try? JSONDecoder().decode(Release.self, from: data)
            } else {
                release = nil
            }
            DispatchQueue.main.async { self?.finishCheck(release: release) }
        }.resume()
    }

    private func finishCheck(release: Release?) {
        precondition(Thread.isMainThread)
        let wasManual = interaction.finishCheck()
        guard let release else { return }
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(latest, than: currentVersion) else {
            if wasManual { presentCurrentVersion() }
            return
        }
        guard displayedVersion != latest || wasManual else { return }
        displayedVersion = latest
        present(release: release, version: latest)
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

    private func presentCurrentVersion() {
        guard interaction.beginPrompt() else { return }
        defer { interaction.endPrompt() }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OrbitDrop is up to date"
        alert.informativeText = "Version \(currentVersion) is the newest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func present(release: Release, version: String) {
        guard interaction.beginPrompt() else { return }
        defer { interaction.endPrompt() }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OrbitDrop \(version) is available"
        alert.informativeText = "Install the update now? OrbitDrop will securely replace this copy and reopen automatically. No extra app or ZIP will be left in Downloads."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(release: release, version: version)
    }

    private func install(release: Release, version: String) {
        guard let archive = release.assets.first(where: { $0.name.hasSuffix("macOS-universal.zip") }),
              let checksums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
            present(error: UpdateError.missingAssets)
            return
        }
        guard interaction.beginInstall() else { return }
        UserDefaults.standard.set(version, forKey: Self.pendingUpdateKey)
        var checksumRequest = URLRequest(url: checksums.browserDownloadUrl)
        checksumRequest.timeoutInterval = 30
        checksumRequest.setValue("OrbitDrop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: checksumRequest) { [weak self] data, response, error in
            guard let self else { return }
            guard error == nil, let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  let expected = self.checksum(for: archive.name, in: text) else {
                self.finishWith(error: UpdateError.missingChecksum)
                return
            }
            self.download(archive: archive, expectedChecksum: expected, version: version)
        }.resume()
    }

    private func download(archive: Release.Asset, expectedChecksum: String, version: String) {
        var request = URLRequest(url: archive.browserDownloadUrl)
        request.timeoutInterval = 180
        request.setValue("OrbitDrop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: request) { [weak self] downloaded, response, error in
            guard let self else { return }
            guard error == nil, let downloaded,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                self.finishWith(error: error ?? UpdateError.invalidArchive)
                return
            }
            do {
                try self.stageAndInstall(downloaded: downloaded, expectedChecksum: expectedChecksum, version: version)
            } catch {
                self.finishWith(error: error)
            }
        }.resume()
    }

    private func stageAndInstall(downloaded: URL, expectedChecksum: String, version: String) throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("OrbitDrop-Update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let archive = work.appendingPathComponent("update.zip")
            try fileManager.moveItem(at: downloaded, to: archive)
            guard try sha256(of: archive).caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
                throw UpdateError.checksumMismatch
            }
            let expanded = work.appendingPathComponent("expanded", isDirectory: true)
            try fileManager.createDirectory(at: expanded, withIntermediateDirectories: true)
            // Release downloads can carry Gatekeeper provenance/quarantine metadata.
            // The archive has already passed its published SHA-256 check, so do not
            // copy transport-only metadata into the verified replacement bundle.
            guard run("/usr/bin/ditto", ["--noextattr", "--noqtn", "--noacl", "-x", "-k", archive.path, expanded.path]) == 0 else {
                throw UpdateError.invalidArchive
            }
            let stagedApp = expanded.appendingPathComponent("OrbitDrop.app", isDirectory: true)
            guard fileManager.fileExists(atPath: stagedApp.path) else { throw UpdateError.invalidArchive }
            guard Bundle(url: stagedApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
                throw UpdateError.invalidVersion
            }
            guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedApp.path]) == 0 else {
                throw UpdateError.invalidSignature
            }

            let installedApp = Bundle.main.bundleURL.standardizedFileURL
            guard installedApp.pathExtension == "app", fileManager.fileExists(atPath: installedApp.path) else {
                throw UpdateError.cannotInstall
            }
            let backup = installedApp.deletingLastPathComponent().appendingPathComponent(".OrbitDrop-backup-\(UUID().uuidString).app")
            let script = work.appendingPathComponent("install-update.sh")
            try updaterScript(pid: ProcessInfo.processInfo.processIdentifier, staged: stagedApp, installed: installedApp, backup: backup, work: work)
                .write(to: script, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

            let updater = Process()
            if fileManager.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) {
                updater.executableURL = URL(fileURLWithPath: "/bin/sh")
                updater.arguments = [script.path]
                try updater.run()
            } else {
                updater.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                let command = "/bin/sh \(shellQuote(script.path)) >/dev/null 2>&1 &"
                updater.arguments = ["-e", "do shell script \(appleScriptLiteral(command)) with administrator privileges"]
                try updater.run()
                updater.waitUntilExit()
                guard updater.terminationStatus == 0 else { throw UpdateError.cannotInstall }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
        } catch {
            try? fileManager.removeItem(at: work)
            throw error
        }
    }

    private func checksum(for filename: String, in manifest: String) -> String? {
        for line in manifest.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let listedName = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " *"))
            if listedName == filename, parts[0].count == 64 { return String(parts[0]) }
        }
        return nil
    }

    private func sha256(of file: URL) throws -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let hash = output.split(whereSeparator: \.isWhitespace).first else {
            throw UpdateError.checksumMismatch
        }
        return String(hash)
    }

    private func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func updaterScript(pid: Int32, staged: URL, installed: URL, backup: URL, work: URL) -> String {
        let source = shellQuote(staged.path)
        let target = shellQuote(installed.path)
        let saved = shellQuote(backup.path)
        let temporary = shellQuote(work.path)
        return """
        #!/bin/sh
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        success=0
        if /bin/mv \(target) \(saved) && /usr/bin/ditto --noextattr --noqtn --noacl \(source) \(target); then
          success=1
        fi
        if [ "$success" -eq 1 ]; then
          /usr/bin/open \(target)
          /bin/rm -rf \(saved)
        else
          /bin/rm -rf \(target)
          if [ -e \(saved) ]; then /bin/mv \(saved) \(target); fi
          if [ -e \(target) ]; then /usr/bin/open \(target); fi
        fi
        /bin/rm -rf \(temporary)
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func finishWith(error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.interaction.failInstall()
            UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
            self?.present(error: error)
        }
    }

    private func present(error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "OrbitDrop could not install the update"
        alert.informativeText = error.localizedDescription + " Your current app has not been changed."
        alert.runModal()
    }
}
