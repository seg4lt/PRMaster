import Foundation

/// GitHub Copilot CLI implementation of AIProvider
actor CopilotProvider: AIProvider {
    static let id = "copilot"
    static let displayName = "Copilot CLI"

    private let shell = ShellExecutor.shared

    /// Timeout for AI summarization (180 seconds for larger batches)
    private let summarizationTimeout: TimeInterval = 180

    /// Cache for available models (protected by cacheLock since static vars aren't actor-isolated)
    private static var cachedModels: [String]?
    private static let cacheLock = NSLock()

    func checkAvailability() async -> AIProviderStatus {
        let start = Date()

        do {
            // Check if copilot CLI is installed by running --version
            let output = try await shell.execute("copilot", arguments: ["--version"], timeout: 10)
            let duration = Date().timeIntervalSince(start)

            await GitHubService.shared.addExternalLog(
                command: "copilot --version",
                duration: duration,
                success: true,
                prompt: nil
            )

            if !output.isEmpty {
                return .available
            }
            return .notInstalled(message: "Copilot CLI not installed")
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)

            switch error {
            case .commandNotFound(let cmd):
                await GitHubService.shared.addExternalLog(
                    command: "copilot --version",
                    duration: duration,
                    success: false,
                    prompt: "Command not found: \(cmd)"
                )
                return .notInstalled(message: "Copilot CLI not found in PATH")

            case .commandFailed(let output, let code):
                await GitHubService.shared.addExternalLog(
                    command: "copilot --version",
                    duration: duration,
                    success: false,
                    prompt: "Exit code \(code)"
                )
                let truncatedOutput = output.prefix(200)
                return .error("Exit \(code): \(truncatedOutput)")

            case .timeout(let seconds):
                await GitHubService.shared.addExternalLog(
                    command: "copilot --version",
                    duration: duration,
                    success: false,
                    prompt: "Timeout after \(Int(seconds))s"
                )
                return .error("Copilot command timed out after \(Int(seconds))s")
            }
        } catch {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "copilot --version",
                duration: duration,
                success: false,
                prompt: error.localizedDescription
            )
            return .error(error.localizedDescription)
        }
    }

    func summarizeDateRange(
        commits: [Commit],
        dateLabel: String,
        model: String? = nil
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits in this date range."
        }

        // Build the commit list for the prompt
        let commitList = commits.map { commit in
            "- [\(commit.shortSha)] \(commit.repository): \(commit.firstLine)"
        }.joined(separator: "\n")

        let prompt = """
        Summarize these commits from \(dateLabel):

        \(commitList)

        Output as markdown with:
        - A "## \(dateLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Each bullet should describe a key change, feature, or fix
        - Keep bullets concise (1 line each)

        Do not include commit SHAs.
        """

        return try await executeCopilotPrompt(
            prompt: prompt,
            model: model,
            displayPrompt: "Summarize \(dateLabel) (\(commits.count) commits)"
        )
    }

    // MARK: - Enriched Commit Summarization

    /// Max tokens for Copilot (64K limit, leave generous room for prompt overhead and response)
    private static let maxTokensPerCall = 20_000

    func summarizeDateRange(
        commits: [EnrichedCommit],
        dateLabel: String,
        model: String? = nil
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits in this date range."
        }

        // Create smaller batches for Copilot's 64K token limit
        let batches = createCopilotBatches(from: commits)

        if batches.count == 1 {
            return try await summarizeBatch(commits: batches[0], dateLabel: dateLabel, model: model, isFinalSummary: true)
        } else {
            var batchSummaries: [String] = []

            for (index, batch) in batches.enumerated() {
                let batchLabel = "\(dateLabel) (batch \(index + 1)/\(batches.count))"
                let summary = try await summarizeBatch(commits: batch, dateLabel: batchLabel, model: model, isFinalSummary: false)
                batchSummaries.append(summary)
            }

            return try await combineSummaries(batchSummaries, dateLabel: dateLabel, model: model)
        }
    }

    /// Create smaller batches for Copilot's token limit
    private func createCopilotBatches(from commits: [EnrichedCommit]) -> [[EnrichedCommit]] {
        guard !commits.isEmpty else { return [] }

        let sorted = commits.sorted { $0.estimatedTokens < $1.estimatedTokens }

        var batches: [[EnrichedCommit]] = []
        var currentBatch: [EnrichedCommit] = []
        var currentTokens = 0

        for commit in sorted {
            let tokens = commit.estimatedTokens

            // Huge commits get their own batch
            if commit.sizeCategory == .huge || commit.sizeCategory == .large {
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                    currentBatch = []
                    currentTokens = 0
                }
                batches.append([commit])
            } else if currentTokens + tokens > Self.maxTokensPerCall || currentBatch.count >= 8 {
                // Start new batch if would exceed limit or too many commits
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                }
                currentBatch = [commit]
                currentTokens = tokens
            } else {
                currentBatch.append(commit)
                currentTokens += tokens
            }
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    /// Max chars per diff to avoid token overflow (~8K chars at 2:1 ratio ≈ 4K tokens)
    private static let maxDiffChars = 8_000

    private func summarizeBatch(
        commits: [EnrichedCommit],
        dateLabel: String,
        model: String?,
        isFinalSummary: Bool
    ) async throws -> String {
        let commitList = commits.map { enriched -> String in
            let commit = enriched.commit
            var entry = """
            ### [\(commit.shortSha)] \(commit.repository)
            **Message:**
            \(commit.message)
            """

            if var diff = enriched.diff {
                // Truncate large diffs to fit Copilot's token limit
                if diff.count > Self.maxDiffChars {
                    diff = String(diff.prefix(Self.maxDiffChars)) + "\n... [truncated]"
                }
                entry += """

                **Diff:**
                ```diff
                \(diff)
                ```
                """
            }

            return entry
        }.joined(separator: "\n\n---\n\n")

        let outputInstructions: String
        if isFinalSummary {
            outputInstructions = """
            Output as markdown with:
            - A "## \(dateLabel)" heading
            - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
            - Each bullet should describe a key change, feature, or fix
            - Keep bullets concise (1-2 lines each)
            - Focus on WHAT was accomplished, not low-level details
            """
        } else {
            outputInstructions = """
            Output as markdown bullet points grouped by repository.
            - Each bullet should describe a key change, feature, or fix
            - Keep bullets concise (1-2 lines each)
            - Focus on WHAT was accomplished
            - Do NOT include a heading (this is a partial batch)
            """
        }

        let prompt = """
        Summarize these commits from \(dateLabel):

        \(commitList)

        \(outputInstructions)

        Do not include commit SHAs. Analyze the diffs to provide meaningful summaries.
        """

        return try await executeCopilotPrompt(
            prompt: prompt,
            model: model,
            displayPrompt: "Summarize \(dateLabel) (\(commits.count) commits with diffs)"
        )
    }

    func summarizeHugeCommit(_ commit: EnrichedCommit, model: String?) async throws -> String {
        guard let diff = commit.diff else {
            return commit.commit.message
        }

        // Copilot has 64K token limit, use ~20K chars at 2:1 ratio (~10K tokens) to leave room for prompt
        let chunkSize = 20_000
        let chunks = diff.chunked(into: chunkSize)

        if chunks.count == 1 {
            return diff
        }

        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            Summarize this portion (\(index + 1)/\(chunks.count)) of a code diff:

            ```diff
            \(chunk)
            ```

            List the key changes in this diff section as concise bullet points.
            Focus on WHAT changed (files, functions, features), not line-by-line details.
            """

            let summary = try await executeCopilotPrompt(
                prompt: prompt,
                model: model,
                displayPrompt: "Chunk \(index + 1)/\(chunks.count) of \(commit.commit.shortSha)"
            )
            chunkSummaries.append(summary)
        }

        return chunkSummaries.joined(separator: "\n\n")
    }

    private func combineSummaries(_ summaries: [String], dateLabel: String, model: String?) async throws -> String {
        let combinedInput = summaries.enumerated().map { index, summary in
            """
            ### Batch \(index + 1):
            \(summary)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Combine these partial summaries into a single cohesive summary for \(dateLabel):

        \(combinedInput)

        Output as markdown with:
        - A "## \(dateLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Deduplicate any overlapping changes
        - Consolidate related items
        - Keep bullets concise (1-2 lines each)
        """

        return try await executeCopilotPrompt(
            prompt: prompt,
            model: model,
            displayPrompt: "Combine \(summaries.count) batch summaries"
        )
    }

    /// Execute a Copilot prompt and return the result
    private func executeCopilotPrompt(prompt: String, model: String?, displayPrompt: String) async throws -> String {
        let start = Date()

        do {
            var arguments = ["-p", prompt]
            if let model = model, !model.isEmpty {
                arguments.append(contentsOf: ["--model", model])
            }

            let output = try await shell.execute("copilot", arguments: arguments, timeout: summarizationTimeout)

            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "copilot",
                duration: duration,
                success: true,
                prompt: displayPrompt
            )

            // Copilot returns plain text, not JSON
            // Filter out usage statistics that Copilot CLI appends to output
            let filtered = filterUsageStatistics(output)
            return filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "copilot",
                duration: duration,
                success: false,
                prompt: displayPrompt
            )

            switch error {
            case .commandFailed(let output, _):
                throw AIProviderError.executionFailed(output)
            case .commandNotFound:
                throw AIProviderError.notInstalled
            case .timeout(let seconds):
                throw AIProviderError.executionFailed("Request timed out after \(Int(seconds)) seconds")
            }
        } catch let error as AIProviderError {
            throw error
        } catch {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "copilot",
                duration: duration,
                success: false,
                prompt: displayPrompt
            )
            throw AIProviderError.executionFailed(error.localizedDescription)
        }
    }

    /// Filter out Copilot CLI usage statistics from output
    private func filterUsageStatistics(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Total usage") {
                // Look ahead: confirm next line is also usage stats
                if i + 1 < lines.count {
                    let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("Total duration") {
                        return lines[0..<i].joined(separator: "\n")
                    }
                }
            }
        }

        return text
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
            // If it succeeds somehow, return empty
            return []
        } catch let error as ShellError {
            if case .commandFailed(let output, _) = error {
                // Parse the error message to extract model names
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
        // Copilot typically lists models in the error like:
        // "Available models: gpt-4, gpt-3.5-turbo, claude-3-opus, ..."
        // or line by line. Try to extract them.

        var models: [String] = []

        // Try to find "Available models:" or similar pattern
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("available") || lowercased.contains("model") {
                // Look for model names (alphanumeric with dashes/dots)
                let pattern = #"[a-zA-Z0-9][-a-zA-Z0-9._]*[a-zA-Z0-9]"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(line.startIndex..., in: line)
                    let matches = regex.matches(in: line, range: range)
                    for match in matches {
                        if let matchRange = Range(match.range, in: line) {
                            let model = String(line[matchRange])
                            // Filter out common non-model words
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
