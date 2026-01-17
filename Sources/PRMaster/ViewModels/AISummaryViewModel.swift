import Foundation
import SwiftUI

@MainActor
class AISummaryViewModel: ObservableObject {
    static let shared = AISummaryViewModel()

    @Published var startDate: Date
    @Published var endDate: Date
    @Published var summaries: [DateRangeSummary] = []
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
        summaries.contains { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    /// Get the selected provider type from settings
    var selectedProviderType: AIProviderType {
        let rawValue = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProviderType.claude.rawValue
        return AIProviderType(rawValue: rawValue) ?? .claude
    }

    /// Get the selected model from settings
    private var selectedModel: String? {
        let model = UserDefaults.standard.string(forKey: "aiModel")
        return model?.isEmpty == true ? nil : model
    }

    /// Check provider status only once (cached)
    func checkProviderStatusIfNeeded() async {
        guard !hasCheckedProvider else { return }
        hasCheckedProvider = true
        isCheckingProvider = true

        let provider = selectedProviderType.createProvider()
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

        // Create a new summary entry for the selected date range (append, don't merge)
        let summaryId = UUID()
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        let dateRange = DateRangeCommits(
            id: summaryId,
            startDate: rangeStart,
            endDate: rangeEnd,
            commits: []
        )
        let newSummary = DateRangeSummary(
            id: summaryId,
            dateRange: dateRange,
            status: .pending
        )

        // Append to existing summaries (newest first)
        summaries.insert(newSummary, at: 0)

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
                    // Remove the failed summary
                    self.summaries.removeAll { $0.id == summaryId }
                }
                return
            }

            // Get selected repos and dates
            let repos = await MainActor.run { Array(self.selectedRepos) }
            let startDate = rangeStart
            let endDate = rangeEnd

            if Task.isCancelled { return }

            // Get the AI provider and model
            let providerType = await MainActor.run { self.selectedProviderType }
            let model = await MainActor.run { self.selectedModel }
            let provider = providerType.createProvider()

            // Find the index of our summary
            guard let index = await MainActor.run(body: { self.summaries.firstIndex(where: { $0.id == summaryId }) }) else {
                return
            }

            let dateLabel = await MainActor.run { self.summaries[index].dateRange.dateLabel }

            // Mark as loading
            await MainActor.run {
                self.summaries[index].status = .loading
                self.statusMessage = "Fetching commits for \(dateLabel)..."
            }

            do {
                // Fetch commits for the entire date range
                let commits = try await GitHubService.shared.fetchUserCommits(
                    author: currentUser,
                    startDate: startDate,
                    endDate: endDate,
                    repos: repos
                )

                if Task.isCancelled { return }

                // Update with actual commits
                await MainActor.run {
                    self.summaries[index].dateRange = DateRangeCommits(
                        id: summaryId,
                        startDate: startDate,
                        endDate: endDate,
                        commits: commits
                    )
                }

                if commits.isEmpty {
                    await MainActor.run {
                        self.summaries[index].status = .completed("No commits in this date range.")
                        self.isLoading = false
                        self.statusMessage = nil
                        self.saveCachedSummaries()
                    }
                    return
                }

                // Fetch diffs for commits
                await MainActor.run {
                    self.statusMessage = "Fetching diffs for \(dateLabel) (\(commits.count) commits)..."
                }

                let diffs = await GitHubService.shared.fetchCommitDiffs(commits: commits)

                if Task.isCancelled { return }

                // Create enriched commits
                var enrichedCommits = commits.map { commit in
                    EnrichedCommit(commit: commit, diff: diffs[commit.sha])
                }

                // Pre-process huge commits
                var processedCommits: [EnrichedCommit] = []
                for enriched in enrichedCommits {
                    if enriched.sizeCategory == .huge {
                        await MainActor.run {
                            self.statusMessage = "Summarizing large diff for \(enriched.commit.shortSha)..."
                        }
                        let summary = try await provider.summarizeHugeCommit(enriched, model: model)
                        processedCommits.append(EnrichedCommit(commit: enriched.commit, diff: summary))
                    } else {
                        processedCommits.append(enriched)
                    }
                }
                enrichedCommits = processedCommits

                // Summarize with diffs
                let batches = CommitBatcher.createBatches(from: enrichedCommits)
                await MainActor.run {
                    if batches.count > 1 {
                        self.statusMessage = "Summarizing \(dateLabel) (\(commits.count) commits in \(batches.count) batches)..."
                    } else {
                        self.statusMessage = "Summarizing \(dateLabel) (\(commits.count) commits)..."
                    }
                }

                let result = try await provider.summarizeDateRange(commits: enrichedCommits, dateLabel: dateLabel, model: model)

                if !Task.isCancelled {
                    await MainActor.run {
                        self.summaries[index].status = .completed(result)
                        self.isLoading = false
                        self.statusMessage = nil
                        self.saveCachedSummaries()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.summaries[index].status = .error(error.localizedDescription)
                        self.isLoading = false
                        self.statusMessage = nil
                    }
                }
            }
        }
    }

    func retrySummary(at index: Int) {
        guard index < summaries.count else { return }

        let summary = summaries[index]
        summaries[index].status = .loading
        statusMessage = "Retrying \(summary.dateRange.dateLabel)..."

        Task.detached { [weak self] in
            guard let self = self else { return }

            let commits = summary.dateRange.commits
            let dateLabel = summary.dateRange.dateLabel

            do {
                // Re-fetch diffs for the retry
                await MainActor.run {
                    self.statusMessage = "Fetching diffs for \(dateLabel)..."
                }

                let diffs = await GitHubService.shared.fetchCommitDiffs(commits: commits)

                // Create enriched commits
                let enrichedCommits = commits.map { commit in
                    EnrichedCommit(commit: commit, diff: diffs[commit.sha])
                }

                await MainActor.run {
                    self.statusMessage = "Summarizing \(dateLabel)..."
                }

                let providerType = await MainActor.run { self.selectedProviderType }
                let model = await MainActor.run { self.selectedModel }
                let provider = providerType.createProvider()
                let result = try await provider.summarizeDateRange(
                    commits: enrichedCommits,
                    dateLabel: dateLabel,
                    model: model
                )
                await MainActor.run {
                    self.summaries[index].status = .completed(result)
                    self.statusMessage = nil
                    self.saveCachedSummaries()
                }
            } catch {
                await MainActor.run {
                    self.summaries[index].status = .error(error.localizedDescription)
                    self.statusMessage = nil
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isLoading = false
        statusMessage = nil

        // Remove any pending/loading summaries
        summaries.removeAll { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    func clearCache() {
        summaries = []
        UserDefaults.standard.removeObject(forKey: "aiSummaryCache")
    }

    func deleteSummary(id: UUID) {
        summaries.removeAll { $0.id == id }
        saveCachedSummaries()
    }

    func updateSummary(id: UUID) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }

        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        // Update the date range and re-generate
        summaries[index].dateRange = DateRangeCommits(
            id: id,
            startDate: rangeStart,
            endDate: rangeEnd,
            commits: []
        )
        summaries[index].status = .loading
        isLoading = true
        statusMessage = "Updating summary..."

        let summaryId = id

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }

            guard let currentUser = try? await GitHubService.shared.getCurrentUser() else {
                await MainActor.run {
                    self.error = "Could not get current user"
                    self.isLoading = false
                    self.statusMessage = nil
                }
                return
            }

            let repos = await MainActor.run { Array(self.selectedRepos) }
            let providerType = await MainActor.run { self.selectedProviderType }
            let model = await MainActor.run { self.selectedModel }
            let provider = providerType.createProvider()

            guard let index = await MainActor.run(body: { self.summaries.firstIndex(where: { $0.id == summaryId }) }) else {
                return
            }

            let dateLabel = await MainActor.run { self.summaries[index].dateRange.dateLabel }

            await MainActor.run {
                self.statusMessage = "Fetching commits for \(dateLabel)..."
            }

            do {
                let commits = try await GitHubService.shared.fetchUserCommits(
                    author: currentUser,
                    startDate: rangeStart,
                    endDate: rangeEnd,
                    repos: repos
                )

                if Task.isCancelled { return }

                await MainActor.run {
                    self.summaries[index].dateRange = DateRangeCommits(
                        id: summaryId,
                        startDate: rangeStart,
                        endDate: rangeEnd,
                        commits: commits
                    )
                }

                if commits.isEmpty {
                    await MainActor.run {
                        self.summaries[index].status = .completed("No commits in this date range.")
                        self.isLoading = false
                        self.statusMessage = nil
                        self.saveCachedSummaries()
                    }
                    return
                }

                await MainActor.run {
                    self.statusMessage = "Fetching diffs for \(dateLabel) (\(commits.count) commits)..."
                }

                let diffs = await GitHubService.shared.fetchCommitDiffs(commits: commits)

                if Task.isCancelled { return }

                var enrichedCommits = commits.map { commit in
                    EnrichedCommit(commit: commit, diff: diffs[commit.sha])
                }

                var processedCommits: [EnrichedCommit] = []
                for enriched in enrichedCommits {
                    if enriched.sizeCategory == .huge {
                        await MainActor.run {
                            self.statusMessage = "Summarizing large diff for \(enriched.commit.shortSha)..."
                        }
                        let summary = try await provider.summarizeHugeCommit(enriched, model: model)
                        processedCommits.append(EnrichedCommit(commit: enriched.commit, diff: summary))
                    } else {
                        processedCommits.append(enriched)
                    }
                }
                enrichedCommits = processedCommits

                let batches = CommitBatcher.createBatches(from: enrichedCommits)
                await MainActor.run {
                    if batches.count > 1 {
                        self.statusMessage = "Summarizing \(dateLabel) (\(commits.count) commits in \(batches.count) batches)..."
                    } else {
                        self.statusMessage = "Summarizing \(dateLabel) (\(commits.count) commits)..."
                    }
                }

                let result = try await provider.summarizeDateRange(commits: enrichedCommits, dateLabel: dateLabel, model: model)

                if !Task.isCancelled {
                    await MainActor.run {
                        self.summaries[index].status = .completed(result)
                        self.isLoading = false
                        self.statusMessage = nil
                        self.saveCachedSummaries()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.summaries[index].status = .error(error.localizedDescription)
                        self.isLoading = false
                        self.statusMessage = nil
                    }
                }
            }
        }
    }

    // MARK: - Caching

    private func saveCachedSummaries() {
        // Convert completed summaries to cache format
        let cacheItems = summaries.compactMap { summary -> CachedSummary? in
            guard case .completed(let text) = summary.status else { return nil }
            return CachedSummary(
                id: summary.id,
                startDate: summary.dateRange.startDate,
                endDate: summary.dateRange.endDate,
                dateLabel: summary.dateRange.dateLabel,
                commitCount: summary.dateRange.commits.count,
                summaryText: text,
                createdAt: summary.createdAt
            )
        }

        // Sort by createdAt descending (newest first)
        let sortedCache = cacheItems.sorted { $0.createdAt > $1.createdAt }
        if let data = try? JSONEncoder().encode(sortedCache) {
            UserDefaults.standard.set(data, forKey: "aiSummaryCache")
        }
    }

    private func loadCachedSummaries() {
        guard let data = UserDefaults.standard.data(forKey: "aiSummaryCache"),
              let cached = try? JSONDecoder().decode([CachedSummary].self, from: data) else {
            return
        }

        // Restore cached summaries (sorted by createdAt descending)
        summaries = cached.sorted { $0.createdAt > $1.createdAt }.map { cache in
            let dateRange = DateRangeCommits(
                id: cache.id,
                startDate: cache.startDate,
                endDate: cache.endDate,
                commits: [] // We don't cache commits, just the summary
            )
            return DateRangeSummary(
                id: cache.id,
                dateRange: dateRange,
                status: .completed(cache.summaryText),
                createdAt: cache.createdAt
            )
        }
    }
}

// MARK: - Cache Models

private struct CachedSummary: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let dateLabel: String
    let commitCount: Int
    let summaryText: String
    let createdAt: Date
}
