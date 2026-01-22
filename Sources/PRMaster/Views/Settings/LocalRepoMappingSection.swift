import SwiftUI
import AppKit

struct LocalRepoMappingSection: View {
    @ObservedObject var repoManager: RepoManager
    @StateObject private var mappingService = LocalRepoMappingService.shared

    @State private var selectedRepo: String? = nil
    @State private var isValidating = false
    @State private var validationError: String?

    var unmappedRepos: [String] {
        repoManager.filteredRepos.filter { repo in
            !mappingService.mappings.contains(where: { $0.repositoryName == repo })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Repository Mapping")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Map GitHub repositories to local clones for faster AI Summary generation (5-10x speedup)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if repoManager.isLoadingRepos {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading repositories...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if repoManager.availableRepos.isEmpty {
                Text("No repositories available. Make sure you're authenticated with GitHub.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            } else {
                // Always show the search/picker section when repos are available
                addMappingSection

                // Show status message if all repos are mapped
                if unmappedRepos.isEmpty && !repoManager.repoSearchText.isEmpty {
                    Text("No unmapped repositories match your search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else if mappingService.mappings.count == repoManager.availableRepos.count {
                    Text("All repositories are mapped!")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.vertical, 4)
                }
            }

            if !mappingService.mappings.isEmpty {
                mappingsList
            } else if !repoManager.isLoadingRepos && !repoManager.availableRepos.isEmpty {
                emptyStateView
            }

            if let error = validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var addMappingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if unmappedRepos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        TextField("Search repos...", text: $repoManager.repoSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                    }
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    ScrollView {
                        VStack {
                            Text(repoManager.repoSearchText.isEmpty
                                ? "Search for a repository to map"
                                : "No unmapped repositories found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } else {
                RepoListPicker(
                    availableRepos: unmappedRepos,
                    selectedRepos: .constant([]),  // Not used in single-select
                    searchText: $repoManager.repoSearchText,
                    singleSelection: $selectedRepo,
                    showSelectAll: false,
                    height: 150
                )
            }

            HStack(spacing: 8) {
                Button("Browse for Local Folder...") {
                    browseForLocalRepo()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedRepo == nil || isValidating)

                if isValidating {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            Text("Select a repository above, then browse to its local clone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        Text("No local repositories mapped yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private var mappingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(mappingService.mappings) { mapping in
                mappingRow(mapping)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func mappingRow(_ mapping: LocalRepoMapping) -> some View {
        HStack(spacing: 8) {
            validationIndicator(for: mapping)

            Text(mapping.repositoryName)
                .font(.caption)
                .frame(width: 180, alignment: .leading)

            Text(truncatedPath(mapping.localPath))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                mappingService.removeMapping(id: mapping.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove mapping")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func validationIndicator(for mapping: LocalRepoMapping) -> some View {
        Button(action: {
            Task {
                await mappingService.revalidateMapping(id: mapping.id)
            }
        }) {
            if FileManager.default.fileExists(atPath: mapping.localPath + "/.git") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("Valid repository - Click to revalidate")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .help("Invalid repository path - Click to revalidate")
            }
        }
        .buttonStyle(.plain)
    }

    private func truncatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func browseForLocalRepo() {
        guard let repo = selectedRepo else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select local git repository for \(repo)"
        panel.prompt = "Select"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let path = url.path

            Task {
                isValidating = true
                validationError = nil

                let isValid = await mappingService.validatePath(at: path)

                if isValid {
                    let success = await mappingService.addMapping(
                        repositoryName: repo,
                        localPath: path
                    )

                    if success {
                        selectedRepo = nil
                        validationError = nil
                        repoManager.repoSearchText = ""
                    } else {
                        validationError = "Failed to add mapping"
                    }
                } else {
                    validationError = "Selected directory is not a valid git repository"
                }

                isValidating = false
            }
        }
    }
}
