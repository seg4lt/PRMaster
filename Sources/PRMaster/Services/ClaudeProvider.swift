import Foundation

/// Claude Code CLI implementation of AIProvider
actor ClaudeProvider: AIProvider {
    static let id = "claude"
    static let displayName = "Claude Code"

    private let shell = ShellExecutor.shared

    func checkAvailability() async -> AIProviderStatus {
        // Check if claude CLI is installed by running --version
        // We don't run an actual prompt to check auth - that would be wasteful
        // and can trigger unexpected permission dialogs. Auth errors will be
        // caught when the user actually tries to generate summaries.
        do {
            let output = try await shell.execute("claude", arguments: ["--version"])
            // Output is like "2.1.12 (Claude Code)" - just check it's not empty
            if !output.isEmpty {
                return .available
            }
            return .notInstalled(message: "Claude Code not installed")
        } catch {
            return .notInstalled(message: "Claude Code not installed")
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

        do {
            let output = try await shell.execute("claude", arguments: [
                "-p", prompt,
                "--output-format", "json",
                "--max-turns", "1"
            ])

            // Parse the JSON response
            guard let data = output.data(using: .utf8) else {
                throw AIProviderError.invalidResponse
            }

            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return response.result
        } catch let error as ShellError {
            switch error {
            case .commandFailed(let output, _):
                throw AIProviderError.executionFailed(output)
            case .commandNotFound:
                throw AIProviderError.notInstalled
            }
        } catch let error as AIProviderError {
            throw error
        } catch {
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
