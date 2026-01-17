import Foundation

/// Status of an AI provider's availability
enum AIProviderStatus {
    case available
    case notInstalled(message: String)
    case notAuthenticated(message: String)
    case error(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

/// Errors that can occur during AI provider operations
enum AIProviderError: Error, LocalizedError {
    case notInstalled
    case notAuthenticated
    case executionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude Code CLI is not installed"
        case .notAuthenticated:
            return "Claude Code is not authenticated"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .invalidResponse:
            return "Invalid response from AI provider"
        }
    }
}

/// Protocol for AI providers that can summarize commits
protocol AIProvider {
    /// Unique identifier for this provider
    static var id: String { get }

    /// Display name for settings UI
    static var displayName: String { get }

    /// Check if provider is available (installed, authenticated, etc.)
    func checkAvailability() async -> AIProviderStatus

    /// Summarize commits for a given week
    func summarizeWeek(
        commits: [Commit],
        weekLabel: String
    ) async throws -> String
}

/// Available AI provider types
enum AIProviderType: String, CaseIterable, Codable {
    case claude = "claude"
    // Future: case copilot = "copilot"

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        }
    }

    func createProvider() -> any AIProvider {
        switch self {
        case .claude: return ClaudeProvider()
        }
    }
}
