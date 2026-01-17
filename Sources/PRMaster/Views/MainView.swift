import SwiftUI
import SwiftData
import AppKit

enum Tab: String, CaseIterable {
    case toReview = "Review"
    case reviewed = "Done"
    case myPRs = "Mine"
    case filters = "Filters"
    case settings = "Settings"
    case apiStats = "API"
    case ai = "AI"

    var icon: String {
        switch self {
        case .toReview: return "tray.and.arrow.down.fill"
        case .reviewed: return "checkmark.circle.fill"
        case .myPRs: return "person.fill"
        case .filters: return "bell.badge.fill"
        case .settings: return "gearshape.fill"
        case .apiStats: return "chart.bar.fill"
        case .ai: return "sparkles"
        }
    }

    var fullName: String {
        switch self {
        case .toReview: return "To Review"
        case .reviewed: return "Reviewed"
        case .myPRs: return "My PRs"
        case .filters: return "Filters"
        case .settings: return "Settings"
        case .apiStats: return "API Stats"
        case .ai: return "AI Summary"
        }
    }

    static var compactTabs: [Tab] {
        [.toReview, .reviewed, .myPRs]
    }

    static var fullWindowTabs: [Tab] {
        [.toReview, .reviewed, .myPRs, .filters, .ai, .apiStats, .settings]
    }
}

struct MainView: View {
    let isCompact: Bool
    let showAPIStatsTab: Bool
    var openWindowAction: (() -> Void)?

    @State private var selectedTab: Tab = .toReview
    @ObservedObject private var viewModel = PRListViewModel.shared
    @Query private var savedFilters: [NotificationFilter]
    @State private var selectedSavedFilter: NotificationFilter?
    @State private var currentTime = Date()
    @State private var showAuthorPopover = false
    @State private var showRepoPopover = false

    init(isCompact: Bool = true, showAPIStatsTab: Bool = false, openWindowAction: (() -> Void)? = nil) {
        self.isCompact = isCompact
        self.showAPIStatsTab = showAPIStatsTab
        self.openWindowAction = openWindowAction
    }

    private var availableTabs: [Tab] {
        isCompact ? Tab.compactTabs : Tab.fullWindowTabs
    }

    private func timeAgoText(from date: Date) -> String {
        let seconds = Int(currentTime.timeIntervalSince(date))
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }

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

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                headerView
                Divider()
            }

            // Error banners
            ErrorBannerList(
                errors: viewModel.errors,
                onDismiss: { viewModel.dismissError($0) },
                onRetry: { Task { await viewModel.retryFailedOperations() } }
            )

            tabBar
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            currentTime = Date()
        }
        .onChange(of: savedFilters) { _, newFilters in
            viewModel.notificationFilters = newFilters
        }
        .onAppear {
            viewModel.notificationFilters = savedFilters
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "1")) { _ in
            selectedTab = .toReview
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "2")) { _ in
            selectedTab = .reviewed
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "3")) { _ in
            selectedTab = .myPRs
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateToPreviousTab()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateToNextTab()
            return .handled
        }
    }

    private func navigateToNextTab() {
        let tabs = availableTabs
        if let currentIndex = tabs.firstIndex(of: selectedTab),
           currentIndex < tabs.count - 1 {
            selectedTab = tabs[currentIndex + 1]
        }
    }

    private func navigateToPreviousTab() {
        let tabs = availableTabs
        if let currentIndex = tabs.firstIndex(of: selectedTab),
           currentIndex > 0 {
            selectedTab = tabs[currentIndex - 1]
        }
    }

    private var headerView: some View {
        HStack {
            Text("PRMaster")
                .font(.title2)
                .fontWeight(.semibold)

            if let user = viewModel.currentUser {
                Text("@\(user)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tabBar: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(availableTabs, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    count: badgeCount(for: tab),
                    isCompact: isCompact
                ) {
                    selectedTab = tab
                }
            }

            Spacer()

            // Last updated time
            if let lastUpdate = viewModel.lastUpdate {
                Text(timeAgoText(from: lastUpdate))
                    .font(.system(size: isCompact ? 9 : 11))
                    .foregroundStyle(.tertiary)
            }

            if isCompact {
                if viewModel.isLoading || viewModel.isEnriching {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                if let action = openWindowAction {
                    Button(action: action) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Open Full Window")
                }
            }
        }
        .padding(.horizontal, isCompact ? 4 : 8)
        .padding(.vertical, isCompact ? 2 : 6)
        .frame(height: isCompact ? 28 : nil)
    }

    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .toReview: return viewModel.toReviewPRs.count
        case .reviewed: return viewModel.reviewedPRs.count
        case .myPRs: return viewModel.myOpenPRs.count
        case .filters: return 0
        case .settings: return 0
        case .apiStats: return 0
        case .ai: return 0
        }
    }

    private func applyFilters(to prs: [EnrichedPullRequest]) -> [EnrichedPullRequest] {
        var filtered = prs

        // Apply saved filter if selected (single select)
        if let savedFilter = selectedSavedFilter {
            filtered = filtered.filter { enrichedPR in
                let filePaths = enrichedPR.detail?.files?.nodes.map { $0.path } ?? []
                return savedFilter.matches(pr: enrichedPR.pr, filePaths: filePaths)
            }
        }

        // Apply author filters (multi-select)
        if !viewModel.authorFilters.isEmpty {
            filtered = filtered.filter { pr in
                guard let author = pr.pr.author?.login else { return false }
                return viewModel.authorFilters.contains(author)
            }
        }

        // Apply repo filters (multi-select)
        if !viewModel.repoFilters.isEmpty {
            filtered = filtered.filter { pr in
                viewModel.repoFilters.contains(pr.pr.repository.nameWithOwner)
            }
        }

        // Apply search filter
        if !viewModel.searchText.isEmpty {
            filtered = filtered.filter {
                $0.pr.title.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.pr.author?.login.localizedCaseInsensitiveContains(viewModel.searchText) == true
            }
        }

        return filtered
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .toReview:
            VStack(spacing: 0) {
                if isCompact {
                    compactFilterBar
                } else {
                    filterBar
                }
                Divider()
                PRListView(
                    prs: applyFilters(to: isCompact ? viewModel.toReviewPRs : viewModel.filteredToReviewPRs),
                    currentUser: viewModel.currentUser,
                    isLoading: viewModel.isLoading,
                    emptyMessage: "No PRs awaiting your review",
                    isCompact: isCompact
                )
            }
        case .reviewed:
            VStack(spacing: 0) {
                if isCompact {
                    compactFilterBar
                } else {
                    filterBar
                }
                Divider()
                PRListView(
                    prs: applyFilters(to: isCompact ? viewModel.reviewedPRs : viewModel.filteredReviewedPRs),
                    currentUser: viewModel.currentUser,
                    isLoading: viewModel.isLoading,
                    emptyMessage: "No PRs you've reviewed",
                    isCompact: isCompact
                )
            }
        case .myPRs:
            MyPRsView(viewModel: viewModel)
        case .filters:
            FiltersView()
        case .settings:
            SettingsView()
        case .apiStats:
            APIStatsView()
        case .ai:
            AISummaryView()
        }
    }

    private var compactFilterBar: some View {
        HStack(spacing: 6) {
            // Saved filter dropdown
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
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedSavedFilter?.name ?? "Filter")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selectedSavedFilter != nil ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)

            // Author multi-select popover
            Button {
                showAuthorPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "person")
                    Text(authorFilterLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(!viewModel.authorFilters.isEmpty ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAuthorPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Clear All") {
                        viewModel.authorFilters.removeAll()
                    }
                    .padding(8)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.allAuthors, id: \.self) { author in
                                Button {
                                    viewModel.toggleAuthorFilter(author)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.authorFilters.contains(author) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(viewModel.authorFilters.contains(author) ? .accentColor : .secondary)
                                        Text("@\(author)")
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .frame(width: 180)
            }

            // Repo multi-select popover
            Button {
                showRepoPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                    Text(repoFilterLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(!viewModel.repoFilters.isEmpty ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRepoPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Clear All") {
                        viewModel.repoFilters.removeAll()
                    }
                    .padding(8)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.allRepos, id: \.self) { repo in
                                Button {
                                    viewModel.toggleRepoFilter(repo)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.repoFilters.contains(repo) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(viewModel.repoFilters.contains(repo) ? .accentColor : .secondary)
                                        Text(repo.split(separator: "/").last.map(String.init) ?? repo)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .frame(width: 200)
            }

            Spacer()

            // Clear button
            if selectedSavedFilter != nil || !viewModel.authorFilters.isEmpty || !viewModel.repoFilters.isEmpty {
                Button {
                    selectedSavedFilter = nil
                    viewModel.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Saved filter dropdown (single select)
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
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedSavedFilter?.name ?? "Filter")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedSavedFilter != nil ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)

            // Author multi-select popover
            Button {
                showAuthorPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person")
                    Text(authorFilterLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(!viewModel.authorFilters.isEmpty ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAuthorPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Clear All") {
                        viewModel.authorFilters.removeAll()
                    }
                    .padding(8)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.allAuthors, id: \.self) { author in
                                Button {
                                    viewModel.toggleAuthorFilter(author)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.authorFilters.contains(author) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(viewModel.authorFilters.contains(author) ? .accentColor : .secondary)
                                        Text("@\(author)")
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .frame(width: 200)
            }

            // Repo multi-select popover
            Button {
                showRepoPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(repoFilterLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(!viewModel.repoFilters.isEmpty ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRepoPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Clear All") {
                        viewModel.repoFilters.removeAll()
                    }
                    .padding(8)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.allRepos, id: \.self) { repo in
                                Button {
                                    viewModel.toggleRepoFilter(repo)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.repoFilters.contains(repo) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(viewModel.repoFilters.contains(repo) ? .accentColor : .secondary)
                                        Text(repo)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .frame(width: 250)
            }

            Spacer()

            if selectedSavedFilter != nil || !viewModel.authorFilters.isEmpty || !viewModel.repoFilters.isEmpty {
                Button {
                    selectedSavedFilter = nil
                    viewModel.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

}

struct TabButton: View {
    let tab: Tab
    let isSelected: Bool
    let count: Int
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 3 : 4) {
                Image(systemName: tab.icon)
                    .font(isCompact ? .system(size: 9) : .caption)
                Text(tab.rawValue)
                    .font(isCompact ? .system(size: 10) : .caption)
                if count > 0 {
                    Text("\(count)")
                        .font(isCompact ? .system(size: 9) : .caption2)
                        .padding(.horizontal, isCompact ? 4 : 5)
                        .padding(.vertical, isCompact ? 1 : 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .frame(height: isCompact ? 18 : nil)
            .padding(.horizontal, isCompact ? 5 : 10)
            .padding(.vertical, isCompact ? 2 : 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4 : 6))
        }
        .buttonStyle(.plain)
    }
}
