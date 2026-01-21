import SwiftUI
import AppKit
import SwiftData

struct RepositoryPathsSection: View {
    @Query private var repoLocalPaths: [RepositoryLocalPath]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet = false

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository Paths")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Configure local repository paths for fast diff fetching")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if repoLocalPaths.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 8) {
                    ForEach(repoLocalPaths) { repoPath in
                        RepositoryPathRow(
                            repoPath: repoPath,
                            onUpdate: { newPath in
                                repoPath.localPath = newPath
                                try? modelContext.save()
                            },
                            onDelete: {
                                modelContext.delete(repoPath)
                                try? modelContext.save()
                            }
                        )
                    }
                }

                Button(action: { showAddSheet = true }) {
                    Label("Add Repository Path", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRepositoryPathSheet()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No repository paths configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Add your local repository paths to enable fast diff fetching")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showAddSheet = true }) {
                Label("Add Repository Path", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct RepositoryPathRow: View {
    let repoPath: RepositoryLocalPath
    var onUpdate: (String) -> Void
    var onDelete: () -> Void

    @State private var localPath: String
    @State private var showPicker = false
    @State private var isValid: Bool = true

    init(repoPath: RepositoryLocalPath, onUpdate: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.repoPath = repoPath
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _localPath = State(initialValue: repoPath.localPath)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isValid ? "folder.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isValid ? .blue : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(repoPath.nameWithOwner)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                if !localPath.isEmpty {
                    HStack(spacing: 4) {
                        Text(localPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !isValid {
                            Text("Not a git repository")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Browse") {
                    showNativeFolderPicker()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isValid ? Color.secondary.opacity(0.2) : Color.orange.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            localPath = repoPath.localPath
            isValid = isValidGitRepository(localPath)
        }
        .onChange(of: localPath) { _, newPath in
            isValid = isValidGitRepository(newPath)
            onUpdate(newPath)
        }
    }

    private func isValidGitRepository(_ path: String) -> Bool {
        guard !path.isEmpty else { return true }
        let gitDir = URL(fileURLWithPath: path)
            .appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    private func showNativeFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: localPath)

        if panel.runModal() == .OK, let url = panel.directoryURL {
            if isValidGitRepository(url.path) {
                localPath = url.path
                onUpdate(localPath)
            } else {
                let alert = NSAlert()
                alert.messageText = "Not a git repository"
                alert.informativeText = "The selected folder is not a git repository. Please select the root directory of a git repository (a folder containing a .git folder)."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

struct AddRepositoryPathSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var repoLocalPaths: [RepositoryLocalPath]

    @State private var selectedRepo = ""
    @State private var localPath = ""
    @State private var showFolderPicker = false
    @State private var availableRepos: [String] = []

    private func isValidGitRepository(_ path: String) -> Bool {
        guard !path.isEmpty else { return true }
        let gitDir = URL(fileURLWithPath: path)
            .appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Repository Path")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if availableRepos.isEmpty {
                    Picker("", selection: $selectedRepo) {
                        Text("Loading repositories...")
                            .tag("")
                    }
                    .pickerStyle(.menu)
                    .disabled(true)
                    .task {
                        await loadRepos()
                    }
                } else {
                    Picker("", selection: $selectedRepo) {
                        Text("Select repository...")
                            .tag("")
                        ForEach(availableRepos, id: \.self) { repo in
                            Text(repo)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("/path/to/repository", text: $localPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        showNativeFolderPicker()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    if !selectedRepo.isEmpty && !localPath.isEmpty {
                        guard isValidGitRepository(localPath) else {
                            let alert = NSAlert()
                            alert.messageText = "Not a git repository"
                            alert.informativeText = "The path '\(localPath)' is not a git repository. Please select a folder that contains a .git directory."
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            return
                        }

                        let newPath = RepositoryLocalPath(
                            nameWithOwner: selectedRepo,
                            localPath: localPath
                        )
                        modelContext.insert(newPath)
                        try? modelContext.save()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRepo.isEmpty || localPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
    }

    private func loadRepos() async {
        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            let existingIds = Set(repoLocalPaths.map { $0.id })
            availableRepos = repos.filter { !existingIds.contains($0) }
        } catch {
            print("[RepositoryPathsSection] Failed to load repos: \(error)")
        }
    }

    private func showNativeFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: localPath)

        if panel.runModal() == .OK, let url = panel.directoryURL {
            if isValidGitRepository(url.path) {
                localPath = url.path
            } else {
                let alert = NSAlert()
                alert.messageText = "Not a git repository"
                alert.informativeText = "The selected folder is not a git repository. Please select the root directory of a git repository (a folder containing a .git folder)."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
