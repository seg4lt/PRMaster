import Foundation

struct APICallLog: Identifiable {
    let id = UUID()
    let command: String
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
}

actor GitHubService {
    static let shared = GitHubService()

    private var totalRequests = 0
    private var sessionRequests = 0
    private var apiLogs: [APICallLog] = []

    private init() {}

    func getStats() -> (total: Int, session: Int, logs: [APICallLog]) {
        (totalRequests, sessionRequests, apiLogs)
    }

    private func logCall(_ command: String, duration: TimeInterval, success: Bool) {
        totalRequests += 1
        sessionRequests += 1
        apiLogs.append(APICallLog(command: command, timestamp: Date(), duration: duration, success: success))
        if apiLogs.count > 100 { apiLogs.removeFirst() }
    }

    func getCurrentUser() async throws -> String {
        let start = Date()
        let result = try await ShellExecutor.execute("gh api user --jq '.login'")
        logCall("getCurrentUser", duration: Date().timeIntervalSince(start), success: true)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getReviewRequests() async throws -> [PullRequest] {
        let command = """
        gh api graphql -f query='
        {
          search(query: "is:pr is:open review-requested:@me", type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                number
                title
                url
                createdAt
                updatedAt
                isDraft
                author { login avatarUrl }
                repository { nameWithOwner }
              }
            }
          }
        }' --jq '.data.search.nodes'
        """
        let start = Date()
        let result = try await ShellExecutor.execute(command)
        logCall("getReviewRequests", duration: Date().timeIntervalSince(start), success: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PullRequest].self, from: Data(result.utf8))
    }
}
