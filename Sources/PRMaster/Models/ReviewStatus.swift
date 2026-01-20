import Foundation
import SwiftUI

enum ReviewDecision: String, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = ReviewDecision(rawValue: rawValue ?? "") ?? .unknown
    }

    var displayText: String {
        switch self {
        case .approved: return "Approved"
        case .changesRequested: return "Changes Requested"
        case .reviewRequired: return "Needs Review"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .reviewRequired: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .changesRequested: return .red
        case .reviewRequired: return .orange
        case .unknown: return .gray
        }
    }
}

enum ReviewState: String, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case pending = "PENDING"
    case dismissed = "DISMISSED"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = ReviewState(rawValue: rawValue ?? "") ?? .unknown
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .commented: return "bubble.left.fill"
        case .pending: return "clock"
        case .dismissed: return "minus.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .changesRequested: return .red
        case .commented: return .blue
        case .pending: return .orange
        case .dismissed: return .gray
        case .unknown: return .gray
        }
    }
}

struct Review: Codable, Identifiable {
    let author: ReviewAuthor?
    let state: ReviewState

    var id: String {
        "\(author?.login ?? "unknown")-\(state.rawValue)"
    }
}

struct ReviewAuthor: Codable {
    let login: String
}

struct PullRequestReview: Codable {
    let id: Int
    let user: ReviewAuthor
    let body: String?
    let state: String
    let html_url: String?
    let submitted_at: Date?
    let pull_request_url: String?
    let commit_id: String
}
