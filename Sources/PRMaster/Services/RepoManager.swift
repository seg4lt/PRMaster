import Foundation

/// Manages repository loading and caching for AI Summary feature
@MainActor
class RepoManager: ObservableObject {
    @Published var availableRepos: [String] = []
    @Published var selectedRepos: Set<String> = [] {
        didSet {
            saveSelectedRepos()
        }
    }
    @Published var isLoadingRepos = false
    @Published var repoSearchText: String = ""
    @Published var error: String?

    private var hasLoadedRepos = false

    var filteredRepos: [String] {
        let repos = repoSearchText.isEmpty
            ? availableRepos
            : availableRepos.filter { $0.localizedCaseInsensitiveContains(repoSearchText) }

        // Selected repos first, then alphabetically within each group
        return repos.sorted { a, b in
            let aSelected = selectedRepos.contains(a)
            let bSelected = selectedRepos.contains(b)
            if aSelected != bSelected {
                return aSelected
            }
            return a < b
        }
    }

    init() {
        loadSelectedRepos()
    }

    // MARK: - Loading

    /// Load available repos (cached for 1 week)
    func loadReposIfNeeded() async {
        guard !hasLoadedRepos else { return }
        hasLoadedRepos = true

        // Try to load from cache first
        if let cached = loadCachedRepos(), !isCacheExpired() {
            availableRepos = cached
            return
        }

        // Fetch from API
        isLoadingRepos = true
        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            availableRepos = repos.sorted()
            saveCachedRepos(availableRepos)
        } catch {
            // If fetch fails but we have stale cache, use it
            if let cached = loadCachedRepos() {
                availableRepos = cached
            } else {
                self.error = "Failed to load repos: \(error.localizedDescription)"
            }
        }
        isLoadingRepos = false
    }

    /// Force reload repos from API
    func reloadRepos() async {
        hasLoadedRepos = false
        isLoadingRepos = true

        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            availableRepos = repos.sorted()
            saveCachedRepos(availableRepos)
        } catch {
            self.error = "Failed to reload repos: \(error.localizedDescription)"
        }

        isLoadingRepos = false
        hasLoadedRepos = true
    }

    // MARK: - Selection

    func toggleRepo(_ repo: String) {
        if selectedRepos.contains(repo) {
            selectedRepos.remove(repo)
        } else {
            selectedRepos.insert(repo)
        }
        saveSelectedRepos()
    }

    func selectAllFilteredRepos() {
        for repo in filteredRepos {
            selectedRepos.insert(repo)
        }
        saveSelectedRepos()
    }

    func deselectAllRepos() {
        selectedRepos.removeAll()
        saveSelectedRepos()
    }

    // MARK: - Persistence

    private func loadSelectedRepos() {
        if let data = UserDefaults.standard.data(forKey: "selectedRepos"),
           let repos = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedRepos = repos
        }
    }

    func saveSelectedRepos() {
        if let data = try? JSONEncoder().encode(selectedRepos) {
            UserDefaults.standard.set(data, forKey: "selectedRepos")
        }
    }

    private func loadCachedRepos() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: "cachedRepos"),
              let repos = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return repos
    }

    private func saveCachedRepos(_ repos: [String]) {
        if let data = try? JSONEncoder().encode(repos) {
            UserDefaults.standard.set(data, forKey: "cachedRepos")
            UserDefaults.standard.set(Date(), forKey: "cachedReposDate")
        }
    }

    private func isCacheExpired() -> Bool {
        guard let cacheDate = UserDefaults.standard.object(forKey: "cachedReposDate") as? Date else {
            return true
        }
        let oneWeek: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(cacheDate) > oneWeek
    }
}
