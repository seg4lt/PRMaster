import Foundation

/// Represents a pending review comment stored on GitHub
struct PendingReview: Codable, Identifiable {
    let id: String
    let prKey: String
    var body: String?
    let commitId: String
    var comments: [PendingReviewComment]
    var createdAt: Date
    var isDirty: Bool  // Local changes not synced to GitHub

    var totalCommentCount: Int { comments.count }
}

/// Represents a single pending comment in a review
struct PendingReviewComment: Codable, Identifiable, Equatable {
    let id: String
    let path: String
    let line: Int
    let side: String  // LEFT or RIGHT
    var body: String
    var isLocalOnly: Bool  // Created locally, not yet submitted

    init(id: String = UUID().uuidString, path: String, line: Int, side: String, body: String, isLocalOnly: Bool = false) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.body = body
        self.isLocalOnly = isLocalOnly
    }

    static func == (lhs: PendingReviewComment, rhs: PendingReviewComment) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages pending reviews (drafts stored on GitHub)
actor PendingReviewService {
    static let shared = PendingReviewService()

    private var pendingReviews: [String: PendingReview] = [:]
    private var cacheFile: URL
    private var isLoaded = false

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let cacheDir = appSupport.appendingPathComponent("PRMaster", isDirectory: true)
        self.cacheFile = cacheDir.appendingPathComponent("pending_reviews.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }

        if let data = try? Data(contentsOf: cacheFile),
           let decoded = try? JSONDecoder().decode([String: PendingReview].self, from: data) {
            pendingReviews = decoded
        }
        isLoaded = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pendingReviews) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    /// Get or create pending review for a PR
    func getPendingReview(prKey: String, commitId: String) -> PendingReview {
        loadIfNeeded()
        if let existing = pendingReviews[prKey] {
            return existing
        }
        let newReview = PendingReview(
            id: UUID().uuidString,
            prKey: prKey,
            body: nil,
            commitId: commitId,
            comments: [],
            createdAt: Date(),
            isDirty: true
        )
        pendingReviews[prKey] = newReview
        save()
        return newReview
    }

    /// Update pending review
    func updatePendingReview(prKey: String, body: String?, comments: [PendingReviewComment]) {
        loadIfNeeded()
        if var existing = pendingReviews[prKey] {
            existing.body = body
            existing.comments = comments
            existing.isDirty = true
            pendingReviews[prKey] = existing
        }
        save()
    }

    /// Add or update a comment in pending review
    func upsertComment(prKey: String, comment: PendingReviewComment) {
        loadIfNeeded()
        if var existing = pendingReviews[prKey] {
            if let index = existing.comments.firstIndex(where: { $0.id == comment.id }) {
                existing.comments[index] = comment
            } else {
                existing.comments.append(comment)
            }
            existing.isDirty = true
            pendingReviews[prKey] = existing
        }
        save()
    }

    /// Remove a comment from pending review
    func removeComment(prKey: String, commentId: String) {
        loadIfNeeded()
        if var existing = pendingReviews[prKey] {
            existing.comments.removeAll { $0.id == commentId }
            existing.isDirty = true
            pendingReviews[prKey] = existing
        }
        save()
    }

    /// Clear pending review (after submission)
    func clearPendingReview(prKey: String) {
        loadIfNeeded()
        pendingReviews.removeValue(forKey: prKey)
        save()
    }

    /// Check if PR has a pending review
    func hasPendingReview(prKey: String) -> Bool {
        loadIfNeeded()
        return pendingReviews[prKey] != nil
    }

    /// Get all pending reviews
    func getAllPendingReviews() -> [PendingReview] {
        loadIfNeeded()
        return Array(pendingReviews.values)
    }
}
