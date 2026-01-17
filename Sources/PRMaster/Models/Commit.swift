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

struct WeeklyCommits: Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let commits: [Commit]

    var id: String {
        ISO8601DateFormatter().string(from: weekStart)
    }

    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: weekEnd)
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd)), \(year)"
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

struct WeeklySummary: Identifiable {
    var week: WeeklyCommits
    var status: SummaryStatus

    var id: String { week.id }
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
