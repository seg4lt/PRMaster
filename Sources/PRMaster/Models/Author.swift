import Foundation

struct Author: Codable, Identifiable, Hashable {
    let id: String
    let login: String
    let isBot: Bool
    let type: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case isBot = "is_bot"
        case type
        case url
    }

    var displayName: String {
        "@\(login)"
    }
}
