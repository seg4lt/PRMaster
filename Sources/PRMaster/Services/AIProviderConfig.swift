import Foundation

/// Configuration for an AI provider's CLI interface
struct AIProviderConfig {
    let cliCommand: String
    let displayName: String
    let maxTokensPerCall: Int
    let maxDiffChars: Int?  // nil = no truncation
    let hugeCommitChunkSize: Int
    let batchLimitSmall: Int
    let batchLimitMedium: Int
    let timeout: TimeInterval

    /// Build CLI arguments for executing a prompt
    let buildArguments: (_ prompt: String, _ model: String?) -> [String]

    /// Parse the CLI output to extract the result
    let parseResponse: (_ output: String) throws -> String
}

// MARK: - Provider Configurations

extension AIProviderConfig {
    /// Claude Code CLI configuration
    static let claude = AIProviderConfig(
        cliCommand: "claude",
        displayName: "Claude Code",
        maxTokensPerCall: 60_000,
        maxDiffChars: nil,  // No truncation for Claude
        hugeCommitChunkSize: 200_000,
        batchLimitSmall: 30,
        batchLimitMedium: 6,
        timeout: 180
    ) { prompt, model in
        var arguments = [
            "-p", prompt,
            "--output-format", "json",
            "--max-turns", "1"
        ]
        if let model = model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    } parseResponse: { output in
        guard let data = output.data(using: .utf8) else {
            throw AIProviderError.invalidResponse
        }
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return response.result
    }

    /// Copilot CLI configuration
    static let copilot = AIProviderConfig(
        cliCommand: "copilot",
        displayName: "Copilot CLI",
        maxTokensPerCall: 20_000,
        maxDiffChars: 8_000,  // Truncate diffs for Copilot's smaller context
        hugeCommitChunkSize: 20_000,
        batchLimitSmall: 8,
        batchLimitMedium: 4,
        timeout: 180
    ) { prompt, model in
        var arguments = ["-p", prompt]
        if let model = model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    } parseResponse: { output in
        // Copilot returns plain text, filter out usage statistics
        filterCopilotUsageStatistics(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get config for a provider type
    static func config(for type: AIProviderType) -> AIProviderConfig {
        switch type {
        case .claude: return .claude
        case .copilot: return .copilot
        }
    }
}

// MARK: - Claude Response Model

struct ClaudeResponse: Codable {
    let result: String
    let costUsd: Double?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case result
        case costUsd = "cost_usd"
        case sessionId = "session_id"
    }
}

// MARK: - Copilot Output Filtering

private func filterCopilotUsageStatistics(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")

    for i in 0..<lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("Total usage") {
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
