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
                        if (output.contains("401") || output.contains("403")) && !output.contains("rate limit") {
                            throw error
                        }
                    case .timeout:
                        // Timeouts can be retried
                        break
                    }
                }
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                }
            }
        }
        throw lastError ?? NSError(
            domain: "GitHubService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Retry failed with no attempts"]
        )
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
        while callLogs.count > maxLogEntries {
            callLogs.removeFirst()
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

    func fetchPRDiff(owner: String, repo: String, number: Int) async throws -> PRDetail? {
        let start = Date()
        let command = "graphql diff \(repo):#\(number)"

        let prFragment = """
              headRefName
              baseRefName
              files(first: 100) {
                nodes {
                  path
                  additions
                  deletions
                  changeType
                }
              }
        """

        let query = """
        query {
          repository(owner: "\(owner)", name: "\(repo)") {
            pullRequest(number: \(number)) {
              \(prFragment)
            }
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

            guard !json.isEmpty else { return nil }

            let response = try decoder.decode(PRDetailResponse.self, from: Data(json.utf8))
            return response.data.repository?.pullRequest
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
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

    // MARK: - Repository Listing

    /// Fetch all repos the user has access to (personal + org)
    func fetchAccessibleRepos() async throws -> [String] {
        let start = Date()
        let command = "list repos"

        do {
            // Use gh repo list which shows all accessible repos
            let output = try await shell.executeGH([
                "repo", "list",
                "--limit", "200",
                "--json", "nameWithOwner",
                "--jq", ".[].nameWithOwner"
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            guard !output.isEmpty else { return [] }
            return output.components(separatedBy: "\n").filter { !$0.isEmpty }
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    // MARK: - Commit Fetching

    /// Fetch commits from specific repos using per-repo API (fast, reliable)
    func fetchCommitsFromRepos(
        author: String,
        startDate: Date,
        endDate: Date,
        repos: [String]
    ) async throws -> [Commit] {
        guard !repos.isEmpty else { return [] }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let sinceStr = dateFormatter.string(from: startDate)
        let untilStr = dateFormatter.string(from: endDate)

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, yyyy HH:mm"
        let displayRange = "\(displayFormatter.string(from: startDate)) - \(displayFormatter.string(from: endDate))"

        var allCommits: [Commit] = []

        for repo in repos {
            let start = Date()
            let command = "commits \(repo): \(displayRange)"

            do {
                let json = try await shell.executeGH([
                    "api", "repos/\(repo)/commits",
                    "-X", "GET",
                    "-f", "author=\(author)",
                    "-f", "since=\(sinceStr)",
                    "-f", "until=\(untilStr)",
                    "-f", "per_page=100"
                ])
                trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

                guard !json.isEmpty, json != "[]" else { continue }

                let repoCommits = try decoder.decode([RepoCommitItem].self, from: Data(json.utf8))
                allCommits.append(contentsOf: repoCommits.map { $0.toCommit(repository: repo) })
            } catch {
                trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
                // Continue with other repos even if one fails
            }
        }

        // Sort by date ascending
        return allCommits.sorted { $0.authorDate < $1.authorDate }
    }

    /// Fetch commits - uses per-repo API (repos required)
    func fetchUserCommits(
        author: String,
        startDate: Date,
        endDate: Date,
        repos: [String]
    ) async throws -> [Commit] {
        // Always use per-repo API (more reliable)
        return try await fetchCommitsFromRepos(
            author: author,
            startDate: startDate,
            endDate: endDate,
            repos: repos
        )
    }

    // MARK: - Commit Diffs

    /// Filter out lock files and binary diffs from a commit diff
    private func filterDiff(_ diff: String) -> String {
        // Lock file patterns to exclude
        let lockFilePatterns = [
            "package-lock.json",
            "yarn.lock",
            "pnpm-lock.yaml",
            "Gemfile.lock",
            "Cargo.lock",
            "poetry.lock",
            "Podfile.lock",
            "composer.lock",
            "go.sum",
            "flake.lock"
        ]

        // Split diff into file sections
        let sections = diff.components(separatedBy: "diff --git ")

        let filtered = sections.filter { section in
            guard !section.isEmpty else { return false }

            // Check for binary file indicator
            if section.contains("Binary files") { return false }

            // Check for lock files
            let firstLine = section.components(separatedBy: "\n").first ?? ""
            for pattern in lockFilePatterns {
                if firstLine.contains(pattern) { return false }
            }

            return true
        }

        return filtered.map { "diff --git " + $0 }.joined()
    }

    /// Fetch full diff for a pull request
    func fetchPRDiffRaw(owner: String, repo: String, number: Int) async throws -> String {
        let start = Date()
        let command = "diff \(repo):#\(number)"

        do {
            let diff = try await withRetry {
                try await shell.executeGH([
                    "api", "repos/\(owner)/\(repo)/pulls/\(number)",
                    "-H", "Accept: application/vnd.github.diff"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)
            return filterDiff(diff)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    /// Fetch diff for a single commit
    func fetchCommitDiff(repo: String, sha: String) async throws -> String {
        let start = Date()
        let command = "diff \(repo.components(separatedBy: "/").last ?? repo):\(sha.prefix(7))"

        do {
            let diff = try await withRetry {
                try await shell.executeGH([
                    "api", "repos/\(repo)/commits/\(sha)",
                    "-H", "Accept: application/vnd.github.diff"
                ])
            }
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)
            return filterDiff(diff)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    /// Fetch diffs for multiple commits (parallel with concurrency limit)
    func fetchCommitDiffs(commits: [Commit], concurrencyLimit: Int = 5) async -> [String: String] {
        // Group commits by repo
        var commitsByRepo: [String: [Commit]] = [:]
        for commit in commits {
            commitsByRepo[commit.repository, default: []].append(commit)
        }

        var allDiffs: [String: String] = [:]

        // Process each repo's commits with limited concurrency
        await withTaskGroup(of: [(String, String)].self) { group in
            for (repo, repoCommits) in commitsByRepo {
                group.addTask {
                    var repoDiffs: [(String, String)] = []

                    // Use a semaphore-like pattern with chunks
                    for chunk in repoCommits.chunked(into: concurrencyLimit) {
                        await withTaskGroup(of: (String, String?).self) { chunkGroup in
                            for commit in chunk {
                                chunkGroup.addTask {
                                    do {
                                        let diff = try await self.fetchCommitDiff(repo: repo, sha: commit.sha)
                                        return (commit.sha, diff)
                                    } catch {
                                        // Return nil on failure - we'll proceed without the diff
                                        return (commit.sha, nil)
                                    }
                                }
                            }

                            for await (sha, diff) in chunkGroup {
                                if let diff = diff {
                                    repoDiffs.append((sha, diff))
                                }
                            }
                        }
                    }

                    return repoDiffs
                }
            }

            for await repoDiffs in group {
                for (sha, diff) in repoDiffs {
                    allDiffs[sha] = diff
                }
            }
        }

        return allDiffs
    }

    // MARK: - Review Comments

    func fetchReviewComments(owner: String, repo: String, number: Int) async throws -> [PullRequestReviewComment] {
        let start = Date()
        let command = "api pull request comments"

        do {
            let output = try await shell.executeGH([
                "api",
                "repos/\(owner)/\(repo)/pulls/\(number)/comments",
                "--paginate"
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            let data = Data(output.utf8)
            return try decoder.decode([PullRequestReviewComment].self, from: data)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func createReviewComment(
        owner: String,
        repo: String,
        number: Int,
        path: String,
        line: Int,
        side: String,
        commitId: String,
        body: String
    ) async throws -> PullRequestReviewComment {
        let start = Date()
        let command = "api create review comment"

        do {
            let requestBody: [String: Any] = [
                "body": body,
                "commit_id": commitId,
                "path": path,
                "line": line,
                "side": side
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let output = try await shell.executeGH([
                "api",
                "-X", "POST",
                "repos/\(owner)/\(repo)/pulls/\(number)/comments",
                "-f", jsonString
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            let data = Data(output.utf8)
            return try decoder.decode(PullRequestReviewComment.self, from: data)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func updateReviewComment(
        owner: String,
        repo: String,
        commentId: Int,
        body: String
    ) async throws -> PullRequestReviewComment {
        let start = Date()
        let command = "api update review comment"

        do {
            let requestBody: [String: Any] = [
                "body": body
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let output = try await shell.executeGH([
                "api",
                "-X", "PATCH",
                "repos/\(owner)/\(repo)/pulls/comments/\(commentId)",
                "-f", jsonString
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            let data = Data(output.utf8)
            return try decoder.decode(PullRequestReviewComment.self, from: data)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func deleteReviewComment(owner: String, repo: String, commentId: Int) async throws {
        let start = Date()
        let command = "api delete review comment"

        do {
            _ = try await shell.executeGH([
                "api",
                "-X", "DELETE",
                "repos/\(owner)/\(repo)/pulls/comments/\(commentId)"
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func createPendingReview(
        owner: String,
        repo: String,
        number: Int,
        commitId: String,
        body: String = "",
        comments: [[String: Any]] = []
    ) async throws -> String {
        let start = Date()
        let command = "api create pending review"

        do {
            var requestBody: [String: Any] = [
                "commit_id": commitId,
                "event": "",
                "body": body
            ]

            if !comments.isEmpty {
                requestBody["comments"] = comments
            }

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let output = try await shell.executeGH([
                "api",
                "-X", "POST",
                "repos/\(owner)/\(repo)/pulls/\(number)/reviews",
                "-f", jsonString
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            return output
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func submitPendingReview(
        owner: String,
        repo: String,
        number: Int,
        reviewId: String,
        event: String,
        body: String = ""
    ) async throws -> String {
        let start = Date()
        let command = "api submit review"

        do {
            var requestBody: [String: Any] = [
                "event": event
            ]

            if !body.isEmpty {
                requestBody["body"] = body
            }

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let output = try await shell.executeGH([
                "api",
                "-X", "POST",
                "repos/\(owner)/\(repo)/pulls/\(number)/reviews/\(reviewId)",
                "-f", jsonString
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            return output
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func createReviewCommentInPendingReview(
        owner: String,
        repo: String,
        number: Int,
        reviewId: String,
        path: String,
        line: Int,
        side: String,
        body: String
    ) async throws -> PullRequestReviewComment {
        let start = Date()
        let command = "api create review comment"

        do {
            let requestBody: [String: Any] = [
                "body": body,
                "line": line,
                "path": path,
                "side": side
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let output = try await shell.executeGH([
                "api",
                "-X", "POST",
                "repos/\(owner)/\(repo)/pulls/\(number)/reviews/\(reviewId)/comments",
                "-f", jsonString
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            return output
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    func listReviewsForPullRequest(
        owner: String,
        repo: String,
        number: Int
    ) async throws -> [PullRequestReview] {
        let start = Date()
        let command = "api list reviews for pull request"

        do {
            let output = try await shell.executeGH([
                "api",
                "repos/\(owner)/\(repo)/pulls/\(number)/reviews"
            ])
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            let data = Data(output.utf8)
            return try decoder.decode([PullRequestReview].self, from: data)
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
