import Foundation

struct Commit: Codable, Identifiable {
    let sha: String
    let message: String
    let authorDate: Date
    let repository: String  // owner/repo

    var id: String { sha }

    var shortSha: String {
        String(sha.prefix(7))
    }

    var firstLine: String {
        message.components(separatedBy: .newlines).first ?? message
    }
}

struct DateRangeCommits: Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let commits: [Commit]
    private let cachedCommitCount: Int?

    init(id: UUID = UUID(), startDate: Date, endDate: Date, commits: [Commit], cachedCommitCount: Int? = nil) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.commits = commits
        self.cachedCommitCount = cachedCommitCount
    }

    var commitCount: Int {
        cachedCommitCount ?? commits.count
    }

    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        // Check if single day (same date)
        let calendar = Calendar.current
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        }

        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

enum SummaryStatus: Equatable {
    case pending
    case loading
    case completed(String)
    case error(String)

    static func == (lhs: SummaryStatus, rhs: SummaryStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case (.loading, .loading):
            return true
        case (.completed(let l), .completed(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

struct DateRangeSummary: Identifiable {
    let id: UUID
    var dateRange: DateRangeCommits
    var status: SummaryStatus
    let createdAt: Date
    var repositories: [String]

    init(id: UUID = UUID(), dateRange: DateRangeCommits, status: SummaryStatus, createdAt: Date = Date(), repositories: [String] = []) {
        self.id = id
        self.dateRange = dateRange
        self.repositories = repositories
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - GitHub API Response Models

struct CommitSearchResponse: Codable {
    let items: [CommitSearchItem]
}

struct CommitSearchItem: Codable {
    let sha: String
    let commit: CommitDetail
    let repository: CommitRepository

    struct CommitDetail: Codable {
        let message: String
        let author: CommitAuthor
    }

    struct CommitAuthor: Codable {
        let date: Date
    }

    struct CommitRepository: Codable {
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    func toCommit() -> Commit {
        Commit(
            sha: sha,
            message: commit.message,
            authorDate: commit.author.date,
            repository: repository.fullName
        )
    }
}

/// Response model for per-repo commits API
struct RepoCommitItem: Codable {
    let sha: String
    let commit: RepoCommitDetail

    struct RepoCommitDetail: Codable {
        let message: String
        let author: RepoCommitAuthor
    }

    struct RepoCommitAuthor: Codable {
        let date: Date
    }

    func toCommit(repository: String) -> Commit {
        Commit(
            sha: sha,
            message: commit.message,
            authorDate: commit.author.date,
            repository: repository
        )
    }
}

// MARK: - Enriched Commit (with diff)

enum CommitSizeCategory {
    case small   // < 2K tokens - batch up to 30
    case medium  // 2K-10K tokens - batch 3-6
    case large   // 10K-50K tokens - individual
    case huge    // > 50K tokens - truncate
}

struct EnrichedCommit {
    let commit: Commit
    let diff: String?

    /// Rough token estimate based on configurable ratio (default 2 chars/token for code)
    var estimatedTokens: Int {
        let ratio = UserDefaults.standard.integer(forKey: "tokenRatio")
        let effectiveRatio = ratio > 0 ? ratio : 2  // Default to 2
        return (commit.message.count + (diff?.count ?? 0)) / effectiveRatio
    }

    var sizeCategory: CommitSizeCategory {
        switch estimatedTokens {
        case 50_001...: return .huge
        case 10_001...50_000: return .large
        case 2_001...10_000: return .medium
        default: return .small
        }
    }

}
