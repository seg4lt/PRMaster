import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @AppStorage("pollingInterval") private var pollingInterval: Double = 300
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("globalShortcutEnabled") private var globalShortcutEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("onlyFilterNotifications") private var onlyFilterNotifications: Bool = false
    @AppStorage("myPRNotificationsEnabled") private var myPRNotificationsEnabled: Bool = true
    @AppStorage("badgeSource") private var badgeSource: String = "toReview"
    @AppStorage("badgeFilterId") private var badgeFilterId: String = ""
    @AppStorage("badgeConfig") private var badgeConfigJSON: String = "[]"  // JSON array of BadgeSourceConfig
    @AppStorage("aiProvider") private var selectedProvider: String = AIProviderType.claude.rawValue
    @Query private var savedFilters: [NotificationFilter]
    @State private var ghStatus: GHStatus = .checking
    @State private var aiProviderStatus: AIProviderStatus = .notInstalled(message: "Checking...")

    private var badgeConfigs: [BadgeSourceConfig] {
        (try? JSONDecoder().decode([BadgeSourceConfig].self, from: Data(badgeConfigJSON.utf8))) ?? []
    }

    private func saveBadgeConfigs(_ configs: [BadgeSourceConfig]) {
        if let data = try? JSONEncoder().encode(configs),
           let json = String(data: data, encoding: .utf8) {
            badgeConfigJSON = json
        }
    }

    private func configFor(_ source: String) -> BadgeSourceConfig? {
        badgeConfigs.first { $0.source == source }
    }

    private func toggleSource(_ source: String) {
        var configs = badgeConfigs
        if let index = configs.firstIndex(where: { $0.source == source }) {
            configs.remove(at: index)
        } else {
            configs.append(BadgeSourceConfig(source: source, prefix: "", suffix: ""))
        }
        saveBadgeConfigs(configs)
    }

    private func updateConfig(_ source: String, prefix: String? = nil, suffix: String? = nil) {
        var configs = badgeConfigs
        if let index = configs.firstIndex(where: { $0.source == source }) {
            if let prefix = prefix { configs[index].prefix = prefix }
            if let suffix = suffix { configs[index].suffix = suffix }
            saveBadgeConfigs(configs)
        }
    }

    enum GHStatus {
        case checking
        case authenticated(user: String)
        case notAuthenticated
        case notInstalled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.headline)

                Divider()

                ghStatusSection

                Divider()

                pollingSection

                Divider()

                startupSection

                Divider()

                shortcutSection

                Divider()

                notificationSection

                Divider()

                badgeSection

                Divider()

                aiProviderSection

                Divider()

                Button("Quit PRMaster") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .task {
            await checkGHStatus()
            await checkAIProviderStatus()
        }
        .onChange(of: selectedProvider) { _, _ in
            Task {
                await checkAIProviderStatus()
            }
        }
    }

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Provider")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProviderType.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)

            HStack(spacing: 6) {
                switch aiProviderStatus {
                case .available:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(currentProviderName) ready")
                case .notInstalled(let msg):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                    Button("Install Claude Code") {
                        if let url = URL(string: "https://claude.ai/code") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .notAuthenticated(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(msg)
                    Button("Run claude login") {
                        openTerminalWithCommand("claude login")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .error(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                }
            }
            .font(.caption)

            Text("Used for AI Weekly Summary feature")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentProviderName: String {
        AIProviderType(rawValue: selectedProvider)?.displayName ?? "Unknown"
    }

    private func checkAIProviderStatus() async {
        guard let providerType = AIProviderType(rawValue: selectedProvider) else { return }
        let provider = providerType.createProvider()
        aiProviderStatus = await provider.checkAvailability()
    }

    private var ghStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub CLI Status")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                switch ghStatus {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking...")
                        .foregroundStyle(.secondary)
                case .authenticated(let user):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Authenticated as @\(user)")
                case .notAuthenticated:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("Not authenticated")
                    Button("Run gh auth login") {
                        openTerminalWithCommand("gh auth login")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .notInstalled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("gh CLI not installed")
                    Button("Install Homebrew gh") {
                        openTerminalWithCommand("brew install gh")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.caption)
        }
    }

    private var pollingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh Interval")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $pollingInterval) {
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
                Text("10 minutes").tag(600.0)
                Text("15 minutes").tag(900.0)
                Text("30 minutes").tag(1800.0)
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Text("How often to check for new PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Startup")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }

            Text("Automatically start when you log in")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global Shortcut")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Enable ⌥⇧⌘P to open window", isOn: $globalShortcutEnabled)

            Text("Press Option+Shift+Command+P from anywhere to open the expanded window. Requires Accessibility permissions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Enable notifications", isOn: $notificationsEnabled)

            if notificationsEnabled {
                Toggle("Only notify for filter matches", isOn: $onlyFilterNotifications)
                    .padding(.leading, 16)

                if onlyFilterNotifications {
                    Text("Notifications only sent when a PR matches an enabled filter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                } else {
                    Text("Notifications sent for all new/updated PRs in To Review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Toggle("Notify on my PR activity", isOn: $myPRNotificationsEnabled)

            Text("Get notified when someone reviews or comments on your PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu Bar Badge")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Select counts to show (with optional prefix/suffix):")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Built-in sources as checkboxes with prefix/suffix
            ForEach(["toReview", "reviewed", "myPRs"], id: \.self) { source in
                badgeSourceRow(
                    source: source,
                    label: BadgeSource(rawValue: source)?.displayName ?? source
                )
            }

            // Saved filters
            if !savedFilters.filter({ $0.isEnabled }).isEmpty {
                Text("Saved filters:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(savedFilters.filter { $0.isEnabled }) { filter in
                    badgeSourceRow(
                        source: "filter:\(filter.id.uuidString)",
                        label: filter.name
                    )
                }
            }

            // Preview
            if !badgeConfigs.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                Text("Preview: \(badgePreview)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func badgeSourceRow(source: String, label: String) -> some View {
        let isSelected = configFor(source) != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(label)
                    .font(.caption)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSource(source)
            }

            if isSelected {
                HStack(spacing: 8) {
                    Text("Pre:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", text: Binding(
                        get: { configFor(source)?.prefix ?? "" },
                        set: { updateConfig(source, prefix: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)

                    Text("Suf:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", text: Binding(
                        get: { configFor(source)?.suffix ?? "" },
                        set: { updateConfig(source, suffix: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)
                }
                .padding(.leading, 20)
            }
        }
    }

    private var badgePreview: String {
        badgeConfigs.map { config in
            "\(config.prefix)#\(config.suffix)"
        }.joined(separator: " ")
    }

    private func checkGHStatus() async {
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

    private func openTerminalWithCommand(_ command: String) {
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

    private func setLaunchAtLogin(_ enabled: Bool) {
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
}
