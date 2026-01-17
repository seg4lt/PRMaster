import SwiftUI
import SwiftData

/// A unified filter bar component for both compact and full modes
struct FilterBar: View {
    let isCompact: Bool
    @Binding var selectedSavedFilter: NotificationFilter?
    @ObservedObject var viewModel: PRListViewModel
    let savedFilters: [NotificationFilter]

    @State private var showAuthorPopover = false
    @State private var showRepoPopover = false

    private var authorFilterLabel: String {
        if viewModel.authorFilters.isEmpty {
            return "Author"
        } else if viewModel.authorFilters.count == 1 {
            return "@\(viewModel.authorFilters.first ?? "unknown")"
        } else {
            return "\(viewModel.authorFilters.count) authors"
        }
    }

    private var repoFilterLabel: String {
        if viewModel.repoFilters.isEmpty {
            return "Repo"
        } else if viewModel.repoFilters.count == 1 {
            guard let repo = viewModel.repoFilters.first else { return "1 repo" }
            return repo.split(separator: "/").last.map(String.init) ?? repo
        } else {
            return "\(viewModel.repoFilters.count) repos"
        }
    }

    private var hasActiveFilters: Bool {
        selectedSavedFilter != nil || !viewModel.authorFilters.isEmpty || !viewModel.repoFilters.isEmpty
    }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            savedFilterMenu
            authorFilterButton
            repoFilterButton

            Spacer()

            if hasActiveFilters {
                clearButton
            }

            if !isCompact {
                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
        }
        .padding(.horizontal, isCompact ? 6 : 12)
        .padding(.vertical, isCompact ? 4 : 6)
    }

    // MARK: - Saved Filter Menu

    private var savedFilterMenu: some View {
        Menu {
            Button("No Filter") {
                selectedSavedFilter = nil
            }
            if !savedFilters.isEmpty {
                Divider()
                ForEach(savedFilters.filter { $0.isEnabled }) { filter in
                    Button(filter.name) {
                        selectedSavedFilter = filter
                    }
                }
            }
        } label: {
            FilterChip(
                icon: "line.3.horizontal.decrease.circle",
                label: selectedSavedFilter?.name ?? "Filter",
                isActive: selectedSavedFilter != nil,
                isCompact: isCompact
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Author Filter

    private var authorFilterButton: some View {
        Button {
            showAuthorPopover.toggle()
        } label: {
            FilterChip(
                icon: "person",
                label: authorFilterLabel,
                isActive: !viewModel.authorFilters.isEmpty,
                isCompact: isCompact
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAuthorPopover) {
            FilterPopover(
                items: viewModel.allAuthors,
                selectedItems: viewModel.authorFilters,
                itemLabel: { "@\($0)" },
                onToggle: { viewModel.toggleAuthorFilter($0) },
                onClearAll: { viewModel.authorFilters.removeAll() },
                maxHeight: isCompact ? 200 : 250,
                width: isCompact ? 180 : 200
            )
        }
    }

    // MARK: - Repo Filter

    private var repoFilterButton: some View {
        Button {
            showRepoPopover.toggle()
        } label: {
            FilterChip(
                icon: "folder",
                label: repoFilterLabel,
                isActive: !viewModel.repoFilters.isEmpty,
                isCompact: isCompact
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showRepoPopover) {
            FilterPopover(
                items: viewModel.allRepos,
                selectedItems: viewModel.repoFilters,
                itemLabel: { isCompact ? ($0.split(separator: "/").last.map(String.init) ?? $0) : $0 },
                onToggle: { viewModel.toggleRepoFilter($0) },
                onClearAll: { viewModel.repoFilters.removeAll() },
                maxHeight: isCompact ? 200 : 250,
                width: isCompact ? 200 : 250
            )
        }
    }

    // MARK: - Clear Button

    private var clearButton: some View {
        Button {
            selectedSavedFilter = nil
            viewModel.clearFilters()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: isCompact ? 12 : 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}

/// A styled chip for filter buttons
struct FilterChip: View {
    let icon: String
    let label: String
    let isActive: Bool
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 3 : 4) {
            Image(systemName: icon)
            Text(label)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: isCompact ? 8 : 10))
        }
        .font(isCompact ? .system(size: 10) : .caption)
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 3 : 4)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4 : 4))
    }
}
