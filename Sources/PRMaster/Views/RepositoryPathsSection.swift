import SwiftUI

struct RepositoryPathsSection: View {
    var repoLocalPaths: [RepositoryLocalPath]
    var onSave: ([RepositoryLocalPath]) -> Void

    @State private var editingPaths: [RepositoryLocalPath] = []
    @State private var showAddSheet = false

    init(repoLocalPaths: [RepositoryLocalPath], onSave: @escaping ([RepositoryLocalPath]) -> Void) {
        self.repoLocalPaths = repoLocalPaths
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository Paths")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Configure local repository paths for fast diff fetching")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if editingPaths.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(editingPaths.enumerated()), id: \.element.id) { index, repoPath in
                        RepositoryPathRow(
                            repoPath: repoPath,
                            onUpdate: { newPath in
                                var updatedPaths = editingPaths
                                updatedPaths[index] = RepositoryLocalPath(nameWithOwner: repoPath.id, localPath: newPath)
                                onSave(updatedPaths)
                            },
                            onDelete: {
                                var updatedPaths = editingPaths
                                updatedPaths.remove(at: index)
                                onSave(updatedPaths)
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
            AddRepositoryPathSheet(
                existingPaths: editingPaths,
                onSave: { newPath in
                    editingPaths.append(newPath)
                    onSave(editingPaths)
                }
            )
        }
        .onAppear {
            editingPaths = repoLocalPaths
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

    init(repoPath: RepositoryLocalPath, onUpdate: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.repoPath = repoPath
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _localPath = State(initialValue: repoPath.localPath)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(repoPath.nameWithOwner)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                if !localPath.isEmpty {
                    Text(localPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            localPath = repoPath.localPath
        }
    }

    private func showNativeFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: localPath)

        if panel.runModal() == .OK, let url = panel.directoryURL {
            localPath = url.path
            onUpdate(localPath)
        }
    }
}

struct AddRepositoryPathSheet: View {
    let existingPaths: [RepositoryLocalPath]
    var onSave: (RepositoryLocalPath) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRepo = ""
    @State private var localPath = ""
    @State private var showFolderPicker = false
    @State private var availableRepos: [String] = []

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
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: localPath)

                        if panel.runModal() == .OK, let url = panel.directoryURL {
                            localPath = url.path
                        }
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
                        let newPath = RepositoryLocalPath(
                            nameWithOwner: selectedRepo,
                            localPath: localPath
                        )
                        onSave(newPath)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRepo.isEmpty || localPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                localPath = url.path
            }
        }
    }

    private func loadRepos() async {
        do {
            let repos = try await GitHubService.shared.fetchAccessibleRepos()
            let existingIds = Set(existingPaths.map { $0.id })
            availableRepos = repos.filter { !existingIds.contains($0) }
        } catch {
            print("[RepositoryPathsSection] Failed to load repos: \(error)")
        }
    }
}
