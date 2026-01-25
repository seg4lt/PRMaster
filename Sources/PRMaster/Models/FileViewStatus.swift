import Foundation

/// Tracks the view status of files in a PR review
struct FileViewStatus: Codable, Identifiable, Equatable {
    let prKey: String  // "owner/repo#prNumber"
    let filePath: String
    var isViewed: Bool
    var viewedAt: Date?
    var viewDuration: TimeInterval?  // How long the user spent viewing this file

    var id: String { "\(prKey)-\(filePath)" }

    init(prKey: String, filePath: String, isViewed: Bool = false) {
        self.prKey = prKey
        self.filePath = filePath
        self.isViewed = isViewed
        self.viewedAt = nil
        self.viewDuration = nil
    }
}

/// Manages file view status for all PRs
actor FileViewStatusService {
    static let shared = FileViewStatusService()

    private var statusCache: [String: FileViewStatus] = [:]
    private let cacheFile: URL
    private var isLoaded = false

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let cacheDir = appSupport.appendingPathComponent("PRMaster", isDirectory: true)
        self.cacheFile = cacheDir.appendingPathComponent("file_view_status.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }

        if let data = try? Data(contentsOf: cacheFile),
           let decoded = try? JSONDecoder().decode([String: FileViewStatus].self, from: data) {
            statusCache = decoded
        }
        isLoaded = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(statusCache) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    /// Get view status for all files in a PR
    func getStatusForPR(prKey: String, filePaths: [String]) -> [String: FileViewStatus] {
        loadIfNeeded()
        var result: [String: FileViewStatus] = [:]

        for filePath in filePaths {
            let key = "\(prKey)-\(filePath)"
            if let existing = statusCache[key] {
                result[filePath] = existing
            } else {
                let newStatus = FileViewStatus(prKey: prKey, filePath: filePath)
                statusCache[key] = newStatus
                result[filePath] = newStatus
            }
        }

        return result
    }

    /// Mark a file as viewed
    func markAsViewed(prKey: String, filePath: String, duration: TimeInterval? = nil) {
        loadIfNeeded()
        let key = "\(prKey)-\(filePath)"

        if var existing = statusCache[key] {
            existing.isViewed = true
            existing.viewedAt = Date()
            existing.viewDuration = duration
            statusCache[key] = existing
        } else {
            var newStatus = FileViewStatus(prKey: prKey, filePath: filePath, isViewed: true)
            newStatus.viewedAt = Date()
            newStatus.viewDuration = duration
            statusCache[key] = newStatus
        }

        save()
    }

    /// Mark a file as unviewed (e.g., if it was updated)
    func markAsUnviewed(prKey: String, filePath: String) {
        loadIfNeeded()
        let key = "\(prKey)-\(filePath)"

        if var existing = statusCache[key] {
            existing.isViewed = false
            existing.viewedAt = nil
            existing.viewDuration = nil
            statusCache[key] = existing
        }

        save()
    }

    /// Reset all files in a PR to unviewed (e.g., after new commits)
    func resetPR(prKey: String) {
        loadIfNeeded()
        let keysToRemove = statusCache.keys.filter { $0.hasPrefix("\(prKey)-") }
        for key in keysToRemove {
            if var existing = statusCache[key] {
                existing.isViewed = false
                existing.viewedAt = nil
                existing.viewDuration = nil
                statusCache[key] = existing
            }
        }
        save()
    }

    /// Get statistics for a PR
    func getStatsForPR(prKey: String) -> (viewed: Int, total: Int) {
        loadIfNeeded()
        let allStatuses = statusCache.values.filter { $0.prKey == prKey }
        let viewed = allStatuses.filter { $0.isViewed }.count
        return (viewed, allStatuses.count)
    }

    /// Clear all file view statuses for a PR (e.g., after review submission)
    func clearPR(prKey: String) {
        loadIfNeeded()
        let keysToRemove = statusCache.keys.filter { $0.hasPrefix("\(prKey)-") }
        for key in keysToRemove {
            statusCache.removeValue(forKey: key)
        }
        save()
    }
}
