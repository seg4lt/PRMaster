import Foundation
import SwiftUI

@MainActor
class AISummaryViewModel: ObservableObject {
    static let shared = AISummaryViewModel()

    @Published var startDate: Date
    @Published var endDate: Date
    @Published var repoFilter: String = ""
    @Published var weeklySummaries: [WeeklySummary] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var statusMessage: String?

    // Cache key based on date range and repo filter
    private var lastCacheKey: String = ""

    private var generationTask: Task<Void, Never>?

    init() {
        // Default: 1 month ago to today
        let calendar = Calendar.current
        let today = Date()
        self.endDate = today
        self.startDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today

        // Load cached summaries
        loadCachedSummaries()
    }

    private var cacheKey: String {
        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: startDate))_\(formatter.string(from: endDate))_\(repoFilter)"
    }

    var hasMorePending: Bool {
        weeklySummaries.contains { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    func generateSummaries() {
        // Cancel any existing generation
        generationTask?.cancel()

        isLoading = true
        error = nil
        statusMessage = "Fetching GitHub user..."
        weeklySummaries = []
        lastCacheKey = cacheKey

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                // Get current user
                await MainActor.run {
                    self.statusMessage = "Fetching GitHub user..."
                }

                guard let currentUser = try? await GitHubService.shared.getCurrentUser() else {
                    await MainActor.run {
                        self.error = "Could not get current user"
                        self.isLoading = false
                        self.statusMessage = nil
                    }
                    return
                }

                // Parse repo filter
                let repos = await MainActor.run { self.parseRepoFilter() }
                let startDate = await MainActor.run { self.startDate }
                let endDate = await MainActor.run { self.endDate }

                await MainActor.run {
                    self.statusMessage = "Fetching commits..."
                }

                // Fetch commits
                let commits = try await GitHubService.shared.fetchUserCommits(
                    author: currentUser,
                    startDate: startDate,
                    endDate: endDate,
                    repos: repos
                )

                if Task.isCancelled { return }

                guard !commits.isEmpty else {
                    await MainActor.run {
                        self.error = "No commits found in the selected date range"
                        self.isLoading = false
                        self.statusMessage = nil
                    }
                    return
                }

                await MainActor.run {
                    self.statusMessage = "Found \(commits.count) commits, grouping by week..."
                }

                // Group commits by week
                let weeklyCommits = await MainActor.run { self.groupCommitsByWeek(commits) }

                // Initialize summaries with pending status
                await MainActor.run {
                    self.weeklySummaries = weeklyCommits.map { week in
                        WeeklySummary(week: week, status: .pending)
                    }
                    self.statusMessage = "Generating summaries..."
                }

                // Get the AI provider
                let provider = AIProviderType.claude.createProvider()

                // Launch all summary tasks concurrently (detached for parallelism)
                let summaryCount = await MainActor.run { self.weeklySummaries.count }
                var tasks: [Int: Task<String, Error>] = [:]

                for index in 0..<summaryCount {
                    let weekData = await MainActor.run { self.weeklySummaries[index].week }
                    let commits = weekData.commits
                    let weekLabel = weekData.weekLabel
                    tasks[index] = Task.detached {
                        try await provider.summarizeWeek(commits: commits, weekLabel: weekLabel)
                    }
                }

                // Process results in order for streaming display
                for index in 0..<summaryCount {
                    if Task.isCancelled { break }

                    // Mark current as loading
                    await MainActor.run {
                        self.weeklySummaries[index].status = .loading
                    }

                    // Await the pre-launched task
                    if let task = tasks[index] {
                        do {
                            let result = try await task.value
                            if !Task.isCancelled {
                                await MainActor.run {
                                    self.weeklySummaries[index].status = .completed(result)
                                }
                            }
                        } catch {
                            if !Task.isCancelled {
                                await MainActor.run {
                                    self.weeklySummaries[index].status = .error(error.localizedDescription)
                                }
                            }
                        }
                    }
                }

                await MainActor.run {
                    self.isLoading = false
                    self.statusMessage = nil
                    self.saveCachedSummaries()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        self.isLoading = false
                        self.statusMessage = nil
                    }
                }
            }
        }
    }

    func retrySummary(at index: Int) {
        guard index < weeklySummaries.count else { return }

        let summary = weeklySummaries[index]
        weeklySummaries[index].status = .loading

        Task.detached { [weak self] in
            guard let self = self else { return }

            let provider = AIProviderType.claude.createProvider()

            do {
                let result = try await provider.summarizeWeek(
                    commits: summary.week.commits,
                    weekLabel: summary.week.weekLabel
                )
                await MainActor.run {
                    self.weeklySummaries[index].status = .completed(result)
                    self.saveCachedSummaries()
                }
            } catch {
                await MainActor.run {
                    self.weeklySummaries[index].status = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isLoading = false
        statusMessage = nil

        // Mark any loading/pending summaries as cancelled
        for index in 0..<weeklySummaries.count {
            switch weeklySummaries[index].status {
            case .pending, .loading:
                weeklySummaries[index].status = .error("Cancelled")
            default:
                break
            }
        }
    }

    func clearCache() {
        weeklySummaries = []
        UserDefaults.standard.removeObject(forKey: "aiSummaryCache")
        UserDefaults.standard.removeObject(forKey: "aiSummaryCacheKey")
    }

    // MARK: - Private Helpers

    private func parseRepoFilter() -> [String] {
        guard !repoFilter.isEmpty else { return [] }
        return repoFilter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func groupCommitsByWeek(_ commits: [Commit]) -> [WeeklyCommits] {
        let calendar = Calendar.current

        // Group by week start (Sunday)
        var weekGroups: [Date: [Commit]] = [:]

        for commit in commits {
            // Get the start of the week (Sunday)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: commit.authorDate)?.start ?? commit.authorDate
            weekGroups[weekStart, default: []].append(commit)
        }

        // Convert to WeeklyCommits and sort by date ascending (oldest first)
        return weekGroups.keys.sorted().map { weekStart in
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return WeeklyCommits(
                weekStart: weekStart,
                weekEnd: weekEnd,
                commits: weekGroups[weekStart] ?? []
            )
        }
    }

    // MARK: - Caching

    private func saveCachedSummaries() {
        // Only cache completed summaries
        let cacheData = weeklySummaries.compactMap { summary -> CachedSummary? in
            guard case .completed(let text) = summary.status else { return nil }
            return CachedSummary(
                weekStart: summary.week.weekStart,
                weekEnd: summary.week.weekEnd,
                weekLabel: summary.week.weekLabel,
                commitCount: summary.week.commits.count,
                summaryText: text
            )
        }

        if let data = try? JSONEncoder().encode(cacheData) {
            UserDefaults.standard.set(data, forKey: "aiSummaryCache")
            UserDefaults.standard.set(lastCacheKey, forKey: "aiSummaryCacheKey")
        }
    }

    private func loadCachedSummaries() {
        guard let data = UserDefaults.standard.data(forKey: "aiSummaryCache"),
              let cached = try? JSONDecoder().decode([CachedSummary].self, from: data) else {
            return
        }

        // Restore cached summaries (without commit details, just the summary text)
        weeklySummaries = cached.map { cache in
            let week = WeeklyCommits(
                weekStart: cache.weekStart,
                weekEnd: cache.weekEnd,
                commits: [] // We don't cache commits, just the summary
            )
            return WeeklySummary(week: week, status: .completed(cache.summaryText))
        }
    }
}

// MARK: - Cache Models

private struct CachedSummary: Codable {
    let weekStart: Date
    let weekEnd: Date
    let weekLabel: String
    let commitCount: Int
    let summaryText: String
}
