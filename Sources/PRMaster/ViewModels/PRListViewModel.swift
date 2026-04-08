import Foundation
import SwiftUI
import SwiftData
import Combine
import UserNotifications

extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<String>()
        return filter { element in
            let id = "\(element.id)"
            if seen.contains(id) {
                return false
            }
            seen.insert(id)
            return true
        }
    }
}

@MainActor
class PRListViewModel: ObservableObject {
    static let shared = PRListViewModel()

    @Published var toReviewPRs: [EnrichedPullRequest] = []
    @Published var reviewedPRs: [EnrichedPullRequest] = []
    @Published var myOpenPRs: [EnrichedPullRequest] = []
    @Published var conversationGroups: [ConversationGroup] = []
    @Published var isLoading = false
    @Published var isEnriching = false
    @Published var isLoadingConversations = false
    @Published var errors: [AppError] = []
    @Published var lastUpdate: Date?
    @Published var currentUser: String?

    @Published var authorFilters: Set<String> = []
    @Published var repoFilters: Set<String> = []
    @Published var searchText: String = ""

    private let maxRetries = 3
    private var retryCount = 0

    // Filters for notifications
    var notificationFilters: [NotificationFilter] = []
    var modelContainer: ModelContainer?

    private let github = GitHubService.shared
    private let cache = CacheService.shared
    private var refreshTimer: Timer?
    private var cacheLoaded = false

    /// Fetch notification filters from SwiftData
    @MainActor
    private func fetchNotificationFilters() -> [NotificationFilter] {
        guard let container = modelContainer else {
            return notificationFilters
        }
        do {
            let context = container.mainContext
            let descriptor = FetchDescriptor<NotificationFilter>()
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch notification filters: \(error)")
            return notificationFilters
        }
    }

    var filteredToReviewPRs: [EnrichedPullRequest] {
        applyFilters(to: toReviewPRs)
    }

    var filteredReviewedPRs: [EnrichedPullRequest] {
        applyFilters(to: reviewedPRs)
    }

    var allAuthors: [String] {
        let authors = Set(
            (toReviewPRs + reviewedPRs + myOpenPRs)
                .compactMap { $0.pr.author?.login }
        )
        return authors.sorted()
    }

    var allRepos: [String] {
        let repos = Set(
            (toReviewPRs + reviewedPRs + myOpenPRs)
                .map { $0.pr.repository.nameWithOwner }
        )
        return repos.sorted()
    }

    var conversationCount: Int {
        conversationGroups.reduce(0) { $0 + $1.conversations.count }
    }

    init() {
        startAutoRefresh()
        // Load cache synchronously on init for instant UI
        Task { await loadFromCache() }
    }

    private func loadFromCache() async {
        guard !cacheLoaded else { return }
        cacheLoaded = true

        if let cached = await cache.loadPRCache() {
            // Only use cache if we don't have data yet
            if toReviewPRs.isEmpty && reviewedPRs.isEmpty && myOpenPRs.isEmpty {
                toReviewPRs = cached.toReview
                reviewedPRs = cached.reviewed
                myOpenPRs = cached.myPRs
                currentUser = cached.currentUser
                lastUpdate = cached.timestamp
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func loadAllData() async {
        guard !isLoading && !isEnriching else { return }

        // Only show skeleton on initial load, show subtle indicator on refresh
        let isInitialLoad = toReviewPRs.isEmpty && reviewedPRs.isEmpty && myOpenPRs.isEmpty
        if isInitialLoad {
            isLoading = true
        } else {
            isEnriching = true  // Shows loading indicator while keeping data visible
        }
        errors = []
        retryCount = 0

        currentUser = try? await github.getCurrentUser()
        let userLogin = currentUser ?? ""

        // Fetch basic PR lists in parallel
        async let toReviewBasic = loadBasicPRs(type: .toReview)
        async let reviewedBasic = loadBasicPRs(type: .reviewed)
        async let myOpenBasic = loadBasicPRs(type: .myOpen)

        let (toReviewResult, reviewedResult, myOpenResult) = await (
            toReviewBasic,
            reviewedBasic,
            myOpenBasic
        )

        // Collect any errors
        [toReviewResult.error, reviewedResult.error, myOpenResult.error]
            .compactMap { $0 }
            .forEach { errors.append($0) }

        // Enrich all PRs in parallel (in background, no UI update yet)
        async let enrichedToReview = enrichPRsSafe(toReviewResult.prs)
        async let enrichedReviewed = enrichPRsSafe(reviewedResult.prs)
        async let enrichedMyOpen = enrichPRsSafe(myOpenResult.prs)

        let (toReviewEnriched, reviewedEnriched, myOpenEnriched) = await (
            enrichedToReview,
            enrichedReviewed,
            enrichedMyOpen
        )

        // Helper to check if user has submitted a final review
        let hasSubmittedReview: (EnrichedPullRequest) -> Bool = { enriched in
            enriched.reviews.contains { review in
                review.author?.login == userLogin &&
                (review.state == .approved || review.state == .changesRequested)
            }
        }

        // Filter "To Review" - PRs where current user hasn't submitted approval/changes requested
        let toReviewFiltered = toReviewEnriched.filter { enriched in
            let isMyPR = enriched.pr.author?.login == userLogin
            return !isMyPR && !hasSubmittedReview(enriched)
        }

        // Include PRs from reviewed where user only commented (not approved/changes requested)
        let commentedOnly = reviewedEnriched.filter { enriched in
            let isMyPR = enriched.pr.author?.login == userLogin
            return !isMyPR && !hasSubmittedReview(enriched)
        }

        // "Reviewed" - PRs by others that user has approved/changes requested
        let alreadyReviewed = toReviewEnriched.filter { enriched in
            let isMyPR = enriched.pr.author?.login == userLogin
            return !isMyPR && hasSubmittedReview(enriched)
        }
        let otherReviewed = reviewedEnriched.filter { enriched in
            let isMyPR = enriched.pr.author?.login == userLogin
            return !isMyPR && hasSubmittedReview(enriched)
        }

        // SINGLE ATOMIC UI UPDATE - only now touch @Published properties
        toReviewPRs = (toReviewFiltered + commentedOnly).uniqued()
        reviewedPRs = (alreadyReviewed + otherReviewed).uniqued()
        myOpenPRs = myOpenEnriched
        lastUpdate = Date()
        isLoading = false
        isEnriching = false

        // Save to cache
        await cache.savePRCache(
            toReview: toReviewPRs,
            reviewed: reviewedPRs,
            myPRs: myOpenPRs,
            currentUser: currentUser
        )

        // Check for notifications
        let filters = fetchNotificationFilters()
        await checkNotifications(for: toReviewPRs, filters: filters)
        await checkMyPRNotifications(for: myOpenPRs)

        await loadConversations()
    }

    private func loadConversations() async {
        guard let currentUser, !currentUser.isEmpty else {
            conversationGroups = []
            isLoadingConversations = false
            return
        }

        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversationGroups = try await github.fetchConversations(currentUser: currentUser)
        } catch {
            conversationGroups = []
            let appError = AppError.from(error)
            if !errors.contains(appError) {
                errors.append(appError)
            }
        }
    }

    private enum PRFetchType {
        case toReview, reviewed, myOpen
    }

    private func loadBasicPRs(type: PRFetchType) async -> (prs: [PullRequest], error: AppError?) {
        do {
            let prs: [PullRequest]
            switch type {
            case .toReview:
                prs = try await github.fetchPRsToReview()
            case .reviewed:
                prs = try await github.fetchReviewedPRs()
            case .myOpen:
                prs = try await github.fetchMyPRs(state: "open")
            }
            return (prs, nil)
        } catch {
            return ([], AppError.from(error))
        }
    }

    private func enrichPRsSafe(_ prs: [PullRequest]) async -> [EnrichedPullRequest] {
        do {
            return try await github.enrichPRs(prs)
        } catch {
            // Return basic enriched PRs if enrichment fails
            return prs.map { pr in
                EnrichedPullRequest(pr: pr, reviewDecision: nil, reviews: [], requestedReviewers: [], mergedBy: nil, mergedAt: nil, detail: nil)
            }
        }
    }

    private func checkNotifications(for prs: [EnrichedPullRequest], filters: [NotificationFilter]) async {
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        let onlyFilterNotifications = UserDefaults.standard.bool(forKey: "onlyFilterNotifications")

        // If notifications disabled, just update state without sending
        guard notificationsEnabled else {
            for pr in prs {
                await cache.markAsSeen(pr: pr)
            }
            return
        }

        for pr in prs {
            // Skip draft PRs - no notifications for drafts
            guard !pr.pr.isDraft else {
                await cache.markAsSeen(pr: pr)
                continue
            }

            if let reason = await cache.checkAndUpdateNotificationState(pr: pr) {
                // If only filter notifications, check if PR matches any enabled filter
                if onlyFilterNotifications {
                    let filePaths = pr.detail?.files?.nodes.map { $0.path } ?? []
                    let matchesFilter = filters.contains { filter in
                        filter.isEnabled && filter.matches(pr: pr.pr, filePaths: filePaths)
                    }
                    if matchesFilter {
                        await sendNotification(for: pr, reason: reason, matchedFilter: true)
                    }
                } else {
                    await sendNotification(for: pr, reason: reason, matchedFilter: false)
                }
            }
        }
    }

    @MainActor
    private func sendNotification(for pr: EnrichedPullRequest, reason: CacheService.NotificationReason, matchedFilter: Bool) async {
        let title: String
        let body: String

        switch reason {
        case .newPR:
            title = matchedFilter ? "🔔 New PR (Filter Match)" : "New PR to Review"
            body = "\(pr.pr.title) by @\(pr.pr.author?.login ?? "unknown")"
        case .newCommits:
            title = matchedFilter ? "🔔 PR Updated (Filter Match)" : "PR Updated"
            body = "\(pr.pr.title)"
        }

        // Use UserNotifications
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "pr-\(pr.pr.id)-\(reason)",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
            }
        } catch {
            print("Notification error: \(error)")
        }
    }

    // MARK: - My PR Notifications

    private func checkMyPRNotifications(for prs: [EnrichedPullRequest]) async {
        let myPRNotificationsEnabled = UserDefaults.standard.bool(forKey: "myPRNotificationsEnabled")
        guard myPRNotificationsEnabled else { return }

        for pr in prs {
            if let reason = await cache.checkMyPRNotificationState(pr: pr) {
                await sendMyPRNotification(for: pr, reason: reason)
            }
        }
    }

    @MainActor
    private func sendMyPRNotification(for pr: EnrichedPullRequest, reason: CacheService.MyPRNotificationReason) async {
        let title: String
        let body: String

        switch reason {
        case .newReview(let reviewer):
            title = "New Review on Your PR"
            body = "@\(reviewer) reviewed: \(pr.pr.title)"
        case .newComment:
            title = "New Comment on Your PR"
            body = pr.pr.title
        }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "mypr-\(pr.pr.id)-\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
            }
        } catch {
            print("My PR notification error: \(error)")
        }
    }

    func refresh() async {
        await loadAllData()
    }

    func retryFailedOperations() async {
        guard retryCount < maxRetries else { return }
        retryCount += 1
        await loadAllData()
    }

    func dismissError(_ error: AppError) {
        errors.removeAll { $0 == error }
    }

    func clearErrors() {
        errors.removeAll()
    }

    /// Only load if we don't have data or data is stale
    func loadIfNeeded() async {
        // If we have data and it's fresh (within poll interval), don't reload
        if let lastUpdate = lastUpdate {
            let pollingInterval = UserDefaults.standard.double(forKey: "pollingInterval")
            let interval = pollingInterval > 0 ? pollingInterval : 300 // default 5 min
            let timeSinceUpdate = Date().timeIntervalSince(lastUpdate)

            if timeSinceUpdate < interval && !toReviewPRs.isEmpty {
                // Data is fresh, no need to reload
                if conversationGroups.isEmpty, currentUser != nil {
                    await loadConversations()
                }
                return
            }
        }

        await loadAllData()
    }

    private func applyFilters(to prs: [EnrichedPullRequest]) -> [EnrichedPullRequest] {
        var filtered = prs

        if !authorFilters.isEmpty {
            filtered = filtered.filter { pr in
                guard let author = pr.pr.author?.login else { return false }
                return authorFilters.contains(author)
            }
        }

        if !repoFilters.isEmpty {
            filtered = filtered.filter { pr in
                repoFilters.contains(pr.pr.repository.nameWithOwner)
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.pr.title.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    func clearFilters() {
        authorFilters.removeAll()
        repoFilters.removeAll()
        searchText = ""
    }

    func toggleAuthorFilter(_ author: String) {
        if authorFilters.contains(author) {
            authorFilters.remove(author)
        } else {
            authorFilters.insert(author)
        }
    }

    func toggleRepoFilter(_ repo: String) {
        if repoFilters.contains(repo) {
            repoFilters.remove(repo)
        } else {
            repoFilters.insert(repo)
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }
}
