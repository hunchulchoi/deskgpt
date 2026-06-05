import Cocoa
import Foundation

protocol UpdateManagerDelegate: AnyObject {
    func updateManager(_ manager: UpdateManager, didPrepareUpdate version: String, downloadURL: URL)
}

extension UpdateManagerDelegate {
    func updateManager(_ manager: UpdateManager, didPrepareUpdate version: String, downloadURL: URL) {}
}

enum UpdateDefaultsKey {
    static let autoUpdateEnabled = "DeskGPTAutoUpdateEnabled"
    static let pendingUpdateVersion = "DeskGPTPendingUpdateVersion"
    static let pendingUpdateDownloadPath = "DeskGPTPendingUpdateDownloadPath"
    static let lastUpdateCheckDate = "DeskGPTLastUpdateCheckDate"
}

struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

final class UpdateManager {
    static let shared = UpdateManager()

    weak var delegate: UpdateManagerDelegate?

    private let repositoryLatestReleaseURL = URL(string: "https://api.github.com/repos/hunchulchoi/deskgpt/releases/latest")!
    private let urlSession: URLSession
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let updateInterval: TimeInterval = 12 * 60 * 60

    private var updateTimer: DispatchSourceTimer?
    private var isCheckingForUpdates = false
    private var activeDownloadTask: URLSessionDownloadTask?

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "DeskGPT/1.0 (macOS)"
        ]
        self.urlSession = URLSession(configuration: configuration)
    }

    func start() {
        ensureUpdatesDirectoryExists()
        clearPendingUpdateIfAlreadyInstalled()
        restorePendingUpdateIfAvailable()
        rescheduleTimerIfNeeded()
    }

    func stop() {
        updateTimer?.cancel()
        updateTimer = nil
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
    }

    func isAutoUpdateEnabled() -> Bool {
        if userDefaults.object(forKey: UpdateDefaultsKey.autoUpdateEnabled) == nil {
            userDefaults.set(true, forKey: UpdateDefaultsKey.autoUpdateEnabled)
            return true
        }
        return userDefaults.bool(forKey: UpdateDefaultsKey.autoUpdateEnabled)
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: UpdateDefaultsKey.autoUpdateEnabled)
        rescheduleTimerIfNeeded()
        if enabled {
            checkForUpdatesNow()
        }
    }

    func pendingUpdateVersion() -> String? {
        userDefaults.string(forKey: UpdateDefaultsKey.pendingUpdateVersion)
    }

    func pendingUpdateDownloadURL() -> URL? {
        guard let path = userDefaults.string(forKey: UpdateDefaultsKey.pendingUpdateDownloadPath) else { return nil }
        let url = URL(fileURLWithPath: path)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func checkForUpdatesNow(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard force || isAutoUpdateEnabled() || pendingUpdateVersion() != nil else {
            completion?(false)
            return
        }
        guard !isCheckingForUpdates else {
            completion?(false)
            return
        }

        isCheckingForUpdates = true
        userDefaults.set(Date(), forKey: UpdateDefaultsKey.lastUpdateCheckDate)

        let request = URLRequest(url: repositoryLatestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            defer { self.isCheckingForUpdates = false }

            if let error = error {
                print("⚠️ Update check failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                print("⚠️ Update check failed: unexpected response")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            guard let data = data else {
                print("⚠️ Update check failed: empty response body")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.handleLatestRelease(release, completion: completion)
            } catch {
                print("⚠️ Update check decode failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
        task.resume()
    }

    private func handleLatestRelease(_ release: GitHubRelease, completion: ((Bool) -> Void)?) {
        let latestVersion = normalizedVersion(from: release.tagName)
        let currentVersion = currentAppVersion

        guard isVersion(latestVersion, newerThan: currentVersion) else {
            clearPendingUpdateIfAlreadyInstalled()
            DispatchQueue.main.async { completion?(false) }
            return
        }

        let existingDownloadURL = pendingUpdateDownloadURL()
        if pendingUpdateVersion() == latestVersion, let existingDownloadURL = existingDownloadURL {
            notifyPendingUpdate(version: latestVersion, downloadURL: existingDownloadURL, completion: completion)
            return
        }

        guard let asset = preferredDMGAsset(from: release.assets) else {
            print("⚠️ Update check failed: no DMG asset found for \(latestVersion)")
            DispatchQueue.main.async { completion?(false) }
            return
        }

        downloadReleaseAsset(asset.browserDownloadURL, version: latestVersion, completion: completion)
    }

    private func preferredDMGAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }
    }

    private func downloadReleaseAsset(_ remoteURL: URL, version: String, completion: ((Bool) -> Void)?) {
        ensureUpdatesDirectoryExists()

        let destinationURL = updatesDirectory.appendingPathComponent("DeskGPT-\(version).dmg")
        if fileManager.fileExists(atPath: destinationURL.path) {
            persistPendingUpdate(version: version, downloadPath: destinationURL)
            notifyPendingUpdate(version: version, downloadURL: destinationURL, completion: completion)
            return
        }

        activeDownloadTask?.cancel()
        let task = urlSession.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            self.activeDownloadTask = nil

            if let error = error {
                print("⚠️ Update download failed: \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                print("⚠️ Update download failed: missing temporary file URL")
                return
            }

            do {
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }
                try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                self.persistPendingUpdate(version: version, downloadPath: destinationURL)
                self.notifyPendingUpdate(version: version, downloadURL: destinationURL, completion: completion)
            } catch {
                print("⚠️ Update download save failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
        activeDownloadTask = task
        task.resume()
    }

    private func notifyPendingUpdate(version: String, downloadURL: URL, completion: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            self.delegate?.updateManager(self, didPrepareUpdate: version, downloadURL: downloadURL)
            completion?(true)
        }
    }

    private func persistPendingUpdate(version: String, downloadPath: URL) {
        userDefaults.set(version, forKey: UpdateDefaultsKey.pendingUpdateVersion)
        userDefaults.set(downloadPath.path, forKey: UpdateDefaultsKey.pendingUpdateDownloadPath)
    }

    private func restorePendingUpdateIfAvailable() {
        guard let version = pendingUpdateVersion() else {
            return
        }

        guard let downloadURL = pendingUpdateDownloadURL() else {
            clearPendingUpdate()
            return
        }

        if isVersion(currentAppVersion, newerThanOrEqualTo: version) {
            clearPendingUpdate()
            return
        }

        notifyPendingUpdate(version: version, downloadURL: downloadURL, completion: nil)
    }

    private func clearPendingUpdateIfAlreadyInstalled() {
        guard let version = pendingUpdateVersion() else { return }
        if isVersion(currentAppVersion, newerThanOrEqualTo: version) {
            clearPendingUpdate()
        }
    }

    private func clearPendingUpdate() {
        userDefaults.removeObject(forKey: UpdateDefaultsKey.pendingUpdateVersion)
        userDefaults.removeObject(forKey: UpdateDefaultsKey.pendingUpdateDownloadPath)
    }

    private func rescheduleTimerIfNeeded() {
        updateTimer?.cancel()
        updateTimer = nil

        guard isAutoUpdateEnabled() else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + updateInterval, repeating: updateInterval, leeway: .seconds(600))
        timer.setEventHandler { [weak self] in
            self?.checkForUpdatesNow()
        }
        timer.resume()
        updateTimer = timer
    }

    private func ensureUpdatesDirectoryExists() {
        do {
            try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("⚠️ Unable to create updates directory: \(error.localizedDescription)")
        }
    }

    private var updatesDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskGPT/Updates", isDirectory: true)
    }

    private var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func normalizedVersion(from tagName: String) -> String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }

    private func isVersion(_ lhs: String, newerThanOrEqualTo rhs: String) -> Bool {
        let comparison = lhs.compare(rhs, options: .numeric)
        return comparison == .orderedDescending || comparison == .orderedSame
    }
}
