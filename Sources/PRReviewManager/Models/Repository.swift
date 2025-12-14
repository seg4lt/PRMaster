import Foundation

struct Repository: Codable, Identifiable, Hashable {
    let name: String
    let nameWithOwner: String

    var id: String { nameWithOwner }

    var shortName: String {
        let parts = nameWithOwner.split(separator: "/")
        if parts.count == 2 {
            return String(parts[1])
        }
        return name
    }

    var owner: String {
        let parts = nameWithOwner.split(separator: "/")
        if parts.count == 2 {
            return String(parts[0])
        }
        return ""
    }
}
