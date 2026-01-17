import Foundation

/// Claude Code CLI implementation of AIProvider
actor ClaudeProvider: AIProvider {
    static let id = "claude"
    static let displayName = "Claude Code"

    private let shell = ShellExecutor.shared

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

        Focus on:
        1) Main themes or areas of work
        2) Key accomplishments
        3) Patterns (features, fixes, refactoring)

        Keep it concise (2-4 sentences). Do not include the commit SHAs in your response.
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
