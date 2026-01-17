import Foundation

/// Claude Code CLI implementation of AIProvider
actor ClaudeProvider: AIProvider {
    static let id = "claude"
    static let displayName = "Claude Code"

    private let executor = AIProviderExecutor(config: .claude)

    func checkAvailability() async -> AIProviderStatus {
        await executor.checkAvailability()
    }

    func summarizeDateRange(
        commits: [Commit],
        dateLabel: String,
        model: String? = nil
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits in this date range."
        }

        let prompt = await executor.buildCommitListPrompt(commits: commits, dateLabel: dateLabel)
        let displayPrompt = "Summarize \(dateLabel) (\(commits.count) commits)"
        return try await executor.execute(prompt: prompt, model: model, displayPrompt: displayPrompt)
    }

    func summarizeDateRange(
        commits: [EnrichedCommit],
        dateLabel: String,
        model: String? = nil
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits in this date range."
        }

        let batches = await executor.createBatches(from: commits)

        if batches.count == 1 {
            return try await summarizeBatch(
                commits: batches[0],
                dateLabel: dateLabel,
                model: model,
                isFinalSummary: true
            )
        } else {
            var batchSummaries: [String] = []

            for (index, batch) in batches.enumerated() {
                let batchLabel = "\(dateLabel) (batch \(index + 1)/\(batches.count))"
                let summary = try await summarizeBatch(
                    commits: batch,
                    dateLabel: batchLabel,
                    model: model,
                    isFinalSummary: false
                )
                batchSummaries.append(summary)
            }

            return try await combineSummaries(batchSummaries, dateLabel: dateLabel, model: model)
        }
    }

    func summarizeHugeCommit(_ commit: EnrichedCommit, model: String?) async throws -> String {
        guard let diff = commit.diff else {
            return commit.commit.message
        }

        let chunkSize = AIProviderConfig.claude.hugeCommitChunkSize
        let chunks = diff.chunked(into: chunkSize)

        if chunks.count == 1 {
            return diff
        }

        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let prompt = await executor.buildChunkSummaryPrompt(chunk: chunk, index: index, total: chunks.count)
            let displayPrompt = "Chunk \(index + 1)/\(chunks.count) of \(commit.commit.shortSha)"
            let summary = try await executor.execute(prompt: prompt, model: model, displayPrompt: displayPrompt)
            chunkSummaries.append(summary)
        }

        return chunkSummaries.joined(separator: "\n\n")
    }

    // MARK: - Private Helpers

    private func summarizeBatch(
        commits: [EnrichedCommit],
        dateLabel: String,
        model: String?,
        isFinalSummary: Bool
    ) async throws -> String {
        let prompt = await executor.buildEnrichedCommitListPrompt(
            commits: commits,
            dateLabel: dateLabel,
            isFinalSummary: isFinalSummary
        )
        let displayPrompt = "Summarize \(dateLabel) (\(commits.count) commits with diffs)"
        return try await executor.execute(prompt: prompt, model: model, displayPrompt: displayPrompt)
    }

    private func combineSummaries(_ summaries: [String], dateLabel: String, model: String?) async throws -> String {
        let prompt = await executor.buildCombineSummariesPrompt(summaries: summaries, dateLabel: dateLabel)
        let displayPrompt = "Combine \(summaries.count) batch summaries"
        return try await executor.execute(prompt: prompt, model: model, displayPrompt: displayPrompt)
    }
}

// MARK: - String Chunking Extension

extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0, count > size else { return [self] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}
