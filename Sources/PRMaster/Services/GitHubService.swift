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

    func fetchConversationCandidatePRs() async throws -> [PullRequest] {
        let start = Date()
        let command = "search prs for conversations"

        do {
            async let involvedJSON = withRetry {
                try await self.shell.executeGH([
                    "search", "prs",
                    "--involves", "@me",
                    "--state", "open",
                    "--limit", "100",
                    "--json", "number,title,url,state,createdAt,updatedAt,isDraft,author,repository"
                ])
            }

            async let mentionedJSON = withRetry {
                try await self.shell.executeGH([
                    "search", "prs",
                    "--mentions", "@me",
                    "--state", "open",
                    "--limit", "100",
                    "--json", "number,title,url,state,createdAt,updatedAt,isDraft,author,repository"
                ])
            }

            let (involved, mentioned) = try await (involvedJSON, mentionedJSON)
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            let involvedResults = involved.isEmpty ? [] : try decoder.decode([PRSearchResult].self, from: Data(involved.utf8))
            let mentionedResults = mentioned.isEmpty ? [] : try decoder.decode([PRSearchResult].self, from: Data(mentioned.utf8))

            return (involvedResults + mentionedResults)
                .map { $0.toPullRequest() }
                .uniqued()
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

    func fetchConversations(currentUser: String) async throws -> [ConversationGroup] {
        let candidates = try await fetchConversationCandidatePRs()
            .filter { $0.isOpen }

        guard !candidates.isEmpty else { return [] }

        let normalizedUser = currentUser.lowercased()

        let items = try await withThrowingTaskGroup(of: [ConversationItem].self) { group in
            for pr in candidates {
                group.addTask {
                    let detail = try await self.fetchConversationDetail(for: pr)
                    return detail.conversationItems(for: normalizedUser)
                }
            }

            var allItems: [ConversationItem] = []
            for try await result in group {
                allItems.append(contentsOf: result)
            }
            return allItems
        }

        let dedupedItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current }).values
            .sorted { $0.latestActivityAt > $1.latestActivityAt }

        let grouped = Dictionary(grouping: dedupedItems, by: \.prID)
            .values
            .compactMap { items -> ConversationGroup? in
                guard let first = items.first else { return nil }
                let sortedItems = items.sorted { $0.latestActivityAt > $1.latestActivityAt }
                return ConversationGroup(
                    prID: first.prID,
                    prTitle: first.prTitle,
                    prNumber: first.prNumber,
                    repoNameWithOwner: first.repoNameWithOwner,
                    prURL: first.prURL,
                    conversations: sortedItems
                )
            }
            .sorted { $0.latestActivityAt > $1.latestActivityAt }

        return grouped
    }

    private func fetchConversationDetail(for pr: PullRequest) async throws -> ConversationPRDetail {
        let start = Date()
        let command = "graphql conversations \(pr.repository.shortName)#\(pr.number)"

        let query = """
        query {
          repository(owner: "\(pr.repository.owner)", name: "\(pr.repository.shortName)") {
            pullRequest(number: \(pr.number)) {
              number
              title
              url
              comments(first: 50) {
                nodes {
                  id
                  body
                  createdAt
                  url
                  author {
                    login
                  }
                }
              }
              reviewThreads(first: 50) {
                nodes {
                  id
                  isResolved
                  path
                  line
                  originalLine
                  comments(first: 50) {
                    nodes {
                      id
                      body
                      createdAt
                      url
                      author {
                        login
                      }
                    }
                  }
                }
              }
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

            guard !json.isEmpty else {
                throw ShellError.commandFailed("Empty conversation response", 1)
            }

            let response = try decoder.decode(ConversationDetailResponse.self, from: Data(json.utf8))
            guard let detail = response.data.repository?.pullRequest else {
                throw ShellError.commandFailed("Missing pull request conversation data", 1)
            }
            return detail
        } catch {
            trackCall(command: command, duration: Date().timeIntervalSince(start), success: false)
            throw error
        }
    }

    // MARK: - Repository Listing

    /// Fetch list of organizations user belongs to
    func fetchUserOrganizations() async throws -> [String] {
        let output = try await shell.executeGH([
            "org", "list"
        ])
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Fetch all repos the user has access to (personal + org)
    func fetchAccessibleRepos() async throws -> [String] {
        let start = Date()
        let command = "list repos"

        do {
            var allRepos: [String] = []

            // Fetch personal repos
            let personalOutput = try await shell.executeGH([
                "repo", "list",
                "--limit", "1000",
                "--json", "nameWithOwner",
                "--jq", ".[].nameWithOwner"
            ])
            allRepos.append(contentsOf: personalOutput.components(separatedBy: "\n").filter { !$0.isEmpty })

            // Fetch org repos
            let orgs = try await fetchUserOrganizations()
            for org in orgs {
                do {
                    let orgOutput = try await shell.executeGH([
                        "repo", "list", org,
                        "--limit", "1000",
                        "--json", "nameWithOwner",
                        "--jq", ".[].nameWithOwner"
                    ])
                    allRepos.append(contentsOf: orgOutput.components(separatedBy: "\n").filter { !$0.isEmpty })
                } catch {
                    // Log warning but continue with other orgs (e.g., IP allow list restrictions)
                    print("Warning: Could not fetch repos for org '\(org)': \(error.localizedDescription)")
                }
            }

            trackCall(command: command, duration: Date().timeIntervalSince(start), success: true)

            // Remove duplicates and sort
            return Array(Set(allRepos)).sorted()
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

    // MARK: - Local Git Fallback Methods

    func fetchUserCommitsWithLocalFallback(
        author: String,
        startDate: Date,
        endDate: Date,
        repos: [String]
    ) async throws -> [Commit] {
        guard !repos.isEmpty else { return [] }

        let mappingService = await LocalRepoMappingService.shared
        let mappings = await mappingService.mappings

        var localRepos: [(String, String)] = []
        var remoteRepos: [String] = []

        for repo in repos {
            if let mapping = mappings.first(where: { $0.repositoryName == repo }) {
                localRepos.append((repo, mapping.localPath))
            } else {
                remoteRepos.append(repo)
            }
        }

        var allCommits: [Commit] = []

        for (repoName, localPath) in localRepos {
            do {
                let commits = try await LocalGitService.shared.fetchCommits(
                    localPath: localPath,
                    author: author,
                    startDate: startDate,
                    endDate: endDate,
                    repositoryName: repoName
                )
                allCommits.append(contentsOf: commits)
            } catch {
                // Silently fall back to API if local fetch fails
                print("Local git fetch failed for \(repoName), falling back to API: \(error)")
                remoteRepos.append(repoName)
            }
        }

        if !remoteRepos.isEmpty {
            let remoteCommits = try await fetchCommitsFromRepos(
                author: author,
                startDate: startDate,
                endDate: endDate,
                repos: remoteRepos
            )
            allCommits.append(contentsOf: remoteCommits)
        }

        // Sort by date (newest first)
        return allCommits.sorted { $0.authorDate > $1.authorDate }
    }

    func fetchCommitDiffsWithLocalFallback(
        commits: [Commit],
        concurrencyLimit: Int = 5
    ) async -> [String: String] {
        var commitsByRepo: [String: [Commit]] = [:]
        for commit in commits {
            commitsByRepo[commit.repository, default: []].append(commit)
        }

        let mappingService = await LocalRepoMappingService.shared
        let mappings = await mappingService.mappings

        var allDiffs: [String: String] = [:]

        for (repo, repoCommits) in commitsByRepo {
            if let mapping = mappings.first(where: { $0.repositoryName == repo }) {
                let diffs = await LocalGitService.shared.fetchCommitDiffs(
                    commits: repoCommits,
                    localPath: mapping.localPath,
                    concurrencyLimit: concurrencyLimit
                )
                allDiffs.merge(diffs) { _, new in new }
            } else {
                let diffs = await fetchCommitDiffsForRepo(repo: repo, commits: repoCommits, concurrencyLimit: concurrencyLimit)
                allDiffs.merge(diffs) { _, new in new }
            }
        }

        return allDiffs
    }

    private func fetchCommitDiffsForRepo(
        repo: String,
        commits: [Commit],
        concurrencyLimit: Int
    ) async -> [String: String] {
        var repoDiffs: [String: String] = [:]

        for chunk in commits.chunked(into: concurrencyLimit) {
            await withTaskGroup(of: (String, String?).self) { group in
                for commit in chunk {
                    group.addTask {
                        do {
                            let diff = try await self.fetchCommitDiff(repo: repo, sha: commit.sha)
                            return (commit.sha, diff)
                        } catch {
                            // Return nil on failure - we'll proceed without the diff
                            return (commit.sha, nil)
                        }
                    }
                }

                for await (sha, diff) in group {
                    if let diff = diff {
                        repoDiffs[sha] = diff
                    }
                }
            }
        }

        return repoDiffs
    }
}

private struct ConversationDetailResponse: Codable {
    let data: ConversationDetailData
}

private struct ConversationDetailData: Codable {
    let repository: ConversationRepository?
}

private struct ConversationRepository: Codable {
    let pullRequest: ConversationPRDetail?
}

private struct ConversationPRDetail: Codable {
    let number: Int
    let title: String
    let url: String
    let comments: IssueCommentNodes?
    let reviewThreads: ReviewThreadNodes?

    func conversationItems(for currentUser: String) -> [ConversationItem] {
        let reviewThreadItems = reviewThreads?.nodes.compactMap { thread -> ConversationItem? in
            guard !thread.isResolved else { return nil }
            let messages = thread.comments.nodes.map(\.conversationMessage)
            let userParticipated = messages.contains { $0.authorLogin?.lowercased() == currentUser }
            let userMentioned = messages.contains { $0.body.containsMention(of: currentUser) }
            guard userParticipated || userMentioned else { return nil }
            guard let latestActivityAt = messages.map(\.createdAt).max() else { return nil }
            let exactURL = messages.last?.url ?? url

            return ConversationItem(
                id: thread.id,
                prID: prID,
                prTitle: title,
                prNumber: number,
                repoNameWithOwner: repoNameWithOwner,
                prURL: url,
                kind: .reviewThread,
                filePath: thread.path,
                lineNumber: thread.line ?? thread.originalLine,
                latestActivityAt: latestActivityAt,
                exactURL: exactURL,
                messages: messages.sorted { $0.createdAt < $1.createdAt },
                currentUserLogin: currentUser
            )
        } ?? []

        let mentionCommentItems = comments?.nodes.compactMap { comment -> ConversationItem? in
            guard comment.body.containsMention(of: currentUser) else { return nil }
            return ConversationItem(
                id: comment.id,
                prID: prID,
                prTitle: title,
                prNumber: number,
                repoNameWithOwner: repoNameWithOwner,
                prURL: url,
                kind: .mentionComment,
                filePath: nil,
                lineNumber: nil,
                latestActivityAt: comment.createdAt,
                exactURL: comment.url,
                messages: [comment.conversationMessage],
                currentUserLogin: currentUser
            )
        } ?? []

        return reviewThreadItems + mentionCommentItems
    }

    private var prID: String {
        repoNameWithOwner + "#\(number)"
    }

    private var repoNameWithOwner: String {
        URL(string: url)?
            .pathComponents
            .dropFirst()
            .prefix(2)
            .joined(separator: "/") ?? ""
    }
}

private struct ReviewThreadNodes: Codable {
    let nodes: [ReviewThread]
}

private struct ReviewThread: Codable {
    let id: String
    let isResolved: Bool
    let path: String?
    let line: Int?
    let originalLine: Int?
    let comments: ReviewThreadCommentNodes
}

private struct ReviewThreadCommentNodes: Codable {
    let nodes: [ConversationComment]
}

private struct IssueCommentNodes: Codable {
    let nodes: [ConversationComment]
}

private struct ConversationComment: Codable {
    let id: String
    let body: String
    let createdAt: Date
    let url: String
    let author: ConversationCommentAuthor?

    var conversationMessage: ConversationMessage {
        ConversationMessage(
            id: id,
            authorLogin: author?.login,
            body: body,
            createdAt: createdAt,
            url: url
        )
    }
}

private struct ConversationCommentAuthor: Codable {
    let login: String?
}

private extension String {
    func containsMention(of username: String) -> Bool {
        let pattern = "(?i)(?:^|[^A-Za-z0-9-])@\(NSRegularExpression.escapedPattern(for: username))(?:$|[^A-Za-z0-9-])"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return localizedCaseInsensitiveContains("@\(username)")
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.firstMatch(in: self, options: [], range: range) != nil
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
