import Foundation

/// GitHub Copilot CLI implementation of AIProvider
actor CopilotProvider: AIProvider {
    static let id = "copilot"
    static let displayName = "Copilot CLI"

    private let executor = AIProviderExecutor(config: .copilot)

    /// Cache for available models (protected by cacheLock since static vars aren't actor-isolated)
    private static var cachedModels: [String]?
    private static let cacheLock = NSLock()

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

        let chunkSize = AIProviderConfig.copilot.hugeCommitChunkSize
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

    // MARK: - Model Discovery

    /// Fetch available models by running copilot with an invalid model name
    static func fetchAvailableModels() async -> [String] {
        cacheLock.lock()
        if let cached = cachedModels {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let shell = ShellExecutor.shared

        do {
            // Run with an intentionally invalid model to get the error listing available models
            _ = try await shell.execute("copilot", arguments: [
                "-p", "test",
                "--model", "___invalid_model_to_list_available___"
            ], timeout: 30)
            return []
        } catch let error as ShellError {
            if case .commandFailed(let output, _) = error {
                let models = parseModelsFromError(output)
                if !models.isEmpty {
                    cacheLock.lock()
                    cachedModels = models
                    cacheLock.unlock()
                    return models
                }
            }
        } catch {
            // Ignore other errors
        }

        return []
    }

    /// Parse model names from copilot error output
    private static func parseModelsFromError(_ output: String) -> [String] {
        var models: [String] = []

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("available") || lowercased.contains("model") {
                let pattern = #"[a-zA-Z0-9][-a-zA-Z0-9._]*[a-zA-Z0-9]"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(line.startIndex..., in: line)
                    let matches = regex.matches(in: line, range: range)
                    for match in matches {
                        if let matchRange = Range(match.range, in: line) {
                            let model = String(line[matchRange])
                            let excludeWords = ["available", "models", "model", "error", "invalid", "the", "are"]
                            if !excludeWords.contains(model.lowercased()) && model.count > 2 {
                                models.append(model)
                            }
                        }
                    }
                }
            }
        }

        return models.uniqued()
    }

    /// Clear cached models to force re-fetch
    static func clearModelCache() {
        cacheLock.lock()
        cachedModels = nil
        cacheLock.unlock()
    }
}

// MARK: - Array Extension for Unique Elements

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
