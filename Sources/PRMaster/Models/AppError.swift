import Foundation

enum AppError: Error, Identifiable, Equatable {
    case networkError(String)
    case authenticationError(String)
    case ghCLINotFound
    case ghCLINotAuthenticated
    case apiRateLimited
    case unknown(String)

    var id: String {
        switch self {
        case .networkError(let msg): return "network-\(msg)"
        case .authenticationError(let msg): return "auth-\(msg)"
        case .ghCLINotFound: return "gh-not-found"
        case .ghCLINotAuthenticated: return "gh-not-auth"
        case .apiRateLimited: return "rate-limited"
        case .unknown(let msg): return "unknown-\(msg)"
        }
    }

    var message: String {
        switch self {
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .authenticationError(let msg):
            return "Authentication failed: \(msg)"
        case .ghCLINotFound:
            return "GitHub CLI (gh) is not installed"
        case .ghCLINotAuthenticated:
            return "GitHub CLI is not authenticated"
        case .apiRateLimited:
            return "GitHub API rate limit exceeded"
        case .unknown(let msg):
            return msg
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .apiRateLimited, .unknown:
            return true
        case .authenticationError, .ghCLINotFound, .ghCLINotAuthenticated:
            return false
        }
    }

    var actionLabel: String? {
        switch self {
        case .ghCLINotFound:
            return "Install gh"
        case .ghCLINotAuthenticated:
            return "Run gh auth login"
        case .apiRateLimited:
            return "Wait and retry"
        default:
            return nil
        }
    }

    static func from(_ error: Error) -> AppError {
        if let shellError = error as? ShellError {
            return from(shellError: shellError)
        }
        return .unknown(error.localizedDescription)
    }

    static func from(shellError: ShellError) -> AppError {
        switch shellError {
        case .commandNotFound:
            return .ghCLINotFound
        case .commandFailed(let output, _):
            if output.contains("auth") || output.contains("401") || output.contains("403") {
                if output.contains("rate limit") {
                    return .apiRateLimited
                }
                return .authenticationError(output.prefix(100).description)
            }
            if output.contains("rate limit") || output.contains("429") {
                return .apiRateLimited
            }
            if output.contains("Could not resolve host") || output.contains("Network") {
                return .networkError(output.prefix(100).description)
            }
            return .networkError(output.prefix(100).description)
        case .timeout(let seconds):
            return .networkError("Request timed out after \(Int(seconds)) seconds")
        }
    }
}
