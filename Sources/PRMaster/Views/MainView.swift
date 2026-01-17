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

    init(isCompact: Bool = true, showAPIStatsTab: Bool = false, openWindowAction: (() -> Void)? = nil) {
        self.isCompact = isCompact
        self.showAPIStatsTab = showAPIStatsTab
        self.openWindowAction = openWindowAction
    }

    private var availableTabs: [Tab] {
        isCompact ? Tab.compactTabs : Tab.fullWindowTabs
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                headerView
                Divider()
            }

            ErrorBannerList(
                errors: viewModel.errors,
                onDismiss: { viewModel.dismissError($0) },
                onRetry: { Task { await viewModel.retryFailedOperations() } }
            )

            MainTabBar(
                tabs: availableTabs,
                selectedTab: $selectedTab,
                badgeCount: { badgeCount(for: $0) },
                isCompact: isCompact,
                lastUpdate: viewModel.lastUpdate,
                isLoading: viewModel.isLoading,
                isEnriching: viewModel.isEnriching,
                onRefresh: { Task { await viewModel.refresh() } },
                onOpenWindow: openWindowAction
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await viewModel.loadIfNeeded()
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

    // MARK: - Navigation

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

    // MARK: - Header (Full Window Only)

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

    // MARK: - Badge Count

    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .toReview: return viewModel.toReviewPRs.count
        case .reviewed: return viewModel.reviewedPRs.count
        case .myPRs: return viewModel.myOpenPRs.count
        case .filters, .settings, .apiStats, .ai: return 0
        }
    }

    // MARK: - Filtering

    private func applyFilters(to prs: [EnrichedPullRequest]) -> [EnrichedPullRequest] {
        var filtered = prs

        if let savedFilter = selectedSavedFilter {
            filtered = filtered.filter { enrichedPR in
                let filePaths = enrichedPR.detail?.files?.nodes.map { $0.path } ?? []
                return savedFilter.matches(pr: enrichedPR.pr, filePaths: filePaths)
            }
        }

        if !viewModel.authorFilters.isEmpty {
            filtered = filtered.filter { pr in
                guard let author = pr.pr.author?.login else { return false }
                return viewModel.authorFilters.contains(author)
            }
        }

        if !viewModel.repoFilters.isEmpty {
            filtered = filtered.filter { pr in
                viewModel.repoFilters.contains(pr.pr.repository.nameWithOwner)
            }
        }

        if !viewModel.searchText.isEmpty {
            filtered = filtered.filter {
                $0.pr.title.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.pr.author?.login.localizedCaseInsensitiveContains(viewModel.searchText) == true
            }
        }

        return filtered
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .toReview:
            VStack(spacing: 0) {
                FilterBar(
                    isCompact: isCompact,
                    selectedSavedFilter: $selectedSavedFilter,
                    viewModel: viewModel,
                    savedFilters: savedFilters
                )
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
                FilterBar(
                    isCompact: isCompact,
                    selectedSavedFilter: $selectedSavedFilter,
                    viewModel: viewModel,
                    savedFilters: savedFilters
                )
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
}
