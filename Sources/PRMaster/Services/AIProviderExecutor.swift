import Foundation

/// Shared executor for AI provider operations
actor AIProviderExecutor {
    private let config: AIProviderConfig
    private let shell = ShellExecutor.shared

    init(config: AIProviderConfig) {
        self.config = config
    }

    // MARK: - Availability Check

    func checkAvailability() async -> AIProviderStatus {
        let start = Date()

        do {
            let output = try await shell.execute(
                config.cliCommand,
                arguments: ["--version"],
                timeout: 10
            )
            let duration = Date().timeIntervalSince(start)

            await GitHubService.shared.addExternalLog(
                command: "\(config.cliCommand) --version",
                duration: duration,
                success: true,
                prompt: nil
            )

            if !output.isEmpty {
                return .available
            }
            return .notInstalled(message: "\(config.displayName) not installed")
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)
            return await handleShellError(error, command: "\(config.cliCommand) --version", duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "\(config.cliCommand) --version",
                duration: duration,
                success: false,
                prompt: error.localizedDescription
            )
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Prompt Execution

    func execute(prompt: String, model: String?, displayPrompt: String) async throws -> String {
        let start = Date()

        do {
            let arguments = config.buildArguments(prompt, model)
            let output = try await shell.execute(
                config.cliCommand,
                arguments: arguments,
                timeout: config.timeout
            )

            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: config.cliCommand,
                duration: duration,
                success: true,
                prompt: displayPrompt
            )

            return try config.parseResponse(output)
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: config.cliCommand,
                duration: duration,
                success: false,
                prompt: displayPrompt
            )
            throw mapShellError(error)
        } catch let error as AIProviderError {
            throw error
        } catch {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: config.cliCommand,
                duration: duration,
                success: false,
                prompt: displayPrompt
            )
            throw AIProviderError.executionFailed(error.localizedDescription)
        }
    }

    // MARK: - Batching

    func createBatches(from commits: [EnrichedCommit]) -> [[EnrichedCommit]] {
        guard !commits.isEmpty else { return [] }

        let sorted = commits.sorted { $0.estimatedTokens < $1.estimatedTokens }

        var batches: [[EnrichedCommit]] = []
        var currentBatch: [EnrichedCommit] = []
        var currentTokens = 0

        for commit in sorted {
            let tokens = commit.estimatedTokens

            switch commit.sizeCategory {
            case .huge, .large:
                // Large/huge commits get their own batch
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                    currentBatch = []
                    currentTokens = 0
                }
                batches.append([commit])

            case .medium:
                if currentBatch.count >= config.batchLimitMedium || currentTokens + tokens > config.maxTokensPerCall {
                    if !currentBatch.isEmpty {
                        batches.append(currentBatch)
                    }
                    currentBatch = [commit]
                    currentTokens = tokens
                } else {
                    currentBatch.append(commit)
                    currentTokens += tokens
                }

            case .small:
                if currentBatch.count >= config.batchLimitSmall || currentTokens + tokens > config.maxTokensPerCall {
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
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    // MARK: - Prompt Building

    func buildCommitListPrompt(commits: [Commit], dateLabel: String) -> String {
        let commitList = commits.map { commit in
            "- [\(commit.shortSha)] \(commit.repository): \(commit.firstLine)"
        }.joined(separator: "\n")

        return """
        Summarize these commits from \(dateLabel):

        \(commitList)

        Output as markdown with:
        - A "## \(dateLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Each bullet should describe a key change, feature, or fix
        - Keep bullets concise (1 line each)

        Do not include commit SHAs.
        """
    }

    func buildEnrichedCommitListPrompt(
        commits: [EnrichedCommit],
        dateLabel: String,
        isFinalSummary: Bool
    ) -> String {
        let commitList = commits.map { enriched -> String in
            let commit = enriched.commit
            var entry = """
            ### [\(commit.shortSha)] \(commit.repository)
            **Message:**
            \(commit.message)
            """

            if var diff = enriched.diff {
                // Truncate if config specifies a max
                if let maxChars = config.maxDiffChars, diff.count > maxChars {
                    diff = String(diff.prefix(maxChars)) + "\n... [truncated]"
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

        return """
        Summarize these commits from \(dateLabel):

        \(commitList)

        \(outputInstructions)

        Do not include commit SHAs. Analyze the diffs to provide meaningful summaries.
        """
    }

    func buildCombineSummariesPrompt(summaries: [String], dateLabel: String) -> String {
        let combinedInput = summaries.enumerated().map { index, summary in
            """
            ### Batch \(index + 1):
            \(summary)
            """
        }.joined(separator: "\n\n")

        return """
        Combine these partial summaries into a single cohesive summary for \(dateLabel):

        \(combinedInput)

        Output as markdown with:
        - A "## \(dateLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Deduplicate any overlapping changes
        - Consolidate related items
        - Keep bullets concise (1-2 lines each)
        """
    }

    func buildChunkSummaryPrompt(chunk: String, index: Int, total: Int) -> String {
        return """
        Summarize this portion (\(index + 1)/\(total)) of a code diff:

        ```diff
        \(chunk)
        ```

        List the key changes in this diff section as concise bullet points.
        Focus on WHAT changed (files, functions, features), not line-by-line details.
        """
    }

    // MARK: - Error Handling

    private func handleShellError(_ error: ShellError, command: String, duration: TimeInterval) async -> AIProviderStatus {
        switch error {
        case .commandNotFound(let cmd):
            await GitHubService.shared.addExternalLog(
                command: command,
                duration: duration,
                success: false,
                prompt: "Command not found: \(cmd)"
            )
            return .notInstalled(message: "\(config.displayName) not found in PATH")

        case .commandFailed(let output, let code):
            await GitHubService.shared.addExternalLog(
                command: command,
                duration: duration,
                success: false,
                prompt: "Exit code \(code)"
            )
            let truncatedOutput = output.prefix(200)
            return .error("Exit \(code): \(truncatedOutput)")

        case .timeout(let seconds):
            await GitHubService.shared.addExternalLog(
                command: command,
                duration: duration,
                success: false,
                prompt: "Timeout after \(Int(seconds))s"
            )
            return .error("\(config.displayName) command timed out after \(Int(seconds))s")
        }
    }

    private func mapShellError(_ error: ShellError) -> AIProviderError {
        switch error {
        case .commandFailed(let output, _):
            return .executionFailed(output)
        case .commandNotFound:
            return .notInstalled
        case .timeout(let seconds):
            return .executionFailed("Request timed out after \(Int(seconds)) seconds")
        }
    }
}
