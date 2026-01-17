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
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
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
