import Foundation
import SwiftUI

@MainActor
class AISummaryViewModel: ObservableObject {
    @Published var startDate: Date
    @Published var endDate: Date
    @Published var repoFilter: String = ""
    @Published var weeklySummaries: [WeeklySummary] = []
    @Published var isLoading = false
    @Published var error: String?

    private var generationTask: Task<Void, Never>?

    init() {
        // Default: 1 month ago to today
        let calendar = Calendar.current
        let today = Date()
        self.endDate = today
        self.startDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today
    }

    var hasMorePending: Bool {
        weeklySummaries.contains { summary in
            if case .pending = summary.status { return true }
            if case .loading = summary.status { return true }
            return false
        }
    }

    func generateSummaries() async {
        // Cancel any existing generation
        generationTask?.cancel()

        isLoading = true
        error = nil
        weeklySummaries = []

        generationTask = Task {
            do {
                // Get current user
                guard let currentUser = try? await GitHubService.shared.getCurrentUser() else {
                    self.error = "Could not get current user"
                    self.isLoading = false
                    return
                }

                // Parse repo filter
                let repos = parseRepoFilter()

                // Fetch commits
                let commits = try await GitHubService.shared.fetchUserCommits(
                    author: currentUser,
                    startDate: startDate,
                    endDate: endDate,
                    repos: repos
                )

                if Task.isCancelled { return }

                guard !commits.isEmpty else {
                    self.error = "No commits found in the selected date range"
                    self.isLoading = false
                    return
                }

                // Group commits by week
                let weeklyCommits = groupCommitsByWeek(commits)

                // Initialize summaries with pending status
                self.weeklySummaries = weeklyCommits.map { week in
                    WeeklySummary(week: week, status: .pending)
                }

                // Get the AI provider
                let provider = AIProviderType.claude.createProvider()

                // Launch all summary tasks concurrently
                var tasks: [Int: Task<String, Error>] = [:]
                for (index, summary) in weeklySummaries.enumerated() {
                    let commits = summary.week.commits
                    let weekLabel = summary.week.weekLabel
                    tasks[index] = Task {
                        try await provider.summarizeWeek(commits: commits, weekLabel: weekLabel)
                    }
                }

                // Process results in order for streaming display
                for index in 0..<weeklySummaries.count {
                    if Task.isCancelled { break }

                    // Mark current as loading
                    weeklySummaries[index].status = .loading

                    // Await the pre-launched task
                    if let task = tasks[index] {
                        do {
                            let result = try await task.value
                            if !Task.isCancelled {
                                weeklySummaries[index].status = .completed(result)
                            }
                        } catch {
                            if !Task.isCancelled {
                                weeklySummaries[index].status = .error(error.localizedDescription)
                            }
                        }
                    }
                }

                self.isLoading = false
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }

        await generationTask?.value
    }

    func retrySummary(at index: Int) async {
        guard index < weeklySummaries.count else { return }

        let summary = weeklySummaries[index]
        weeklySummaries[index].status = .loading

        let provider = AIProviderType.claude.createProvider()

        do {
            let result = try await provider.summarizeWeek(
                commits: summary.week.commits,
                weekLabel: summary.week.weekLabel
            )
            weeklySummaries[index].status = .completed(result)
        } catch {
            weeklySummaries[index].status = .error(error.localizedDescription)
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isLoading = false

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
}
