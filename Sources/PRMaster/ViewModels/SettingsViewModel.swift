import Foundation
import SwiftUI
import ServiceManagement

/// ViewModel for settings management
@MainActor
class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()

    // GitHub CLI Status
    enum GHStatus {
        case checking
        case authenticated(user: String)
        case notAuthenticated
        case notInstalled
    }

    @Published var ghStatus: GHStatus = .checking
    @Published var aiProviderStatus: AIProviderStatus = .notInstalled(message: "Checking...")
    @Published var copilotModels: [String] = []
    @Published var isLoadingModels = false
    @Published var isRefreshingRepoCache = false
    @Published var repoCacheError: String?
    
    private let repoManager = RepoManager()

    // MARK: - GitHub Status

    func checkGHStatus() async {
        ghStatus = .checking

        let installed = await GitHubService.shared.checkGHInstalled()
        if !installed {
            ghStatus = .notInstalled
            return
        }

        let authenticated = await GitHubService.shared.checkGHAuthenticated()
        if !authenticated {
            ghStatus = .notAuthenticated
            return
        }

        if let user = try? await GitHubService.shared.getCurrentUser() {
            ghStatus = .authenticated(user: user)
        } else {
            ghStatus = .notAuthenticated
        }
    }

    // MARK: - AI Provider Status

    func checkAIProviderStatus(for providerRawValue: String) async {
        guard let providerType = AIProviderType(rawValue: providerRawValue) else { return }
        let provider = providerType.createProvider()
        aiProviderStatus = await provider.checkAvailability()
    }

    func loadModelsIfNeeded(for providerRawValue: String) async {
        guard let providerType = AIProviderType(rawValue: providerRawValue),
              providerType == .copilot else {
            return
        }

        isLoadingModels = true
        copilotModels = await CopilotProvider.fetchAvailableModels()
        isLoadingModels = false
    }

    func providerDisplayName(for providerRawValue: String) -> String {
        AIProviderType(rawValue: providerRawValue)?.displayName ?? "Unknown"
    }

    // MARK: - Terminal Commands

    func openTerminalWithCommand(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }

    // MARK: - Repository Cache

    func refreshRepoCache() async {
        isRefreshingRepoCache = true
        repoCacheError = nil
        
        await repoManager.reloadRepos()
        
        if let error = repoManager.error {
            repoCacheError = error
        }
        
        isRefreshingRepoCache = false
    }

    func getRepoCacheAge() -> String? {
        guard let cacheDate = UserDefaults.standard.object(forKey: "cachedReposDate") as? Date else {
            return nil
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: cacheDate, relativeTo: Date())
    }

    var cachedRepoCount: Int {
        guard let data = UserDefaults.standard.data(forKey: "cachedRepos"),
              let repos = try? JSONDecoder().decode([String].self, from: data) else {
            return 0
        }
        return repos.count
    }
}
