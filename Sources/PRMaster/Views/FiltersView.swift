import SwiftUI
import SwiftData
import UserNotifications
import AppKit

struct FiltersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var filters: [NotificationFilter]
    @State private var isAddingFilter = false
    @State private var editingFilter: NotificationFilter?

    var body: some View {
        VStack(spacing: 0) {
            if isAddingFilter {
                FilterEditorView(
                    filter: nil,
                    onSave: { newFilter in
                        modelContext.insert(newFilter)
                        isAddingFilter = false
                    },
                    onCancel: {
                        isAddingFilter = false
                    }
                )
            } else if let filter = editingFilter {
                FilterEditorView(
                    filter: filter,
                    onSave: { _ in
                        editingFilter = nil
                    },
                    onCancel: {
                        editingFilter = nil
                    }
                )
            } else {
                filterListContent
            }
        }
    }

    private var filterListContent: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if filters.isEmpty {
                emptyView
            } else {
                filtersList
            }

            Divider()
            defaultBehaviorView
        }
    }

    private var headerView: some View {
        HStack {
            Text("Notification Filters")
                .font(.headline)
            Spacer()
            Button {
                isAddingFilter = true
            } label: {
                Label("New Filter", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No notification filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Create filters to customize how you're notified about PRs from specific authors or repositories")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                isAddingFilter = true
            } label: {
                Label("Create Your First Filter", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var filtersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filters) { filter in
                    FilterRowView(filter: filter) {
                        editingFilter = filter
                    } onDelete: {
                        modelContext.delete(filter)
                    } onTest: {
                        sendTestNotification(for: filter)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 300)
    }

    private func sendTestNotification(for filter: NotificationFilter) {
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

                guard granted else {
                    print("Notification permission denied")
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = "PRMaster - Test"
                content.subtitle = "Filter: \(filter.name)"

                var body = "This is a test notification"
                if !filter.authors.isEmpty {
                    body += "\nAuthors: \(filter.authors.map { "@\($0)" }.joined(separator: ", "))"
                }
                if !filter.repositories.isEmpty {
                    body += "\nRepos: \(filter.repositories.joined(separator: ", "))"
                }
                content.body = body

                switch filter.notificationAction {
                case .soundAndBanner:
                    content.sound = .default
                case .silentBanner:
                    content.sound = nil
                case .badgeOnly:
                    content.sound = nil
                    content.body = "Badge-only notifications don't show a banner"
                case .mute:
                    content.body = "This filter is muted - no notification would be shown"
                }

                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )

                try await center.add(request)
            } catch {
                print("Failed to send test notification: \(error)")
            }
        }
    }

    private var defaultBehaviorView: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Default: Notify for all new review requests")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct FilterRowView: View {
    let filter: NotificationFilter
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: filter.notificationAction.icon)
                    .foregroundColor(filter.isEnabled ? .accentColor : .secondary)
                Text(filter.name)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { filter.isEnabled },
                    set: { filter.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Button {
                    onTest()
                } label: {
                    Image(systemName: "bell.badge")
                }
                .buttonStyle(.borderless)
                .help("Test notification")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }

            if !filter.authors.isEmpty {
                HStack {
                    Text("Authors:")
                        .foregroundStyle(.secondary)
                    Text(filter.authors.map { "@\($0)" }.joined(separator: ", "))
                }
                .font(.caption)
            }

            if !filter.repositories.isEmpty {
                HStack {
                    Text("Repos:")
                        .foregroundStyle(.secondary)
                    Text(filter.repositories.joined(separator: ", "))
                }
                .font(.caption)
            }

            if !filter.filePatterns.isEmpty {
                HStack {
                    Text("Files:")
                        .foregroundStyle(.secondary)
                    Text(filter.filePatterns.joined(separator: ", "))
                }
                .font(.caption)
            }

            HStack {
                Text("Action:")
                    .foregroundStyle(.secondary)
                Text(filter.notificationAction.displayName)
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FilterEditorView: View {
    let filter: NotificationFilter?
    let onSave: (NotificationFilter) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var authorsText: String = ""
    @State private var reposText: String = ""
    @State private var titlePattern: String = ""
    @State private var filePatternsText: String = ""
    @State private var action: NotificationAction = .soundAndBanner

    init(filter: NotificationFilter?, onSave: @escaping (NotificationFilter) -> Void, onCancel: @escaping () -> Void) {
        self.filter = filter
        self.onSave = onSave
        self.onCancel = onCancel

        if let filter = filter {
            _name = State(initialValue: filter.name)
            _authorsText = State(initialValue: filter.authors.joined(separator: ", "))
            _reposText = State(initialValue: filter.repositories.joined(separator: ", "))
            _titlePattern = State(initialValue: filter.titlePattern ?? "")
            _filePatternsText = State(initialValue: filter.filePatterns.joined(separator: ", "))
            _action = State(initialValue: filter.notificationAction)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(filter == nil ? "New Filter" : "Edit Filter")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveFilter()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filter Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., Critical PRs, Team Updates", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authors (comma-separated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., john-doe, jane-smith", text: $authorsText)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty to match all authors")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repositories (comma-separated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., org/repo1, org/repo2", text: $reposText)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty to match all repos")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Patterns (comma-separated, wildcards supported)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., src/api/*, *.swift, tests/**/*", text: $filePatternsText)
                            .textFieldStyle(.roundedBorder)
                        Text("Use * for single directory, ** for any depth")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title Pattern (regex, optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., hotfix|urgent", text: $titlePattern)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notification Action")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(NotificationAction.allCases, id: \.self) { notifAction in
                            Button {
                                action = notifAction
                            } label: {
                                HStack {
                                    Image(systemName: notifAction.icon)
                                        .frame(width: 20)
                                    VStack(alignment: .leading) {
                                        Text(notifAction.displayName)
                                            .fontWeight(.medium)
                                        Text(actionDescription(notifAction))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if action == notifAction {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(8)
                                .background(action == notifAction ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func actionDescription(_ action: NotificationAction) -> String {
        switch action {
        case .soundAndBanner: return "Show notification with sound"
        case .silentBanner: return "Show notification without sound"
        case .badgeOnly: return "Only update badge count"
        case .mute: return "Don't notify for matching PRs"
        }
    }

    private func saveFilter() {
        let authors = authorsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "") }
            .filter { !$0.isEmpty }

        let repos = reposText
            .split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        let filePatterns = filePatternsText
            .split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        if let existingFilter = filter {
            existingFilter.name = name
            existingFilter.authors = authors
            existingFilter.repositories = repos
            existingFilter.titlePattern = titlePattern.isEmpty ? nil : titlePattern
            existingFilter.filePatterns = filePatterns
            existingFilter.notificationAction = action
            onSave(existingFilter)
        } else {
            let newFilter = NotificationFilter(
                name: name,
                authors: authors,
                repositories: repos,
                titlePattern: titlePattern.isEmpty ? nil : titlePattern,
                filePatterns: filePatterns,
                action: action
            )
            onSave(newFilter)
        }
    }
}
