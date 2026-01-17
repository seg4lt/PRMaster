import Foundation

actor CacheService {
    static let shared = CacheService()

    private let cacheDir: URL
    private let prCacheFile: URL
    private let notificationStateFile: URL

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        cacheDir = appSupport.appendingPathComponent("PRMaster", isDirectory: true)
        prCacheFile = cacheDir.appendingPathComponent("pr_cache.json")
        notificationStateFile = cacheDir.appendingPathComponent("notification_state.json")

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - PR Cache

    struct PRCache: Codable {
        var toReview: [EnrichedPullRequest]
        var reviewed: [EnrichedPullRequest]
        var myPRs: [EnrichedPullRequest]
        var currentUser: String?
        var timestamp: Date
    }

    func loadPRCache() -> PRCache? {
        guard let data = try? Data(contentsOf: prCacheFile),
              let cache = try? JSONDecoder().decode(PRCache.self, from: data) else {
            return nil
        }
        return cache
    }

    func savePRCache(toReview: [EnrichedPullRequest], reviewed: [EnrichedPullRequest], myPRs: [EnrichedPullRequest], currentUser: String?) {
        let cache = PRCache(toReview: toReview, reviewed: reviewed, myPRs: myPRs, currentUser: currentUser, timestamp: Date())
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: prCacheFile, options: .atomic)
        }
    }

    // MARK: - Notification State

    struct PRNotificationState: Codable {
        var key: String  // "owner/repo#number"
        var lastUpdatedAt: Date  // Track PR's updatedAt timestamp
        var notifiedForNew: Bool
        var lastSeen: Date
        // My PR tracking fields
        var activeReviewCount: Int?
        var reviewAuthors: [String]?  // Using Array for Codable (Set doesn't auto-conform)
        var commentCount: Int?
    }

    private var notificationStates: [String: PRNotificationState] = [:]
    private var statesLoaded = false

    private func loadStatesIfNeeded() {
        guard !statesLoaded else { return }
        if let data = try? Data(contentsOf: notificationStateFile),
           let states = try? JSONDecoder().decode([String: PRNotificationState].self, from: data) {
            notificationStates = states
        }
        statesLoaded = true
    }

    private func saveStates() {
        if let data = try? JSONEncoder().encode(notificationStates) {
            try? data.write(to: notificationStateFile, options: .atomic)
        }
    }

    func checkAndUpdateNotificationState(pr: EnrichedPullRequest) -> NotificationReason? {
        loadStatesIfNeeded()

        let key = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
        let currentUpdatedAt = pr.pr.updatedAt

        if let existing = notificationStates[key] {
            // Check if PR was updated since we last saw it
            if currentUpdatedAt > existing.lastUpdatedAt {
                notificationStates[key] = PRNotificationState(
                    key: key,
                    lastUpdatedAt: currentUpdatedAt,
                    notifiedForNew: true,
                    lastSeen: Date()
                )
                saveStates()
                return .newCommits
            }

            // Already notified, no changes
            return nil
        } else {
            // New PR we haven't seen
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: currentUpdatedAt,
                notifiedForNew: true,
                lastSeen: Date()
            )
            saveStates()
            return .newPR
        }
    }

    // Update state without triggering notification (for PRs we've seen but don't need to notify about)
    func markAsSeen(pr: EnrichedPullRequest) {
        loadStatesIfNeeded()

        let key = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
        if notificationStates[key] == nil {
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: pr.pr.updatedAt,
                notifiedForNew: true,
                lastSeen: Date()
            )
            saveStates()
        }
    }

    enum NotificationReason {
        case newPR
        case newCommits
    }

    // MARK: - My PR Notifications

    enum MyPRNotificationReason {
        case newReview(by: String)
        case newComment
    }

    func checkMyPRNotificationState(pr: EnrichedPullRequest) -> MyPRNotificationReason? {
        loadStatesIfNeeded()

        let key = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"

        // Count active (non-dismissed) reviews
        let activeReviews = pr.reviews.filter { $0.state != .dismissed }
        let currentReviewCount = activeReviews.count
        let currentReviewers = Set(activeReviews.compactMap { $0.author?.login })
        let currentCommentCount = pr.detail?.comments?.totalCount ?? 0

        guard let existing = notificationStates[key], existing.reviewAuthors != nil else {
            // PR not tracked yet, or My PR fields not initialized - store state, don't notify
            let prev = notificationStates[key]
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: pr.pr.updatedAt,
                notifiedForNew: prev?.notifiedForNew ?? true,
                lastSeen: Date(),
                activeReviewCount: currentReviewCount,
                reviewAuthors: Array(currentReviewers),
                commentCount: currentCommentCount
            )
            saveStates()
            return nil
        }

        // Check for review dismissal (user pushed commits)
        // When reviews are dismissed, reset tracking so new reviews trigger notifications
        if let prevCount = existing.activeReviewCount, currentReviewCount < prevCount {
            // Reviews were dismissed - reset tracking state
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: pr.pr.updatedAt,
                notifiedForNew: true,
                lastSeen: Date(),
                activeReviewCount: currentReviewCount,
                reviewAuthors: Array(currentReviewers),
                commentCount: currentCommentCount
            )
            saveStates()
            return nil  // Don't notify on dismissal
        }

        // Check for new reviews
        if let prevAuthors = existing.reviewAuthors {
            let prevAuthorsSet = Set(prevAuthors)
            let newReviewers = currentReviewers.subtracting(prevAuthorsSet)
            if let reviewer = newReviewers.first {
                notificationStates[key] = PRNotificationState(
                    key: key,
                    lastUpdatedAt: pr.pr.updatedAt,
                    notifiedForNew: true,
                    lastSeen: Date(),
                    activeReviewCount: currentReviewCount,
                    reviewAuthors: Array(currentReviewers),
                    commentCount: currentCommentCount
                )
                saveStates()
                return .newReview(by: reviewer)
            }
        }

        // Check for new comments
        if let prevComments = existing.commentCount, currentCommentCount > prevComments {
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: pr.pr.updatedAt,
                notifiedForNew: true,
                lastSeen: Date(),
                activeReviewCount: currentReviewCount,
                reviewAuthors: Array(currentReviewers),
                commentCount: currentCommentCount
            )
            saveStates()
            return .newComment
        }

        // No changes worth notifying about, but update the state
        if existing.activeReviewCount != currentReviewCount ||
           existing.commentCount != currentCommentCount {
            notificationStates[key] = PRNotificationState(
                key: key,
                lastUpdatedAt: pr.pr.updatedAt,
                notifiedForNew: true,
                lastSeen: Date(),
                activeReviewCount: currentReviewCount,
                reviewAuthors: Array(currentReviewers),
                commentCount: currentCommentCount
            )
            saveStates()
        }

        return nil
    }
}
