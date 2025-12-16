import Foundation

actor GitHubService {
    static let shared = GitHubService()
    private init() {}

    func getCurrentUser() async throws -> String {
        let result = try await ShellExecutor.execute("gh api user --jq '.login'")
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
        let result = try await ShellExecutor.execute(command)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PullRequest].self, from: Data(result.utf8))
    }
}
