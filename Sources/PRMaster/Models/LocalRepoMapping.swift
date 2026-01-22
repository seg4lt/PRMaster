import Foundation

struct LocalRepoMapping: Codable, Identifiable {
    let id: UUID
    let repositoryName: String  // "owner/repo" format
    let localPath: String
    let lastValidated: Date

    init(id: UUID = UUID(), repositoryName: String, localPath: String, lastValidated: Date = Date()) {
        self.id = id
        self.repositoryName = repositoryName
        self.localPath = localPath
        self.lastValidated = lastValidated
    }
}

@MainActor
class LocalRepoMappingService: ObservableObject {
    static let shared = LocalRepoMappingService()

    @Published private(set) var mappings: [LocalRepoMapping] = []

    private let userDefaultsKey = "localRepoMappings"

    private init() {
        loadMappings()
    }

    // MARK: - Public Methods

    func getMapping(for repositoryName: String) -> LocalRepoMapping? {
        return mappings.first { $0.repositoryName == repositoryName }
    }

    func addMapping(repositoryName: String, localPath: String) async -> Bool {
        let isValid = await LocalGitService.shared.validateRepository(path: localPath)
        guard isValid else {
            return false
        }

        mappings.removeAll { $0.repositoryName == repositoryName }

        let mapping = LocalRepoMapping(
            repositoryName: repositoryName,
            localPath: localPath,
            lastValidated: Date()
        )
        mappings.append(mapping)

        saveMappings()
        return true
    }

    func removeMapping(id: UUID) {
        mappings.removeAll { $0.id == id }
        saveMappings()
    }

    func removeMapping(for repositoryName: String) {
        mappings.removeAll { $0.repositoryName == repositoryName }
        saveMappings()
    }

    func validatePath(at path: String) async -> Bool {
        return await LocalGitService.shared.validateRepository(path: path)
    }

    func revalidateMapping(id: UUID) async {
        guard let index = mappings.firstIndex(where: { $0.id == id }) else {
            return
        }

        let mapping = mappings[index]
        let isValid = await LocalGitService.shared.validateRepository(path: mapping.localPath)

        if isValid {
            mappings[index] = LocalRepoMapping(
                id: mapping.id,
                repositoryName: mapping.repositoryName,
                localPath: mapping.localPath,
                lastValidated: Date()
            )
            saveMappings()
        }
    }

    // MARK: - Persistence

    private func loadMappings() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            mappings = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            mappings = try decoder.decode([LocalRepoMapping].self, from: data)
        } catch {
            print("Failed to load repository mappings: \(error)")
            mappings = []
        }
    }

    private func saveMappings() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(mappings)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to save repository mappings: \(error)")
        }
    }
}
