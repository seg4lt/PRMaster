import SwiftUI

struct ReviewProductivityDashboard: View {
    @ObservedObject var analytics: ReviewAnalyticsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Productivity Dashboard")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Track your review performance over time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Streak section
                    streakSection

                    // Today's progress
                    todaySection

                    // All-time stats
                    allTimeSection

                    // Recent sessions
                    recentSessionsSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Text("Press Esc or click outside to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 650, height: 700)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review Streak")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if analytics.streak.isHot {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("On Fire! 🔥")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            }

            HStack(spacing: 20) {
                StreakCard(
                    title: "Current",
                    value: "\(analytics.streak.currentStreak)",
                    subtitle: "day\(analytics.streak.currentStreak == 1 ? "" : "s")",
                    icon: "calendar",
                    color: analytics.streak.isHot ? .orange : .blue
                )

                StreakCard(
                    title: "Longest",
                    value: "\(analytics.streak.longestStreak)",
                    subtitle: "day\(analytics.streak.longestStreak == 1 ? "" : "s")",
                    icon: "trophy",
                    color: .yellow
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Progress")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                StatCard(
                    title: "Files Reviewed",
                    value: "\(analytics.todayStats.filesReviewed)",
                    icon: "doc.text",
                    color: .green
                )

                StatCard(
                    title: "Time Spent",
                    value: analytics.todayStats.formattedTime,
                    icon: "timer",
                    color: .purple
                )

                StatCard(
                    title: "PRs Reviewed",
                    value: "\(analytics.todayStats.prsReviewed)",
                    icon: "number",
                    color: .blue
                )

                StatCard(
                    title: "Comments",
                    value: "\(analytics.todayStats.commentsAdded)",
                    icon: "bubble.left.fill",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All-Time Stats")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    BigStatCard(
                        title: "Total Files",
                        value: "\(analytics.allTimeStats.totalFilesReviewed)",
                        icon: "doc.text.fill",
                        color: .green
                    )

                    BigStatCard(
                        title: "Total Time",
                        value: analytics.allTimeStats.formattedTotalTime,
                        icon: "clock.fill",
                        color: .purple
                    )
                }

                HStack(spacing: 20) {
                    BigStatCard(
                        title: "PRs Reviewed",
                        value: "\(analytics.allTimeStats.totalPRsReviewed)",
                        icon: "checkmark.seal.fill",
                        color: .blue
                    )

                    BigStatCard(
                        title: "Avg Velocity",
                        value: String(format: "%.1f files/hr", analytics.allTimeStats.averageVelocity),
                        icon: "speedometer",
                        color: .orange
                    )
                }

                if let bestDay = analytics.allTimeStats.bestDay {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Best Day")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("\(bestDay.filesReviewed) files, \(bestDay.formattedTime), \(bestDay.prsReviewed) PRs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
                .foregroundStyle(.secondary)

            if analytics.sessions.isEmpty {
                Text("No review sessions yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                VStack(spacing: 8) {
                    ForEach(analytics.sessions.suffix(5).reversed()) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct StreakCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 2)
        )
    }
}

struct BigStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

struct SessionRow: View {
    let session: ReviewSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(session.isCompleted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.prKey)
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(formatDate(session.startTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Label("\(session.filesViewed)/\(session.totalFiles) files", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Label(session.isCompleted ? formatDuration(session.duration) : "In progress",
                          systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if session.commentsAdded > 0 {
                        Label("\(session.commentsAdded)", systemImage: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    ReviewProductivityDashboard(analytics: ReviewAnalyticsViewModel())
}
