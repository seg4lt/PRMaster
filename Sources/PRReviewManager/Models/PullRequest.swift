import Foundation

struct PullRequest: Codable, Identifiable {
    var id: String { url }
    let number: Int
    let title: String
    let url: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let author: Author?
    let repository: Repository
}
