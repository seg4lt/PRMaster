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
    @AppStorage("badgeConfig") private var badgeConfigJSON: String = "[]"
    @AppStorage("aiProvider") private var selectedProvider: String = AIProviderType.claude.rawValue
    @AppStorage("aiModel") private var selectedModel: String = AIProviderType.claude.defaultModel
    @AppStorage("tokenRatio") private var tokenRatio: Int = 2
    @AppStorage("repositoryLocalPaths") private var repositoryLocalPathsJSON: String = "[]"
    @Query private var savedFilters: [NotificationFilter]

    @StateObject private var viewModel = SettingsViewModel.shared

    private var badgeConfigs: [BadgeSourceConfig] {
        (try? JSONDecoder().decode([BadgeSourceConfig].self, from: Data(badgeConfigJSON.utf8))) ?? []
    }

    private var repoLocalPaths: [RepositoryLocalPath] {
        (try? JSONDecoder().decode([RepositoryLocalPath].self, from: Data(repositoryLocalPathsJSON.utf8))) ?? []
    }

    private func saveBadgeConfigs(_ configs: [BadgeSourceConfig]) {
        if let data = try? JSONEncoder().encode(configs),
           let json = String(data: data, encoding: .utf8) {
            badgeConfigJSON = json
        }
    }

    private func saveRepoPaths(_ paths: [RepositoryLocalPath]) {
        if let data = try? JSONEncoder().encode(paths),
           let json = String(data: data, encoding: .utf8) {
            repositoryLocalPathsJSON = json
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.headline)

                Divider()

                GHStatusSection(viewModel: viewModel)

                Divider()

                PollingSection(pollingInterval: $pollingInterval)

                Divider()

                startupSection

                Divider()

                shortcutSection

                Divider()

                NotificationSection(
                    notificationsEnabled: $notificationsEnabled,
                    onlyFilterNotifications: $onlyFilterNotifications,
                    myPRNotificationsEnabled: $myPRNotificationsEnabled
                )

                Divider()

                badgeSection

                Divider()

                RepositoryPathsSection(
                    repoLocalPaths: repoLocalPaths,
                    onSave: saveRepoPaths
                )

                Divider()

                AIProviderSection(
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    tokenRatio: $tokenRatio,
                    viewModel: viewModel
                )

                Divider()

                Button("Quit PRMaster") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .task {
            await viewModel.checkGHStatus()
            await viewModel.checkAIProviderStatus(for: selectedProvider)
            await viewModel.loadModelsIfNeeded(for: selectedProvider)
        }
        .onChange(of: selectedProvider) { _, newValue in
            Task {
                await viewModel.checkAIProviderStatus(for: newValue)
                if let providerType = AIProviderType(rawValue: newValue) {
                    selectedModel = providerType.defaultModel
                }
                await viewModel.loadModelsIfNeeded(for: newValue)
            }
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Startup")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    viewModel.setLaunchAtLogin(newValue)
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

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu Bar Badge")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Select counts to show (with optional prefix/suffix):")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(["toReview", "reviewed", "myPRs"], id: \.self) { source in
                badgeSourceRow(
                    source: source,
                    label: BadgeSource(rawValue: source)?.displayName ?? source
                )
            }

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
}
