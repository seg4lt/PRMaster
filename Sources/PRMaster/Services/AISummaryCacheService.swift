import Foundation

/// Cache model for saved AI summaries
struct CachedSummary: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let dateLabel: String
    let commitCount: Int
    let summaryText: String
    let createdAt: Date
    let repositories: [String]
}

/// Service for caching and loading AI summaries
struct AISummaryCacheService {
    private static let cacheKey = "aiSummaryCache"

    /// Save completed summaries to cache
    static func saveSummaries(_ summaries: [DateRangeSummary]) {
        let cacheItems = summaries.compactMap { summary -> CachedSummary? in
            guard case .completed(let text) = summary.status else { return nil }
            return CachedSummary(
                id: summary.id,
                startDate: summary.dateRange.startDate,
                endDate: summary.dateRange.endDate,
                dateLabel: summary.dateRange.dateLabel,
                commitCount: summary.dateRange.commitCount,
                summaryText: text,
                createdAt: summary.createdAt,
                repositories: summary.repositories
            )
        }

        // Sort by startDate descending (newest date range first)
        let sortedCache = cacheItems.sorted { $0.startDate > $1.startDate }
        if let data = try? JSONEncoder().encode(sortedCache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// Load cached summaries
    static func loadSummaries() -> [DateRangeSummary] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedSummary].self, from: data) else {
            return []
        }

        // Restore cached summaries (sorted by startDate descending)
        return cached.sorted { $0.startDate > $1.startDate }.map { cache in
            let dateRange = DateRangeCommits(
                id: cache.id,
                startDate: cache.startDate,
                endDate: cache.endDate,
                commits: [],
                cachedCommitCount: cache.commitCount
            )
            return DateRangeSummary(
                id: cache.id,
                dateRange: dateRange,
                status: .completed(cache.summaryText),
                createdAt: cache.createdAt,
                repositories: cache.repositories
            )
        }
    }

    /// Clear all cached summaries
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
