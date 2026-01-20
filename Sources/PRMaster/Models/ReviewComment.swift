import Foundation
import SwiftUI

struct PullRequestReviewComment: Codable, Identifiable, Equatable {
    let id: Int
    let node_id: String
    let pull_request_review_id: Int?
    let diff_hunk: String?
    let path: String?
    let position: Int?
    let original_position: Int?
    let commit_id: String?
    let original_commit_id: String?
    let line: Int?
    let original_line: Int?
    let start_line: Int?
    let original_start_line: Int?
    let side: String?
    let start_side: String?
    let in_reply_to_id: Int?
    let user: CommentUser
    let body: String
    let created_at: Date
    let updated_at: Date
    let html_url: String?
    let author_association: String?
    let reactions: CommentReactions?

    var displayBody: String {
        body
    }

    var isMyComment: Bool {
        // TODO: Compare with current user login
        false
    }

    static func == (lhs: PullRequestReviewComment, rhs: PullRequestReviewComment) -> Bool {
        lhs.id == rhs.id
    }
}

struct CommentUser: Codable, Equatable {
    let login: String
    let id: Int
    let avatar_url: String?
    let html_url: String?

    var displayName: String {
        login
    }
}

struct CommentReactions: Codable {
    let total_count: Int
    let plus_one: Int?
    let minus_one: Int?
    let laugh: Int?
    let hooray: Int?
    let confused: Int?
    let heart: Int?
    let rocket: Int?
    let eyes: Int?
}

enum CommentSide: String, Codable {
    case left = "LEFT"
    case right = "RIGHT"

    var displayName: String {
        switch self {
        case .left: return "Removed"
        case .right: return "Added"
        }
    }
}

struct CommentDraft: Identifiable, Equatable {
    let id: UUID
    let filePath: String
    let line: Int
    let side: CommentSide
    var body: String
    var isModified: Bool
    var isNew: Bool
    var reviewId: String?
    var isSynced: Bool = false

    init(filePath: String, line: Int, side: CommentSide, body: String = "") {
        self.id = UUID()
        self.filePath = filePath
        self.line = line
        self.side = side
        self.body = body
        self.isModified = false
        self.isNew = true
        self.isSynced = false
    }

    static func == (lhs: CommentDraft, rhs: CommentDraft) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ReviewCommentViewModel: ObservableObject {
    @Published var comments: [PullRequestReviewComment] = []
    @Published var drafts: [CommentDraft] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var pendingReviewId: String?
    @Published var isPendingReviewActive: Bool = false

    private let pr: EnrichedPullRequest
    private let filePaths: [String]

    init(pr: EnrichedPullRequest, filePaths: [String] = []) {
        self.pr = pr
        self.filePaths = filePaths
    }

    func loadComments() async {
        isLoading = true
        error = nil

        do {
            let fetchedComments = try await GitHubService.shared.fetchReviewComments(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )

            // Filter comments for this PR's files
            comments = fetchedComments.filter { comment in
                guard let path = comment.path else { return false }
                if filePaths.isEmpty {
                    return true
                }
                return filePaths.contains(path)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func addDraft(filePath: String, line: Int, side: CommentSide) -> CommentDraft {
        let draft = CommentDraft(filePath: filePath, line: line, side: side)
        drafts.append(draft)
        return draft
    }

    func updateDraft(_ draft: CommentDraft, body: String) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index].body = body
            drafts[index].isModified = true
        }
    }

    func deleteDraft(_ draft: CommentDraft) {
        drafts.removeAll { $0.id == draft.id }
    }

    func clearDrafts() {
        drafts.removeAll()
        pendingReviewId = nil
        isPendingReviewActive = false
    }

    func getCommentsForLine(filePath: String, line: Int, side: CommentSide) -> [PullRequestReviewComment] {
        comments.filter { comment in
            comment.path == filePath &&
            comment.line == line &&
            comment.side == side.rawValue
        }
    }

    func getDraftForLine(filePath: String, line: Int, side: CommentSide) -> CommentDraft? {
        drafts.first { draft in
            draft.filePath == filePath &&
            draft.line == line &&
            draft.side == side
        }
    }

    func hasCommentsForLine(filePath: String, line: Int, side: CommentSide) -> Bool {
        !getCommentsForLine(filePath: filePath, line: line, side: side).isEmpty ||
        getDraftForLine(filePath: filePath, line: line, side: side) != nil
    }

    func loadPendingReviewIfExists() async throws {
        guard pendingReviewId == nil else { return }

        do {
            let reviews = try await GitHubService.shared.listReviewsForPullRequest(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )

            // Find pending review for current user
            if let pendingReview = reviews.first(where: { review in
                review.state == "PENDING" &&
                review.user.login == getCurrentUserLogin()
            ) {
                pendingReviewId = pendingReview.id
                isPendingReviewActive = true
            }
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func getCurrentUserLogin() -> String {
        // Get current user login from GH CLI
        UserDefaults.standard.string(forKey: "ghUsername") ?? "unknown"
    }
}
