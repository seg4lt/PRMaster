import Foundation

/// Claude Code CLI implementation of AIProvider
actor ClaudeProvider: AIProvider {
    static let id = "claude"
    static let displayName = "Claude Code"

    private let shell = ShellExecutor.shared

    /// Timeout for AI summarization (180 seconds for larger batches)
    private let summarizationTimeout: TimeInterval = 180

    func checkAvailability() async -> AIProviderStatus {
        // Check if claude CLI is installed by running --version
        let start = Date()

        do {
            // Use a shorter timeout for version check (10 seconds)
            let output = try await shell.execute("claude", arguments: ["--version"], timeout: 10)
            let duration = Date().timeIntervalSince(start)

            await GitHubService.shared.addExternalLog(
                command: "claude --version",
                duration: duration,
                success: true,
                prompt: nil
            )

            // Output is like "2.1.12 (Claude Code)" - just check it's not empty
            if !output.isEmpty {
                return .available
            }
            return .notInstalled(message: "Claude Code not installed")
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)

            switch error {
            case .commandNotFound(let cmd):
                await GitHubService.shared.addExternalLog(
                    command: "claude --version",
                    duration: duration,
                    success: false,
                    prompt: "Command not found: \(cmd)"
                )
                return .notInstalled(message: "Claude Code not found in PATH")

            case .commandFailed(let output, let code):
                await GitHubService.shared.addExternalLog(
                    command: "claude --version",
                    duration: duration,
                    success: false,
                    prompt: "Exit code \(code)"
                )
                // Surface the actual error
                let truncatedOutput = output.prefix(200)
                return .error("Exit \(code): \(truncatedOutput)")

            case .timeout(let seconds):
                await GitHubService.shared.addExternalLog(
                    command: "claude --version",
                    duration: duration,
                    success: false,
                    prompt: "Timeout after \(Int(seconds))s"
                )
                return .error("Claude command timed out after \(Int(seconds))s")
            }
        } catch {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "claude --version",
                duration: duration,
                success: false,
                prompt: error.localizedDescription
            )
            return .error(error.localizedDescription)
        }
    }

    func summarizeWeek(
        commits: [Commit],
        weekLabel: String
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits this week."
        }

        // Build the commit list for the prompt
        let commitList = commits.map { commit in
            "- [\(commit.shortSha)] \(commit.repository): \(commit.firstLine)"
        }.joined(separator: "\n")

        let prompt = """
        Summarize these commits from \(weekLabel):

        \(commitList)

        Output as markdown with:
        - A "## \(weekLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Each bullet should describe a key change, feature, or fix
        - Keep bullets concise (1 line each)

        Do not include commit SHAs.
        """

        let start = Date()
        let displayPrompt = "Summarize \(weekLabel) (\(commits.count) commits)"

        do {
            // Use a longer timeout for AI summarization (120 seconds)
            let output = try await shell.execute("claude", arguments: [
                "-p", prompt,
                "--output-format", "json",
                "--max-turns", "1"
            ], timeout: 120)

            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "claude",
                duration: duration,
                success: true,
                prompt: displayPrompt
            )

            // Parse the JSON response
            guard let data = output.data(using: .utf8) else {
                throw AIProviderError.invalidResponse
            }

            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return response.result
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "claude",
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
                command: "claude",
                duration: duration,
                success: false,
                prompt: displayPrompt
            )
            throw AIProviderError.executionFailed(error.localizedDescription)
        }
    }

    // MARK: - Enriched Commit Summarization

    /// Summarize a week using enriched commits with diffs
    func summarizeWeekEnriched(
        commits: [EnrichedCommit],
        weekLabel: String
    ) async throws -> String {
        guard !commits.isEmpty else {
            return "No commits this week."
        }

        // Create batches based on token limits
        let batches = CommitBatcher.createBatches(from: commits)

        if batches.count == 1 {
            // Single batch - direct summarization
            return try await summarizeBatch(commits: batches[0], weekLabel: weekLabel, isFinalSummary: true)
        } else {
            // Multiple batches - summarize each, then combine
            var batchSummaries: [String] = []

            for (index, batch) in batches.enumerated() {
                let batchLabel = "\(weekLabel) (batch \(index + 1)/\(batches.count))"
                let summary = try await summarizeBatch(commits: batch, weekLabel: batchLabel, isFinalSummary: false)
                batchSummaries.append(summary)
            }

            // Combine all batch summaries into final summary
            return try await combineSummaries(batchSummaries, weekLabel: weekLabel)
        }
    }

    /// Summarize a single batch of commits
    private func summarizeBatch(
        commits: [EnrichedCommit],
        weekLabel: String,
        isFinalSummary: Bool
    ) async throws -> String {
        // Build the detailed commit list for the prompt
        let commitList = commits.map { enriched -> String in
            let commit = enriched.commit
            var entry = """
            ### [\(commit.shortSha)] \(commit.repository)
            **Message:**
            \(commit.message)
            """

            if let diff = enriched.truncatedDiff {
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
            - A "## \(weekLabel)" heading
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
        Summarize these commits from \(weekLabel):

        \(commitList)

        \(outputInstructions)

        Do not include commit SHAs. Analyze the diffs to provide meaningful summaries.
        """

        return try await executeClaudePrompt(prompt: prompt, displayPrompt: "Summarize \(weekLabel) (\(commits.count) commits with diffs)")
    }

    /// Combine multiple batch summaries into a final weekly summary
    private func combineSummaries(_ summaries: [String], weekLabel: String) async throws -> String {
        let combinedInput = summaries.enumerated().map { index, summary in
            """
            ### Batch \(index + 1):
            \(summary)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Combine these partial summaries into a single cohesive weekly summary for \(weekLabel):

        \(combinedInput)

        Output as markdown with:
        - A "## \(weekLabel)" heading
        - Bullet points grouped by repository (use "**repo-name**:" as sub-heading)
        - Deduplicate any overlapping changes
        - Consolidate related items
        - Keep bullets concise (1-2 lines each)
        """

        return try await executeClaudePrompt(prompt: prompt, displayPrompt: "Combine \(summaries.count) batch summaries")
    }

    /// Execute a Claude prompt and return the result
    private func executeClaudePrompt(prompt: String, displayPrompt: String) async throws -> String {
        let start = Date()

        do {
            let output = try await shell.execute("claude", arguments: [
                "-p", prompt,
                "--output-format", "json",
                "--max-turns", "1"
            ], timeout: summarizationTimeout)

            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "claude",
                duration: duration,
                success: true,
                prompt: displayPrompt
            )

            // Parse the JSON response
            guard let data = output.data(using: .utf8) else {
                throw AIProviderError.invalidResponse
            }

            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return response.result
        } catch let error as ShellError {
            let duration = Date().timeIntervalSince(start)
            await GitHubService.shared.addExternalLog(
                command: "claude",
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
                command: "claude",
                duration: duration,
                success: false,
                prompt: displayPrompt
            )
            throw AIProviderError.executionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Claude Response Models

private struct ClaudeResponse: Codable {
    let result: String
    let costUsd: Double?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case result
        case costUsd = "cost_usd"
        case sessionId = "session_id"
    }
}
