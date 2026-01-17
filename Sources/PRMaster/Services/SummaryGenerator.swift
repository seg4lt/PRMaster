import Foundation

/// Callbacks for summary generation progress updates
struct SummaryGeneratorCallbacks {
    let onStatusUpdate: @MainActor (String?) -> Void
    let onSummaryUpdate: @MainActor (UUID, SummaryStatus) -> Void
    let onComplete: @MainActor () -> Void
    let onFail: @MainActor (String) -> Void
    let getSummary: @MainActor (UUID) -> DateRangeSummary?
}

/// Service responsible for generating AI summaries
actor SummaryGenerator {
    private var generationTask: Task<Void, Never>?
    private var retryTasks: [UUID: Task<Void, Never>] = [:]

    /// Generate summaries for the given week ranges
    func generate(
        weekRanges: [(start: Date, end: Date)],
        summaryIds: [UUID],
        repos: [String],
        providerType: AIProviderType,
        model: String?,
        callbacks: SummaryGeneratorCallbacks
    ) {
        // Cancel any existing generation
        generationTask?.cancel()

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Get current user
            await MainActor.run {
                callbacks.onStatusUpdate("Fetching GitHub user...")
            }

            guard let currentUser = try? await GitHubService.shared.getCurrentUser() else {
                await MainActor.run {
                    callbacks.onFail("Could not get current user")
                }
                return
            }

            if Task.isCancelled { return }

            let provider = providerType.createProvider()

            // Process each week sequentially
            for summaryId in summaryIds {
                if Task.isCancelled { return }

                guard let summary = await MainActor.run(body: { callbacks.getSummary(summaryId) }) else {
                    continue
                }

                let weekStart = summary.dateRange.startDate
                let weekEnd = summary.dateRange.endDate
                let dateLabel = summary.dateRange.dateLabel

                // Mark as loading
                await MainActor.run {
                    callbacks.onSummaryUpdate(summaryId, .loading)
                    callbacks.onStatusUpdate("Fetching commits for \(dateLabel)...")
                }

                do {
                    let result = try await self.processSummary(
                        weekStart: weekStart,
                        weekEnd: weekEnd,
                        dateLabel: dateLabel,
                        repos: repos,
                        currentUser: currentUser,
                        provider: provider,
                        model: model,
                        onStatusUpdate: callbacks.onStatusUpdate
                    )

                    if !Task.isCancelled {
                        await MainActor.run {
                            callbacks.onSummaryUpdate(summaryId, .completed(result))
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            callbacks.onSummaryUpdate(summaryId, .error(error.localizedDescription))
                        }
                    }
                }
            }

            // All weeks processed
            await MainActor.run {
                callbacks.onComplete()
            }
        }
    }

    /// Process a single summary
    private func processSummary(
        weekStart: Date,
        weekEnd: Date,
        dateLabel: String,
        repos: [String],
        currentUser: String,
        provider: any AIProvider,
        model: String?,
        onStatusUpdate: @escaping @MainActor (String?) -> Void
    ) async throws -> String {
        // Fetch commits
        let commits = try await GitHubService.shared.fetchUserCommits(
            author: currentUser,
            startDate: weekStart,
            endDate: weekEnd,
            repos: repos
        )

        if Task.isCancelled {
            throw CancellationError()
        }

        if commits.isEmpty {
            return "No commits in this date range."
        }

        // Fetch diffs
        await MainActor.run {
            onStatusUpdate("Fetching diffs for \(dateLabel) (\(commits.count) commits)...")
        }

        let diffs = await GitHubService.shared.fetchCommitDiffs(commits: commits)

        if Task.isCancelled {
            throw CancellationError()
        }

        // Create enriched commits
        var enrichedCommits = commits.map { commit in
            EnrichedCommit(commit: commit, diff: diffs[commit.sha])
        }

        // Pre-process huge commits
        var processedCommits: [EnrichedCommit] = []
        for enriched in enrichedCommits {
            if enriched.sizeCategory == .huge {
                await MainActor.run {
                    onStatusUpdate("Summarizing large diff for \(enriched.commit.shortSha)...")
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
                onStatusUpdate("Summarizing \(dateLabel) (\(commits.count) commits in \(batches.count) batches)...")
            } else {
                onStatusUpdate("Summarizing \(dateLabel) (\(commits.count) commits)...")
            }
        }

        return try await provider.summarizeDateRange(commits: enrichedCommits, dateLabel: dateLabel, model: model)
    }

    /// Retry a failed summary
    func retry(
        summary: DateRangeSummary,
        providerType: AIProviderType,
        model: String?,
        callbacks: SummaryGeneratorCallbacks
    ) {
        let summaryId = summary.id

        // Cancel any existing retry for this summary
        retryTasks[summaryId]?.cancel()

        retryTasks[summaryId] = Task.detached { [weak self] in
            guard let self = self else { return }

            let commits = summary.dateRange.commits
            let dateLabel = summary.dateRange.dateLabel

            do {
                await MainActor.run {
                    callbacks.onStatusUpdate("Fetching diffs for \(dateLabel)...")
                }

                let diffs = await GitHubService.shared.fetchCommitDiffs(commits: commits)

                let enrichedCommits = commits.map { commit in
                    EnrichedCommit(commit: commit, diff: diffs[commit.sha])
                }

                await MainActor.run {
                    callbacks.onStatusUpdate("Summarizing \(dateLabel)...")
                }

                let provider = providerType.createProvider()
                let result = try await provider.summarizeDateRange(
                    commits: enrichedCommits,
                    dateLabel: dateLabel,
                    model: model
                )

                await MainActor.run {
                    callbacks.onSummaryUpdate(summaryId, .completed(result))
                    callbacks.onStatusUpdate(nil)
                }
            } catch {
                await MainActor.run {
                    callbacks.onSummaryUpdate(summaryId, .error(error.localizedDescription))
                    callbacks.onStatusUpdate(nil)
                }
            }

            await self.removeRetryTask(for: summaryId)
        }
    }

    private func removeRetryTask(for id: UUID) {
        retryTasks.removeValue(forKey: id)
    }

    /// Cancel all ongoing generation
    func cancelGeneration() {
        generationTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
    }
}
