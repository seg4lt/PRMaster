import Foundation
import SwiftUI

@MainActor
class AISummaryViewModel: ObservableObject {
    static let shared = AISummaryViewModel()

    @Published var startDate: Date
    @Published var endDate: Date
    @Published var weeklySummaries: [WeeklySummary] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var statusMessage: String?

    // Repo selection
    @Published var availableRepos: [String] = []
    @Published var selectedRepos: Set<String> = []
    @Published var isLoadingRepos = false
    @Published var repoSearchText: String = ""

    // Provider status (cached - only checked once)
    @Published var providerStatus: AIProviderStatus = .notInstalled(message: "Not checked")
    @Published var isCheckingProvider = false
    private var hasCheckedProvider = false
    private var hasLoadedRepos = false

    var filteredRepos: [String] {
        let repos = repoSearchText.isEmpty
            ? availableRepos
            : availableRepos.filter { $0.localizedCaseInsensitiveContains(repoSearchText) }
        // Selected repos first, then alphabetically within each group
        return repos.sorted { a, b in
            let aSelected = selectedRepos.contains(a)
            let bSelected = selectedRepos.contains(b)
            if aSelected != bSelected {
                return aSelected
            }
            return a < b
        }
    }

    private var generationTask: Task<Void, Never>?

    init() {
        // Default: 1 month ago to today
        let calendar = Calendar.current
        let today = Date()
        self.endDate = today
        self.startDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today

        // Load cached summaries and selected repos
        loadCachedSummaries()
        loadSelectedRepos()
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

    /// Load available repos (cached for 1 week)
    func loadReposIfNeeded() async {
        guard !hasLoadedRepos else { return }
        hasLoadedRepos = true

        // Try to load from cache first
        if let cached = loadCachedRepos(), !isCacheExpired() {
            availableRepos = cached
            return
        }

        // Fetch from API
        isLoadingRepos = true
        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            availableRepos = repos.sorted()
            saveCachedRepos(availableRepos)
        } catch {
            // If fetch fails but we have stale cache, use it
            if let cached = loadCachedRepos() {
                availableRepos = cached
            } else {
                self.error = "Failed to load repos: \(error.localizedDescription)"
            }
        }
        isLoadingRepos = false
    }

    /// Force reload repos from API
    func reloadRepos() async {
        hasLoadedRepos = false
        isLoadingRepos = true

        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            availableRepos = repos.sorted()
            saveCachedRepos(availableRepos)
        } catch {
            self.error = "Failed to reload repos: \(error.localizedDescription)"
        }

        isLoadingRepos = false
        hasLoadedRepos = true
    }

    private func loadCachedRepos() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: "cachedRepos"),
              let repos = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return repos
    }

    private func saveCachedRepos(_ repos: [String]) {
        if let data = try? JSONEncoder().encode(repos) {
            UserDefaults.standard.set(data, forKey: "cachedRepos")
            UserDefaults.standard.set(Date(), forKey: "cachedReposDate")
        }
    }

    private func isCacheExpired() -> Bool {
        guard let cacheDate = UserDefaults.standard.object(forKey: "cachedReposDate") as? Date else {
            return true
        }
        let oneWeek: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(cacheDate) > oneWeek
    }

    func toggleRepo(_ repo: String) {
        if selectedRepos.contains(repo) {
            selectedRepos.remove(repo)
        } else {
            selectedRepos.insert(repo)
        }
        saveSelectedRepos()
    }

    func selectAllFilteredRepos() {
        for repo in filteredRepos {
            selectedRepos.insert(repo)
        }
        saveSelectedRepos()
    }

    func deselectAllRepos() {
        selectedRepos.removeAll()
        saveSelectedRepos()
    }

    private func loadSelectedRepos() {
        if let data = UserDefaults.standard.data(forKey: "selectedRepos"),
           let repos = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedRepos = repos
        }
    }

    private func saveSelectedRepos() {
        if let data = try? JSONEncoder().encode(selectedRepos) {
            UserDefaults.standard.set(data, forKey: "selectedRepos")
        }
    }

    func generateSummaries() {
        // Require at least one repo
        guard !selectedRepos.isEmpty else {
            error = "Please select at least one repository"
            return
        }

        // Cancel any existing generation
        generationTask?.cancel()

        isLoading = true
        error = nil
        statusMessage = "Fetching GitHub user..."
        weeklySummaries = []

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

            // Get selected repos and dates
            let repos = await MainActor.run { Array(self.selectedRepos) }
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
    }

    // MARK: - Private Helpers

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
        // Load existing cache
        var existingCache: [String: CachedSummary] = [:]
        if let data = UserDefaults.standard.data(forKey: "aiSummaryCache"),
           let cached = try? JSONDecoder().decode([CachedSummary].self, from: data) {
            for summary in cached {
                let key = ISO8601DateFormatter().string(from: summary.weekStart)
                existingCache[key] = summary
            }
        }

        // Merge new completed summaries (override existing, add new)
        for summary in weeklySummaries {
            guard case .completed(let text) = summary.status else { continue }
            let key = summary.week.id
            existingCache[key] = CachedSummary(
                weekStart: summary.week.weekStart,
                weekEnd: summary.week.weekEnd,
                weekLabel: summary.week.weekLabel,
                commitCount: summary.week.commits.count,
                summaryText: text
            )
        }

        // Sort by date and save
        let sortedCache = existingCache.values.sorted { $0.weekStart < $1.weekStart }
        if let data = try? JSONEncoder().encode(Array(sortedCache)) {
            UserDefaults.standard.set(data, forKey: "aiSummaryCache")
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
