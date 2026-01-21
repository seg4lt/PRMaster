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

import Foundation
import SwiftData

@Model
final class RepositoryLocalPath {
    var id: String
    var localPath: String

    init(nameWithOwner: String, localPath: String) {
        self.id = nameWithOwner
        self.localPath = localPath
    }

    var nameWithOwner: String { id }

    var shortName: String {
        let parts = id.split(separator: "/")
        if parts.count == 2 {
            return String(parts[1])
        }
        return id
    }
}
