import Foundation

/// Caches PR diff file metadata + patches so we can reopen the review window
/// without refetching/parsing until the PR changes.
actor DiffCacheService {
    static let shared = DiffCacheService()

    struct CachedPRDiff: Codable {
        let key: String                 // "owner/repo#number"
        let updatedAt: Date             // PR.updatedAt at time of caching
        let files: [ChangedFile]        // includes per-file `patch`
        let cachedAt: Date
    }

    private var memory: [String: CachedPRDiff] = [:]

    private let cacheDir: URL

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        cacheDir = appSupport
            .appendingPathComponent("PRMaster", isDirectory: true)
            .appendingPathComponent("diff_cache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func loadDiff(for pr: EnrichedPullRequest) -> [ChangedFile]? {
        let key = cacheKey(for: pr)
        let updatedAt = pr.pr.updatedAt

        if let cached = memory[key], cached.updatedAt == updatedAt {
            return cached.files
        }

        let url = cacheFileURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedPRDiff.self, from: data),
              cached.updatedAt == updatedAt else {
            return nil
        }

        memory[key] = cached
        return cached.files
    }

    func saveDiff(for pr: EnrichedPullRequest, files: [ChangedFile]) {
        let key = cacheKey(for: pr)
        let cached = CachedPRDiff(
            key: key,
            updatedAt: pr.pr.updatedAt,
            files: files,
            cachedAt: Date()
        )

        memory[key] = cached

        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: cacheFileURL(forKey: key), options: .atomic)
        }
    }

    func invalidate(for pr: EnrichedPullRequest) {
        let key = cacheKey(for: pr)
        memory[key] = nil
        try? FileManager.default.removeItem(at: cacheFileURL(forKey: key))
    }

    private func cacheKey(for pr: EnrichedPullRequest) -> String {
        "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
    }

    private func cacheFileURL(forKey key: String) -> URL {
        // Make a filename-safe key
        let safe = key
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: "#", with: "_")
        return cacheDir.appendingPathComponent("diff_\(safe).json")
    }
}
