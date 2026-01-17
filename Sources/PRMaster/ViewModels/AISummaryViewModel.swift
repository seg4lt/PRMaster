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

    // Provider status (cached - only checked once)
    @Published var providerStatus: AIProviderStatus = .notInstalled(message: "Not checked")
    @Published var isCheckingProvider = false
    private var hasCheckedProvider = false

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

    /// Check provider status only once (cached)
    func checkProviderStatusIfNeeded() async {
        guard !hasCheckedProvider else { return }
        hasCheckedProvider = true
        isCheckingProvider = true

        let provider = AIProviderType.claude.createProvider()
        providerStatus = await provider.checkAvailability()

        isCheckingProvider = false
    }

    /// Force re-check provider status
    func recheckProviderStatus() async {
        hasCheckedProvider = false
        await checkProviderStatusIfNeeded()
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

            // Parse repo filter and dates
            let repos = await MainActor.run { self.parseRepoFilter() }
            let startDate = await MainActor.run { self.startDate }
            let endDate = await MainActor.run { self.endDate }

            // Break date range into weeks FIRST (before fetching)
            let weekRanges = await MainActor.run { self.generateWeekRanges(from: startDate, to: endDate) }

            // Initialize all weeks as pending (with empty commits for now)
            await MainActor.run {
                self.weeklySummaries = weekRanges.map { range in
                    let week = WeeklyCommits(
                        weekStart: range.start,
                        weekEnd: range.end,
                        commits: []
                    )
                    return WeeklySummary(week: week, status: .pending)
                }
            }

            if Task.isCancelled { return }

            // Get the AI provider
            let provider = AIProviderType.claude.createProvider()

            // Process each week: fetch commits, then summarize
            let summaryCount = await MainActor.run { self.weeklySummaries.count }
            var totalCommits = 0

            for index in 0..<summaryCount {
                if Task.isCancelled { break }

                let weekData = await MainActor.run { self.weeklySummaries[index].week }
                let weekLabel = weekData.weekLabel

                // Mark as loading and update status
                await MainActor.run {
                    self.weeklySummaries[index].status = .loading
                    self.statusMessage = "Fetching commits for \(weekLabel)..."
                }

                do {
                    // Fetch commits for this specific week
                    let commits = try await GitHubService.shared.fetchUserCommits(
                        author: currentUser,
                        startDate: weekData.weekStart,
                        endDate: weekData.weekEnd,
                        repos: repos
                    )

                    if Task.isCancelled { break }

                    // Update the week with actual commits
                    await MainActor.run {
                        self.weeklySummaries[index].week = WeeklyCommits(
                            weekStart: weekData.weekStart,
                            weekEnd: weekData.weekEnd,
                            commits: commits
                        )
                    }

                    totalCommits += commits.count

                    if commits.isEmpty {
                        // No commits this week
                        await MainActor.run {
                            self.weeklySummaries[index].status = .completed("No commits this week.")
                        }
                    } else {
                        // Summarize this week
                        await MainActor.run {
                            self.statusMessage = "Summarizing \(weekLabel) (\(commits.count) commits)..."
                        }

                        let result = try await provider.summarizeWeek(commits: commits, weekLabel: weekLabel)

                        if !Task.isCancelled {
                            await MainActor.run {
                                self.weeklySummaries[index].status = .completed(result)
                            }
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

            let finalTotalCommits = totalCommits
            await MainActor.run {
                self.isLoading = false
                self.statusMessage = nil
                if finalTotalCommits == 0 {
                    self.error = "No commits found in the selected date range"
                }
                self.saveCachedSummaries()
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

    private func generateWeekRanges(from startDate: Date, to endDate: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var ranges: [(start: Date, end: Date)] = []

        // Find the start of the week containing startDate
        var currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate

        while currentWeekStart <= endDate {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart

            // Clamp to the user's selected date range
            let effectiveStart = max(currentWeekStart, startDate)
            let effectiveEnd = min(weekEnd, endDate)

            ranges.append((start: effectiveStart, end: effectiveEnd))

            // Move to next week
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) else { break }
            currentWeekStart = nextWeek
        }

        return ranges
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
