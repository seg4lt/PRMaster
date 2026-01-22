import SwiftUI

struct RepoListPicker: View {
    let availableRepos: [String]
    @Binding var selectedRepos: Set<String>
    @Binding var searchText: String
    var singleSelection: Binding<String?>? = nil  // NEW: For single-select mode
    var showSelectAll: Bool = true
    var height: CGFloat = 150

    private var isSingleSelect: Bool { singleSelection != nil }

    private var filteredRepos: [String] {
        let repos = searchText.isEmpty
            ? availableRepos
            : availableRepos.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return repos.sorted { a, b in
            if isSingleSelect {
                let aSelected = (singleSelection?.wrappedValue == a)
                let bSelected = (singleSelection?.wrappedValue == b)
                if aSelected != bSelected {
                    return aSelected
                }
            } else {
                let aSelected = selectedRepos.contains(a)
                let bSelected = selectedRepos.contains(b)
                if aSelected != bSelected {
                    return aSelected
                }
            }
            return a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isSingleSelect {
                    Text(singleSelection?.wrappedValue != nil ? "1 selected" : "None selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedRepos.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showSelectAll && !isSingleSelect {
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredRepos, id: \.self) { repo in
                        Button {
                            if isSingleSelect {
                                // Single-select mode: clear previous selection and set new one
                                if singleSelection?.wrappedValue == repo {
                                    singleSelection?.wrappedValue = nil
                                } else {
                                    singleSelection?.wrappedValue = repo
                                }
                            } else {
                                // Multi-select mode: toggle selection
                                if selectedRepos.contains(repo) {
                                    selectedRepos.remove(repo)
                                } else {
                                    selectedRepos.insert(repo)
                                }
                            }
                        } label: {
                            HStack {
                                let isSelected = isSingleSelect
                                    ? (singleSelection?.wrappedValue == repo)
                                    : selectedRepos.contains(repo)
                                Image(systemName: isSelected ? "circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
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
            .id(searchText) // Force re-render when search text changes
        }
    }
}
