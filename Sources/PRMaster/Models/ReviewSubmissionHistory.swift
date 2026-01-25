import Foundation

/// Tracks the user's review submission history for incremental diffs
struct ReviewSubmissionHistory: Codable {
    let prKey: String  // "owner/repo#prNumber"
    var lastReviewCommit: String?  // The HEAD commit when user last reviewed
    var lastReviewAt: Date?
    var lastReviewEvent: String?  // APPROVE, REQUEST_CHANGES, COMMENT
    var reviewCount: Int

    init(prKey: String) {
        self.prKey = prKey
        self.lastReviewCommit = nil
        self.lastReviewAt = nil
        self.lastReviewEvent = nil
        self.reviewCount = 0
    }

    /// Record a review submission
    mutating func recordReview(commitId: String, event: String) {
        lastReviewCommit = commitId
        lastReviewAt = Date()
        lastReviewEvent = event
        reviewCount += 1
    }

    /// Clear review history (e.g., after PR is merged/closed)
    mutating func clear() {
        lastReviewCommit = nil
        lastReviewAt = nil
        lastReviewEvent = nil
        reviewCount = 0
    }

    /// Check if there are new commits since last review
    func hasNewCommits(currentHeadCommit: String) -> Bool {
        guard let lastCommit = lastReviewCommit else { return false }
        return lastCommit != currentHeadCommit
    }
}

/// Manages review submission history
actor ReviewHistoryService {
    static let shared = ReviewHistoryService()

    private var historyCache: [String: ReviewSubmissionHistory] = [:]
    private let cacheFile: URL
    private var isLoaded = false

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let cacheDir = appSupport.appendingPathComponent("PRMaster", isDirectory: true)
        self.cacheFile = cacheDir.appendingPathComponent("review_history.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }

        if let data = try? Data(contentsOf: cacheFile),
           let decoded = try? JSONDecoder().decode([String: ReviewSubmissionHistory].self, from: data) {
            historyCache = decoded
        }
        isLoaded = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(historyCache) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    /// Get or create history for a PR
    func getHistory(prKey: String) -> ReviewSubmissionHistory {
        loadIfNeeded()
        if let existing = historyCache[prKey] {
            return existing
        }
        let newHistory = ReviewSubmissionHistory(prKey: prKey)
        historyCache[prKey] = newHistory
        save()
        return newHistory
    }

    /// Record a review submission
    func recordReview(prKey: String, commitId: String, event: String) {
        loadIfNeeded()
        var history = getHistory(prKey: prKey)
        history.recordReview(commitId: commitId, event: event)
        historyCache[prKey] = history
        save()
    }

    /// Clear history for a PR
    func clearHistory(prKey: String) {
        loadIfNeeded()
        historyCache.removeValue(forKey: prKey)
        save()
    }

    /// Clear all history (e.g., for clean slate)
    func clearAll() {
        loadIfNeeded()
        historyCache.removeAll()
        save()
    }
}
