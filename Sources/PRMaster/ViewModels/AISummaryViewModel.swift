import Foundation
import SwiftUI

@MainActor
class AISummaryViewModel: ObservableObject {
    static let shared = AISummaryViewModel()

    // Date range
    @Published var startDate: Date
    @Published var endDate: Date

    // Summaries
    @Published var summaries: [DateRangeSummary] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var statusMessage: String?

    // Provider status
    @Published var providerStatus: AIProviderStatus = .notInstalled(message: "Not checked")
    @Published var isCheckingProvider = false

    // Repo management (delegated)
    let repoManager = RepoManager()

    // Generation (delegated)
    private let generator = SummaryGenerator()

    private var hasCheckedProvider = false

    init() {
        let calendar = Calendar.current
        let today = Date()
        self.endDate = today
        self.startDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today

        // Load cached summaries
        summaries = AISummaryCacheService.loadSummaries()
    }

    private var generatorCallbacks: SummaryGeneratorCallbacks {
        SummaryGeneratorCallbacks(
            onStatusUpdate: { [weak self] message in
                self?.statusMessage = message
            },
            onSummaryUpdate: { [weak self] id, status in
                guard let self = self,
                      let index = self.summaries.firstIndex(where: { $0.id == id }) else { return }
                self.summaries[index].status = status
                self.saveCachedSummaries()
            },
            onComplete: { [weak self] in
                self?.isLoading = false
                self?.statusMessage = nil
            },
            onFail: { [weak self] errorMessage in
                self?.error = errorMessage
                self?.isLoading = false
                self?.statusMessage = nil
            },
            getSummary: { [weak self] id in
                self?.summaries.first { $0.id == id }
            }
        )
    }

    // MARK: - Computed Properties

    var hasMorePending: Bool {
        summaries.contains { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    var selectedProviderType: AIProviderType {
        let rawValue = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProviderType.claude.rawValue
        return AIProviderType(rawValue: rawValue) ?? .claude
    }

    private var selectedModel: String? {
        let model = UserDefaults.standard.string(forKey: "aiModel")
        return model?.isEmpty == true ? nil : model
    }

    // MARK: - Convenience Accessors for RepoManager

    var availableRepos: [String] { repoManager.availableRepos }
    var selectedRepos: Set<String> {
        get { repoManager.selectedRepos }
        set { repoManager.selectedRepos = newValue }
    }
    var isLoadingRepos: Bool { repoManager.isLoadingRepos }
    var repoSearchText: String {
        get { repoManager.repoSearchText }
        set { repoManager.repoSearchText = newValue }
    }
    var filteredRepos: [String] { repoManager.filteredRepos }

    /// Binding for selectedRepos for use in views
    var selectedReposBinding: Binding<Set<String>> {
        Binding(
            get: { self.repoManager.selectedRepos },
            set: { self.repoManager.selectedRepos = $0 }
        )
    }

    /// Binding for repoSearchText for use in views
    var repoSearchTextBinding: Binding<String> {
        Binding(
            get: { self.repoManager.repoSearchText },
            set: { self.repoManager.repoSearchText = $0 }
        )
    }

    func toggleRepo(_ repo: String) { repoManager.toggleRepo(repo) }
    func selectAllFilteredRepos() { repoManager.selectAllFilteredRepos() }
    func deselectAllRepos() { repoManager.deselectAllRepos() }
    func saveSelectedReposPublic() { repoManager.saveSelectedRepos() }

    func loadReposIfNeeded() async {
        await repoManager.loadReposIfNeeded()
    }

    func reloadRepos() async {
        await repoManager.reloadRepos()
    }

    // MARK: - Provider Status

    func checkProviderStatusIfNeeded() async {
        guard !hasCheckedProvider else { return }
        hasCheckedProvider = true
        isCheckingProvider = true

        let provider = selectedProviderType.createProvider()
        providerStatus = await provider.checkAvailability()

        isCheckingProvider = false
    }

    func recheckProviderStatus() async {
        hasCheckedProvider = false
        await checkProviderStatusIfNeeded()
    }

    // MARK: - Summary Generation

    func generateSummaries() {
        guard !repoManager.selectedRepos.isEmpty else {
            error = "Please select at least one repository"
            return
        }

        isLoading = true
        error = nil
        statusMessage = "Fetching GitHub user..."

        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        // Check if range is > 7 days
        let daysDiff = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 0

        let weekRanges: [(start: Date, end: Date)]
        if daysDiff > 7 {
            weekRanges = splitIntoWeeks(startDate: rangeStart, endDate: rangeEnd)
        } else {
            weekRanges = [(start: rangeStart, end: rangeEnd)]
        }

        // Create summary entries for each week
        var summaryIds: [UUID] = []
        for (weekStart, weekEnd) in weekRanges {
            let summaryId = UUID()
            summaryIds.append(summaryId)

            let dateRange = DateRangeCommits(
                id: summaryId,
                startDate: weekStart,
                endDate: weekEnd,
                commits: []
            )
            let newSummary = DateRangeSummary(
                id: summaryId,
                dateRange: dateRange,
                status: .pending,
                repositories: Array(repoManager.selectedRepos)
            )

            // Insert in sorted position (by startDate descending)
            let insertIndex = summaries.firstIndex { $0.dateRange.startDate < weekStart } ?? summaries.count
            summaries.insert(newSummary, at: insertIndex)
        }

        // Start generation
        Task {
            await generator.generate(
                weekRanges: weekRanges,
                summaryIds: summaryIds,
                repos: Array(repoManager.selectedRepos),
                providerType: selectedProviderType,
                model: selectedModel,
                callbacks: generatorCallbacks
            )
        }
    }

    func retrySummary(at index: Int) {
        guard index < summaries.count else { return }

        let summary = summaries[index]
        summaries[index].status = .loading
        statusMessage = "Retrying \(summary.dateRange.dateLabel)..."

        Task {
            await generator.retry(
                summary: summary,
                providerType: selectedProviderType,
                model: selectedModel,
                callbacks: generatorCallbacks
            )
        }
    }

    func cancelGeneration() {
        Task {
            await generator.cancelGeneration()
        }
        isLoading = false
        statusMessage = nil

        // Remove any pending/loading summaries
        summaries.removeAll { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    // MARK: - Summary Management

    func clearCache() {
        summaries = []
        AISummaryCacheService.clearCache()
    }

    func deleteSummary(id: UUID) {
        summaries.removeAll { $0.id == id }
        AISummaryCacheService.saveSummaries(summaries)
    }

    func updateSummary(id: UUID, startDate: Date, endDate: Date, repositories: [String]) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }

        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        summaries[index].dateRange = DateRangeCommits(
            id: id,
            startDate: rangeStart,
            endDate: rangeEnd,
            commits: []
        )
        summaries[index].repositories = repositories
        summaries[index].status = .loading
        isLoading = true
        statusMessage = "Updating summary..."

        let repos = repositories

        Task {
            await generator.generate(
                weekRanges: [(start: rangeStart, end: rangeEnd)],
                summaryIds: [id],
                repos: repos,
                providerType: selectedProviderType,
                model: selectedModel,
                callbacks: generatorCallbacks
            )
        }
    }

    // MARK: - Helpers

    private func splitIntoWeeks(startDate: Date, endDate: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var weeks: [(start: Date, end: Date)] = []

        var currentStart = startDate
        while currentStart < endDate {
            var weekEnd = calendar.date(byAdding: .day, value: 6, to: currentStart) ?? currentStart
            weekEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) ?? weekEnd
            if weekEnd > endDate {
                weekEnd = endDate
            }

            weeks.append((start: currentStart, end: weekEnd))
            currentStart = calendar.date(byAdding: .day, value: 1, to: weekEnd) ?? endDate
        }

        return weeks
    }

    private func saveCachedSummaries() {
        AISummaryCacheService.saveSummaries(summaries)
    }
}
