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

    init(filePath: String, line: Int, side: CommentSide, body: String = "") {
        self.id = UUID()
        self.filePath = filePath
        self.line = line
        self.side = side
        self.body = body
        self.isModified = false
        self.isNew = true
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
    @Published var hasPendingReview: Bool = false

    private let pr: EnrichedPullRequest
    private let filePaths: [String]
    private let prKey: String

    init(pr: EnrichedPullRequest, filePaths: [String] = []) {
        self.pr = pr
        self.filePaths = filePaths
        self.prKey = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
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

            // Check for pending reviews on GitHub
            let pendingReviews = try await GitHubService.shared.fetchPendingReviews(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )
            hasPendingReview = !pendingReviews.isEmpty

            // Load pending review comments if any
            if let pendingReview = pendingReviews.first {
                let pendingComments = try await GitHubService.shared.fetchPendingReviewComments(
                    owner: pr.pr.repository.owner,
                    repo: pr.pr.repository.name,
                    number: pr.pr.number,
                    reviewId: pendingReview.id
                )

                // Convert pending comments to drafts
                for pendingComment in pendingComments {
                    guard let path = pendingComment.path,
                          let line = pendingComment.line,
                          let sideString = pendingComment.side,
                          let side = CommentSide(rawValue: sideString.lowercased()) else {
                        continue
                    }

                    // Check if we already have a draft for this line
                    let existingDraft = getDraftForLine(filePath: path, line: line, side: side)
                    if existingDraft == nil {
                        let draft = CommentDraft(filePath: path, line: line, side: side, body: pendingComment.body)
                        drafts.append(draft)
                    }
                }
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
}
