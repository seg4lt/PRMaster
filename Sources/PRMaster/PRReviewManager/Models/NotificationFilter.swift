import Foundation
import SwiftData

enum NotificationAction: String, Codable, CaseIterable {
    case soundAndBanner = "soundAndBanner"
    case silentBanner = "silentBanner"
    case badgeOnly = "badgeOnly"
    case mute = "mute"

    var displayName: String {
        switch self {
        case .soundAndBanner: return "Sound + Banner"
        case .silentBanner: return "Silent Banner"
        case .badgeOnly: return "Badge Only"
        case .mute: return "Mute"
        }
    }

    var icon: String {
        switch self {
        case .soundAndBanner: return "bell.badge.fill"
        case .silentBanner: return "bell.fill"
        case .badgeOnly: return "app.badge"
        case .mute: return "bell.slash.fill"
        }
    }
}

@Model
final class NotificationFilter {
    var id: UUID
    var name: String
    var authors: [String]
    var repositories: [String]
    var titlePattern: String?
    var action: String
    var isEnabled: Bool
    var createdAt: Date

    init(
        name: String,
        authors: [String] = [],
        repositories: [String] = [],
        titlePattern: String? = nil,
        action: NotificationAction = .soundAndBanner,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.authors = authors
        self.repositories = repositories
        self.titlePattern = titlePattern
        self.action = action.rawValue
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }

    var notificationAction: NotificationAction {
        get { NotificationAction(rawValue: action) ?? .soundAndBanner }
        set { action = newValue.rawValue }
    }

    func matches(pr: PullRequest) -> Bool {
        if !isEnabled { return false }

        if !authors.isEmpty {
            guard let authorLogin = pr.author?.login,
                  authors.contains(authorLogin) else {
                return false
            }
        }

        if !repositories.isEmpty {
            guard repositories.contains(pr.repository.nameWithOwner) ||
                  repositories.contains(pr.repository.shortName) else {
                return false
            }
        }

        if let pattern = titlePattern, !pattern.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(pr.title.startIndex..., in: pr.title)
            guard regex.firstMatch(in: pr.title, options: [], range: range) != nil else {
                return false
            }
        }

        return true
    }
}
