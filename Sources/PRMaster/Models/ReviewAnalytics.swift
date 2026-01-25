import Foundation
import SwiftUI

struct ReviewSession: Codable, Identifiable {
    let id: UUID
    let prKey: String
    let startTime: Date
    var endTime: Date?
    var filesViewed: Int
    var totalFiles: Int
    var commentsAdded: Int
    var draftsCreated: Int

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var isCompleted: Bool {
        endTime != nil
    }

    var reviewVelocity: Double {
        guard duration > 0 else { return 0 }
        return Double(filesViewed) / (duration / 3600)  // files per hour
    }

    init(prKey: String, totalFiles: Int) {
        self.id = UUID()
        self.prKey = prKey
        self.startTime = Date()
        self.endTime = nil
        self.filesViewed = 0
        self.totalFiles = totalFiles
        self.commentsAdded = 0
        self.draftsCreated = 0
    }
}

struct ReviewStreak: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var lastReviewDate: Date?

    var isHot: Bool {
        currentStreak >= 3
    }

    static let `default` = ReviewStreak(currentStreak: 0, longestStreak: 0, lastReviewDate: nil)
}

@MainActor
class ReviewAnalyticsViewModel: ObservableObject {
    @Published var sessions: [ReviewSession] = []
    @Published var streak: ReviewStreak = .default
    @Published var todayStats: DayStats = DayStats()
    @Published var allTimeStats: AllTimeStats = AllTimeStats()

    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "reviewSessions"
    private let streakKey = "reviewStreak"

    init() {
        loadSessions()
        loadStreak()
        updateStats()
    }

    func startSession(prKey: String, totalFiles: Int) -> UUID {
        let session = ReviewSession(prKey: prKey, totalFiles: totalFiles)
        sessions.append(session)
        saveSessions()
        return session.id
    }

    func endSession(sessionId: UUID, commentsAdded: Int = 0, draftsCreated: Int = 0) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        sessions[index].endTime = Date()
        sessions[index].commentsAdded = commentsAdded
        sessions[index].draftsCreated = draftsCreated

        updateStreak()
        saveSessions()
        updateStats()
    }

    func updateFilesViewed(sessionId: UUID, count: Int) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].filesViewed = count
        saveSessions()
        updateStats()
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastDate = streak.lastReviewDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysSince = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysSince == 0 {
                // Same day, no change
                return
            } else if daysSince == 1 {
                // Next day, increment streak
                streak.currentStreak += 1
            } else {
                // Streak broken
                streak.currentStreak = 1
            }
        } else {
            // First review
            streak.currentStreak = 1
        }

        streak.lastReviewDate = today

        // Update longest streak
        if streak.currentStreak > streak.longestStreak {
            streak.longestStreak = streak.currentStreak
        }

        saveStreak()
    }

    private func updateStats() {
        let today = Calendar.current.startOfDay(for: Date())
        let todaySessions = sessions.filter { Calendar.current.isDate($0.startTime, inSameDayAs: today) }

        todayStats = DayStats(
            filesReviewed: todaySessions.reduce(0) { $0 + $1.filesViewed },
            timeSpent: todaySessions.reduce(0) { $0 + $1.duration },
            prsReviewed: todaySessions.count,
            commentsAdded: todaySessions.reduce(0) { $0 + $1.commentsAdded }
        )

        let completedSessions = sessions.filter { $0.isCompleted }

        allTimeStats = AllTimeStats(
            totalFilesReviewed: completedSessions.reduce(0) { $0 + $1.filesViewed },
            totalTimeSpent: completedSessions.reduce(0) { $0 + $1.duration },
            totalPRsReviewed: completedSessions.count,
            totalCommentsAdded: completedSessions.reduce(0) { $0 + $1.commentsAdded },
            averageVelocity: completedSessions.isEmpty ? 0 : completedSessions.reduce(0.0) { $0 + $1.reviewVelocity } / Double(completedSessions.count),
            bestDay: findBestDay(),
            longestStreak: streak.longestStreak
        )
    }

    private func findBestDay() -> DayStats? {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }

        let dayStatsList = grouped.map { (day, sessions) in
            DayStats(
                filesReviewed: sessions.reduce(0) { $0 + $1.filesViewed },
                timeSpent: sessions.reduce(0) { $0 + $1.duration },
                prsReviewed: sessions.count,
                commentsAdded: sessions.reduce(0) { $0 + $1.commentsAdded }
            )
        }

        return dayStatsList.max(by: { $0.filesReviewed < $1.filesReviewed })
    }

    private func loadSessions() {
        guard let data = userDefaults.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([ReviewSession].self, from: data) else {
            sessions = []
            return
        }
        sessions = decoded
    }

    private func saveSessions() {
        guard let encoded = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(encoded, forKey: sessionsKey)
    }

    private func loadStreak() {
        guard let data = userDefaults.data(forKey: streakKey),
              let decoded = try? JSONDecoder().decode(ReviewStreak.self, from: data) else {
            streak = .default
            return
        }
        streak = decoded
    }

    private func saveStreak() {
        guard let encoded = try? JSONEncoder().encode(streak) else { return }
        userDefaults.set(encoded, forKey: streakKey)
    }
}

struct DayStats: Codable {
    var filesReviewed: Int = 0
    var timeSpent: TimeInterval = 0
    var prsReviewed: Int = 0
    var commentsAdded: Int = 0

    var formattedTime: String {
        let hours = Int(timeSpent) / 3600
        let minutes = Int(timeSpent) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
}

struct AllTimeStats: Codable {
    var totalFilesReviewed: Int = 0
    var totalTimeSpent: TimeInterval = 0
    var totalPRsReviewed: Int = 0
    var totalCommentsAdded: Int = 0
    var averageVelocity: Double = 0  // files per hour
    var bestDay: DayStats? = nil
    var longestStreak: Int = 0

    var formattedTotalTime: String {
        let hours = Int(totalTimeSpent) / 3600
        let minutes = Int(totalTimeSpent) / 60 % 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
