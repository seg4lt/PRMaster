import SwiftUI

/// Reusable repository list picker component
struct RepoListPicker: View {
    let availableRepos: [String]
    @Binding var selectedRepos: Set<String>
    @Binding var searchText: String
    var showSelectAll: Bool = true
    var height: CGFloat = 150

    private var filteredRepos: [String] {
        let repos = searchText.isEmpty
            ? availableRepos
            : availableRepos.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return repos.sorted { a, b in
            let aSelected = selectedRepos.contains(a)
            let bSelected = selectedRepos.contains(b)
            if aSelected != bSelected {
                return aSelected
            }
            return a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with count and actions
            HStack {
                Text("\(selectedRepos.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if showSelectAll {
                    Button("All") {
                        for repo in filteredRepos {
                            selectedRepos.insert(repo)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("None") {
                        selectedRepos.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search repos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Repo list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredRepos, id: \.self) { repo in
                        Button {
                            if selectedRepos.contains(repo) {
                                selectedRepos.remove(repo)
                            } else {
                                selectedRepos.insert(repo)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedRepos.contains(repo) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedRepos.contains(repo) ? .accentColor : .secondary)
                                Text(repo)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
