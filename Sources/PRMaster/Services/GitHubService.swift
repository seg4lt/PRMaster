import Foundation

struct APICallLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let command: String
    let duration: TimeInterval
    let success: Bool
}

actor GitHubService {
    static let shared = GitHubService()

    private let shell = ShellExecutor.shared
    private let decoder: JSONDecoder

    // Request tracking
    private(set) var totalRequests: Int = 0
    private(set) var sessionRequests: Int = 0
    private(set) var callLogs: [APICallLog] = []
    private let maxLogEntries = 100

    private init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                // Don't retry on auth errors or CLI not found
                if let shellError = error as? ShellError {
                    switch shellError {
                    case .commandNotFound:
                        throw error
                    case .commandFailed(let output, _):
                        if output.contains("401") || output.contains("403") && !output.contains("rate limit") {
                            throw error
                        }
                    }
                }
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                }
            }
        }
        throw lastError!
    }

    private func trackCall(command: String, duration: TimeInterval, success: Bool) {
        totalRequests += 1
        sessionRequests += 1

        let log = APICallLog(
            timestamp: Date(),
            command: command,
            duration: duration,
            success: success
        )
        callLogs.append(log)

        // Keep only last N entries
        if callLogs.count > maxLogEntries {
            callLogs.removeFirst(callLogs.count - maxLogEntries)
        }
    }

    func resetSessionCount() {
        sessionRequests = 0
    }

    func getStats() -> (total: Int, session: Int, logs: [APICallLog]) {
        (totalRequests, sessionRequests, callLogs)
    }

    /// Add an external API call log (used by other services like ClaudeProvider)
    func addExternalLog(command: String, duration: TimeInterval, success: Bool, prompt: String? = nil) {
        var logCommand = command
        if let prompt = prompt {
            // Truncate long prompts for display
            let truncated = prompt.count > 100 ? String(prompt.prefix(100)) + "..." : prompt
            logCommand = "\(command): \(truncated)"
        }
        trackCall(command: logCommand, duration: duration, success: success)
    }

    func getCurrentUser() async throws -> String {
        let start = Date()
        do {
            let result = try await shell.executeGH(["api", "user", "--jq", ".login"])
            trackCall(command: "api user", duration: Date().timeIntervalSince(start), success: true)
            return result
        } catch {
            trackCall(command: "api user", duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func fetchPRsToReview() async throws -> [PullRequest] {
        let start = Date()
        let command = "search prs --review-requested @me"
        do {
            let json = try await withRetry {
                try await shell.executeGH([
                    "search", "prs",
                    "--review-requested", "@me",
                    "--state", "open",
                    "--limit", "100",
                    "--json", "number,title,url,state,createdAt,updatedAt,isDraft,author,repository"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !json.isEmpty else { return [] }
            let results = try decoder.decode([PRSearchResult].self, from: Data(json.utf8))
            return results.map { $0.toPullRequest() }
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func fetchReviewedPRs() async throws -> [PullRequest] {
        let start = Date()
        let command = "search prs --reviewed-by @me"
        do {
            let json = try await withRetry {
                try await shell.executeGH([
                    "search", "prs",
                    "--reviewed-by", "@me",
                    "--state", "open",
                    "--limit", "100",
                    "--json", "number,title,url,state,createdAt,updatedAt,isDraft,author,repository"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !json.isEmpty else { return [] }
            let results = try decoder.decode([PRSearchResult].self, from: Data(json.utf8))
            return results.map { $0.toPullRequest() }
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func fetchMyPRs(state: String = "open") async throws -> [PullRequest] {
        let start = Date()
        let command = "search prs --author @me --state \(state)"
        do {
            let json = try await withRetry {
                try await shell.executeGH([
                    "search", "prs",
                    "--author", "@me",
                    "--state", state,
                    "--limit", "100",
                    "--json", "number,title,url,state,createdAt,updatedAt,isDraft,author,repository"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !json.isEmpty else { return [] }
            let results = try decoder.decode([PRSearchResult].self, from: Data(json.utf8))
            return results.map { $0.toPullRequest() }
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func fetchPRDetail(owner: String, repo: String, number: Int) async throws -> PRDetail? {
        let results = try await fetchPRDetailsBatch(owner: owner, repo: repo, numbers: [number])
        return results[number]
    }

    func fetchPRDetailsBatch(owner: String, repo: String, numbers: [Int]) async throws -> [Int: PRDetail] {
        guard !numbers.isEmpty else { return [:] }

        let start = Date()
        let command = "graphql batch \(repo) (\(numbers.count) PRs)"

        let prFragment = """
              headRefName
              baseRefName
              reviewDecision
              reviews(first: 50) {
                nodes {
                  author { login }
                  state
                }
              }
              reviewRequests(first: 20) {
                nodes {
                  requestedReviewer {
                    ... on User { login }
                    ... on Team { name }
                  }
                }
              }
              comments(first: 1) {
                totalCount
              }
              mergedBy { login }
              mergedAt
              mergeable
              mergeStateStatus
              commits(last: 1) {
                nodes {
                  commit {
                    statusCheckRollup {
                      state
                      contexts(first: 50) {
                        nodes {
                          ... on CheckRun {
                            name
                            status
                            conclusion
                            detailsUrl
                          }
                          ... on StatusContext {
                            context
                            state
                            targetUrl
                          }
                        }
                      }
                    }
                  }
                }
              }
              files(first: 100) {
                nodes {
                  path
                }
              }
        """

        let prQueries = numbers.map { number in
            "pr\(number): pullRequest(number: \(number)) {\n\(prFragment)\n}"
        }.joined(separator: "\n")

        let query = """
        query {
          repository(owner: "\(owner)", name: "\(repo)") {
            \(prQueries)
          }
        }
        """

        do {
            let json = try await withRetry {
                try await shell.executeGH([
                    "api", "graphql",
                    "-f", "query=\(query)"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !json.isEmpty else { return [:] }
            let response = try decoder.decode(BatchPRDetailResponse.self, from: Data(json.utf8))

            var results: [Int: PRDetail] = [:]
            if let prDetails = response.data.repository {
                for (key, detail) in prDetails {
                    if let number = Int(key.dropFirst(2)) { // Remove "pr" prefix
                        results[number] = detail
                    }
                }
            }
            return results
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func enrichPR(_ pr: PullRequest) async throws -> EnrichedPullRequest {
        let detail = try await fetchPRDetail(
            owner: pr.repository.owner,
            repo: pr.repository.shortName,
            number: pr.number
        )

        let requestedReviewers = detail?.reviewRequests?.nodes.compactMap {
            $0.requestedReviewer?.displayName
        } ?? []

        return EnrichedPullRequest(
            pr: pr,
            reviewDecision: detail?.reviewDecision,
            reviews: detail?.reviews?.nodes ?? [],
            requestedReviewers: requestedReviewers,
            mergedBy: detail?.mergedBy?.login,
            mergedAt: detail?.mergedAt,
            detail: detail
        )
    }

    func enrichPRs(_ prs: [PullRequest]) async throws -> [EnrichedPullRequest] {
        // Group PRs by repository
        var prsByRepo: [String: [PullRequest]] = [:]
        for pr in prs {
            let repoKey = pr.repository.nameWithOwner
            prsByRepo[repoKey, default: []].append(pr)
        }

        // Fetch details in parallel per repository (batched within each repo)
        return try await withThrowingTaskGroup(of: [EnrichedPullRequest].self) { group in
            for (_, repoPRs) in prsByRepo {
                group.addTask {
                    guard let firstPR = repoPRs.first else { return [] }
                    let owner = firstPR.repository.owner
                    let repo = firstPR.repository.shortName
                    let numbers = repoPRs.map { $0.number }

                    let details = try await self.fetchPRDetailsBatch(owner: owner, repo: repo, numbers: numbers)

                    return repoPRs.map { pr in
                        let detail = details[pr.number]
                        let requestedReviewers = detail?.reviewRequests?.nodes.compactMap {
                            $0.requestedReviewer?.displayName
                        } ?? []

                        return EnrichedPullRequest(
                            pr: pr,
                            reviewDecision: detail?.reviewDecision,
                            reviews: detail?.reviews?.nodes ?? [],
                            requestedReviewers: requestedReviewers,
                            mergedBy: detail?.mergedBy?.login,
                            mergedAt: detail?.mergedAt,
                            detail: detail
                        )
                    }
                }
            }

            var enriched: [EnrichedPullRequest] = []
            for try await results in group {
                enriched.append(contentsOf: results)
            }
            return enriched.sorted { $0.pr.updatedAt > $1.pr.updatedAt }
        }
    }

    func checkGHInstalled() async -> Bool {
        do {
            _ = try await shell.executeGH(["--version"])
            return true
        } catch {
            return false
        }
    }

    func checkGHAuthenticated() async -> Bool {
        do {
            _ = try await shell.executeGH(["auth", "status"])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Commit Fetching

    func fetchUserCommits(
        author: String,
        startDate: Date,
        endDate: Date,
        repos: [String] = []
    ) async throws -> [Commit] {
        let start = Date()

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)

        // Build search query
        var query = "author:\(author) author-date:\(startStr)..\(endStr)"

        // Add repo filters if provided
        if !repos.isEmpty {
            let repoQueries = repos.map { "repo:\($0)" }.joined(separator: " ")
            query += " \(repoQueries)"
        }

        let command = "search commits"

        do {
            let json = try await withRetry {
                try await self.shell.executeGH([
                    "api", "search/commits",
                    "-X", "GET",
                    "-H", "Accept: application/vnd.github.cloak-preview+json",
                    "-f", "q=\(query)",
                    "-f", "sort=author-date",
                    "-f", "order=asc",
                    "-f", "per_page=100"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !json.isEmpty else { return [] }
            let response = try decoder.decode(CommitSearchResponse.self, from: Data(json.utf8))
            return response.items.map { $0.toCommit() }
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }
}
