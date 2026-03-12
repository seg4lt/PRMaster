import Foundation

enum ConversationKind {
    case reviewThread
    case mentionComment

    var badgeLabel: String {
        switch self {
        case .reviewThread: return "Thread"
        case .mentionComment: return "Mention"
        }
    }
}

struct ConversationMessage: Identifiable {
    let id: String
    let authorLogin: String?
    let body: String
    let createdAt: Date
    let url: String

    var authorDisplayName: String {
        if let authorLogin, !authorLogin.isEmpty {
            return "@\(authorLogin)"
        }
        return "Unknown"
    }
}

struct ConversationItem: Identifiable {
    let id: String
    let prID: String
    let prTitle: String
    let prNumber: Int
    let repoNameWithOwner: String
    let prURL: String
    let kind: ConversationKind
    let filePath: String?
    let lineNumber: Int?
    let latestActivityAt: Date
    let exactURL: String
    let messages: [ConversationMessage]

    var previewText: String {
        let source = messages.last(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.body ?? ""
        let collapsed = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "No message preview" }
        if collapsed.count <= 90 {
            return collapsed
        }
        return String(collapsed.prefix(87)) + "..."
    }

    var latestAuthorLogin: String? {
        messages.last?.authorLogin
    }

    var locationText: String? {
        guard let filePath else { return nil }
        if let lineNumber {
            return "\(filePath):\(lineNumber)"
        }
        return filePath
    }
}

struct ConversationGroup: Identifiable {
    let prID: String
    let prTitle: String
    let prNumber: Int
    let repoNameWithOwner: String
    let prURL: String
    let conversations: [ConversationItem]

    var id: String { prID }

    var latestActivityAt: Date {
        conversations.map(\.latestActivityAt).max() ?? .distantPast
    }
}

