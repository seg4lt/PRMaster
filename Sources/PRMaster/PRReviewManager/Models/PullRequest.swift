import Foundation
import SwiftUI

struct PullRequest: Codable, Identifiable, Hashable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let author: Author?
    let repository: Repository

    var id: String {
        "\(repository.nameWithOwner)#\(number)"
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var isOpen: Bool {
        state.lowercased() == "open"
    }

    static func == (lhs: PullRequest, rhs: PullRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PRSearchResult: Codable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool?
    let author: Author?
    let repository: Repository

    func toPullRequest() -> PullRequest {
        PullRequest(
            number: number,
            title: title,
            url: url,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDraft: isDraft ?? false,
            author: author,
            repository: repository
        )
    }
}

struct PRDetailResponse: Codable {
    let data: PRDetailData
}

struct PRDetailData: Codable {
    let repository: PRDetailRepository?
}

struct PRDetailRepository: Codable {
    let pullRequest: PRDetail?
}

// For batch GraphQL response with dynamic keys (pr123, pr456, etc.)
struct BatchPRDetailResponse: Codable {
    let data: BatchPRDetailData
}

struct BatchPRDetailData: Codable {
    let repository: [String: PRDetail]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        guard let repoKey = container.allKeys.first(where: { $0.stringValue == "repository" }) else {
            repository = nil
            return
        }

        let repoContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: repoKey)
        var prDetails: [String: PRDetail] = [:]

        for key in repoContainer.allKeys {
            if key.stringValue.hasPrefix("pr") {
                if let detail = try? repoContainer.decode(PRDetail.self, forKey: key) {
                    prDetails[key.stringValue] = detail
                }
            }
        }

        repository = prDetails.isEmpty ? nil : prDetails
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct PRDetail: Codable {
    let reviewDecision: ReviewDecision?
    let reviews: ReviewNodes?
    let reviewRequests: ReviewRequestNodes?
    let comments: CommentInfo?
    let mergedBy: MergedBy?
    let mergedAt: Date?
    let mergeable: String?
    let mergeStateStatus: String?
    let commits: CommitNodes?

    var statusCheckRollup: StatusCheckRollup? {
        commits?.nodes.first?.commit.statusCheckRollup
    }

    var hasConflicts: Bool {
        mergeable == "CONFLICTING"
    }

    /// Returns the merge status considering both mergeable and mergeStateStatus
    var mergeableStatus: (icon: String, color: Color, text: String)? {
        // First check for conflicts
        if mergeable == "CONFLICTING" {
            return ("exclamationmark.triangle.fill", .red, "Conflicts")
        }

        // Then check mergeStateStatus for blocked/other states
        switch mergeStateStatus {
        case "BLOCKED":
            return ("xmark.octagon.fill", .orange, "Blocked")
        case "BEHIND":
            return ("arrow.down.circle", .yellow, "Behind")
        case "DIRTY":
            return ("exclamationmark.triangle.fill", .red, "Conflicts")
        case "UNSTABLE":
            return ("exclamationmark.circle", .orange, "Unstable")
        case "HAS_HOOKS":
            return ("hook.circle", .blue, "Has Hooks")
        case "CLEAN":
            return ("checkmark.circle.fill", .green, "Ready")
        case "UNKNOWN":
            if mergeable == "MERGEABLE" {
                return ("checkmark.circle", .green, "Mergeable")
            }
            return ("questionmark.circle", .secondary, "Unknown")
        default:
            // Fallback to mergeable status
            if mergeable == "MERGEABLE" {
                return ("checkmark.circle", .green, "Mergeable")
            }
            return nil
        }
    }
}

struct CommentInfo: Codable {
    let totalCount: Int
}

// MARK: - Commit Status Checks

struct CommitNodes: Codable {
    let nodes: [CommitNode]
}

struct CommitNode: Codable {
    let commit: CommitInfo
}

struct CommitInfo: Codable {
    let statusCheckRollup: StatusCheckRollup?
}

struct StatusCheckRollup: Codable {
    let state: String  // SUCCESS, PENDING, FAILURE, ERROR
    let contexts: CheckContextNodes?
}

struct CheckContextNodes: Codable {
    let nodes: [CheckContext]
}

struct CheckContext: Codable, Identifiable {
    // CheckRun fields (GitHub Actions, etc.)
    let name: String?
    let status: String?      // QUEUED, IN_PROGRESS, COMPLETED
    let conclusion: String?  // SUCCESS, FAILURE, NEUTRAL, CANCELLED, TIMED_OUT, ACTION_REQUIRED, SKIPPED
    let detailsUrl: String?
    // StatusContext fields (legacy - Jenkins, etc.)
    let context: String?
    let state: String?
    let targetUrl: String?

    var id: String { displayName + (url ?? "") }

    var displayName: String {
        name ?? context ?? "Unknown"
    }

    var url: String? {
        detailsUrl ?? targetUrl
    }

    var isSuccess: Bool {
        // CheckRun: conclusion == SUCCESS
        // StatusContext: state == SUCCESS
        conclusion?.uppercased() == "SUCCESS" || state?.uppercased() == "SUCCESS"
    }

    var isPending: Bool {
        // CheckRun: status != COMPLETED
        // StatusContext: state == PENDING
        if let status = status?.uppercased(), status != "COMPLETED" {
            return true
        }
        return state?.uppercased() == "PENDING"
    }

    var isFailed: Bool {
        let failedConclusions = ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"]
        if let conclusion = conclusion?.uppercased(), failedConclusions.contains(conclusion) {
            return true
        }
        let failedStates = ["FAILURE", "ERROR"]
        if let state = state?.uppercased(), failedStates.contains(state) {
            return true
        }
        return false
    }

    var icon: String {
        if isSuccess { return "checkmark.circle.fill" }
        if isPending { return "clock.fill" }
        if isFailed { return "xmark.circle.fill" }
        return "questionmark.circle"
    }

    var color: Color {
        if isSuccess { return .green }
        if isPending { return .orange }
        if isFailed { return .red }
        return .secondary
    }
}

struct ReviewNodes: Codable {
    let nodes: [Review]
}

struct ReviewRequestNodes: Codable {
    let nodes: [ReviewRequest]
}

struct ReviewRequest: Codable {
    let requestedReviewer: RequestedReviewer?
}

struct RequestedReviewer: Codable {
    let login: String?
    let name: String?

    var displayName: String {
        login ?? name ?? "Unknown"
    }
}

struct MergedBy: Codable {
    let login: String
}

struct EnrichedPullRequest: Identifiable, Codable {
    let pr: PullRequest
    let reviewDecision: ReviewDecision?
    let reviews: [Review]
    let requestedReviewers: [String]
    let mergedBy: String?
    let mergedAt: Date?
    let detail: PRDetail?

    var id: String { pr.id }

    var latestReviewsByAuthor: [String: Review] {
        var result: [String: Review] = [:]
        for review in reviews {
            if let login = review.author?.login {
                result[login] = review
            }
        }
        return result
    }

    /// Pending reviewers who haven't submitted a review yet
    var pendingReviewers: [String] {
        let reviewedAuthors = Set(reviews.compactMap { $0.author?.login })
        return requestedReviewers.filter { !reviewedAuthors.contains($0) }
    }
}
