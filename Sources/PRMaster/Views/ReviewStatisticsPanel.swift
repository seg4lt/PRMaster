import SwiftUI

struct ReviewStatisticsPanel: View {
    let pr: EnrichedPullRequest
    let fileComplexities: [String: FileComplexity]
    let viewStatuses: [String: FileViewStatus]
    let sessionTimer: ReviewSessionTimer
    let commentViewModel: ReviewCommentViewModel
    @Environment(\.dismiss) private var dismiss

    private var totalFiles: Int {
        fileComplexities.count
    }

    private var viewedFiles: Int {
        viewStatuses.values.filter { $0.isViewed }.count
    }

    private var completionPercentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(viewedFiles) / Double(totalFiles)
    }

    private var totalComments: Int {
        commentViewModel.comments.count + commentViewModel.drafts.count
    }

    private var averageTimePerFile: String {
        guard viewedFiles > 0 else { return "N/A" }
        let avgTime = sessionTimer.totalSessionTime / Double(viewedFiles)
        return formatTimeInterval(avgTime)
    }

    private var complexityBreakdown: [FileComplexity.ComplexityLevel: Int] {
        var breakdown: [FileComplexity.ComplexityLevel: Int] = [:]
        for complexity in fileComplexities.values {
            breakdown[complexity.level, default: 0] += 1
        }
        return breakdown
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review Statistics")
                    .font(.title2)
                    .fontWeight(.bold)

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
                    // Overview
                    overviewSection

                    // Progress
                    progressSection

                    // Complexity breakdown
                    complexitySection

                    // Timing
                    timingSection

                    // Comments
                    commentsSection
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
        .frame(width: 500, height: 600)
        .onAppear {
            Task {
                await sessionTimer.startSession()
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                StatCard(
                    title: "Total Files",
                    value: "\(totalFiles)",
                    icon: "doc.text",
                    color: .blue
                )

                StatCard(
                    title: "Viewed",
                    value: "\(viewedFiles)",
                    icon: "eye.fill",
                    color: .green
                )

                StatCard(
                    title: "Remaining",
                    value: "\(totalFiles - viewedFiles)",
                    icon: "circle",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Progress")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: completionPercentage, total: 1.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(completionPercentage * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewedFiles)/\(totalFiles) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var complexitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Complexity")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach([FileComplexity.ComplexityLevel.veryComplex, .complex, .moderate, .simple, .trivial], id: \.self) { level in
                    if let count = complexityBreakdown[level], count > 0 {
                        HStack {
                            Image(systemName: level.icon)
                                .foregroundColor(level.displayColor)
                                .font(.caption)

                            Text("\(level.rawValue): \(count)")
                                .font(.caption)

                            Spacer()

                            Text("\(count) files")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                StatCard(
                    title: "Total Time",
                    value: sessionTimer.formattedTotalTime,
                    icon: "timer",
                    color: .purple
                )

                StatCard(
                    title: "Avg Per File",
                    value: averageTimePerFile,
                    icon: "clock",
                    color: .cyan
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                StatCard(
                    title: "Total",
                    value: "\(totalComments)",
                    icon: "bubble.left.fill",
                    color: .blue
                )

                StatCard(
                    title: "Drafts",
                    value: "\(commentViewModel.drafts.count)",
                    icon: "pencil",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
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

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
