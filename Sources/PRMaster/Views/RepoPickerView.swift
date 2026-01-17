import SwiftUI

struct RepoPickerView: View {
    @ObservedObject var viewModel: AISummaryViewModel
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Header button to expand/collapse
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)

                if viewModel.selectedRepos.isEmpty {
                    Text("Select repositories...")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.selectedRepos.count) selected")
                        .foregroundColor(.primary)
                }

                Spacer()

                if viewModel.isLoadingRepos {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            // Floating dropdown using overlay (doesn't affect layout)
            if isExpanded {
                dropdownContent
                    .offset(y: 36)
            }
        }
    }

    private var dropdownContent: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search repos...", text: $viewModel.repoSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Quick actions
            HStack {
                Button("Select All") {
                    viewModel.selectAllFilteredRepos()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Clear") {
                    viewModel.deselectAllRepos()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Text("\(viewModel.filteredRepos.count) repos")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    Task {
                        await viewModel.reloadRepos()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh repo list")
                .disabled(viewModel.isLoadingRepos)
            }

            // Repo list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.filteredRepos, id: \.self) { repo in
                        RepoRowView(
                            repo: repo,
                            isSelected: viewModel.selectedRepos.contains(repo),
                            onToggle: { viewModel.toggleRepo(repo) }
                        )
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(8)
        .frame(width: 280)
        .background(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct RepoRowView: View {
    let repo: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(repo)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
