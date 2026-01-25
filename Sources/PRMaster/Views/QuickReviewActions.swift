import SwiftUI

/// Quick action buttons for reviewing files
struct QuickReviewActions: View {
    let pr: EnrichedPullRequest
    let onApprove: () -> Void
    let onRequestChanges: () -> Void
    let onComment: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onApprove) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("Approve")
                        .font(.caption)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Approve this PR")

            Button(action: onRequestChanges) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text("Request Changes")
                        .font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Request changes")

            Button(action: onComment) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.caption)
                    Text("Comment")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Submit general comment")
        }
    }
}

/// File-level quick actions
struct FileQuickActions: View {
    let file: ChangedFile
    let isViewed: Bool
    let onViewedToggle: () -> Void
    let onApproveFile: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onViewedToggle) {
                Image(systemName: isViewed ? "eye.slash.fill" : "eye.fill")
                    .font(.caption)
                    .foregroundColor(isViewed ? .secondary : .blue)
            }
            .buttonStyle(.plain)
            .help(isViewed ? "Mark as unviewed" : "Mark as viewed")

            Button(action: onApproveFile) {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .help("Approve this file")
        }
    }
}

/// Review checklist for common review items
struct ReviewChecklist: View {
    @Binding var checkedItems: Set<String>
    let onSubmit: () -> Void

    private let checklistItems = [
        "Code follows style guidelines",
        "No obvious bugs or logic errors",
        "Tests are included/updated",
        "Documentation is updated",
        "Security concerns addressed",
        "Performance implications considered"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Checklist")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(checklistItems, id: \.self) { item in
                    Button(action: {
                        if checkedItems.contains(item) {
                            checkedItems.remove(item)
                        } else {
                            checkedItems.insert(item)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: checkedItems.contains(item) ? "checkmark.square.fill" : "square")
                                .foregroundColor(checkedItems.contains(item) ? .blue : .secondary)
                            Text(item)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !checkedItems.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: Double(checkedItems.count), total: Double(checklistItems.count))
                        .progressViewStyle(.linear)
                    Text("\(checkedItems.count)/\(checklistItems.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Review history display
struct ReviewHistoryView: View {
    let reviews: [Review]
    let lastReviewDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review History")
                .font(.headline)
                .foregroundColor(.secondary)

            if reviews.isEmpty {
                Text("No reviews yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reviews, id: \.id) { review in
                        HStack {
                            if let author = review.author {
                                HStack(spacing: 4) {
                                    Image(systemName: review.state.icon)
                                        .font(.caption2)
                                        .foregroundColor(review.state.color)
                                    Text("@\(author.login)")
                                        .font(.caption)
                                }
                            }

                            Spacer()

                            if let submittedAt = review.submittedAt {
                                Text(DateFormatters.timeAgo(from: submittedAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if let lastDate = lastReviewDate {
                Divider()
                HStack {
                    Text("Your last review:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(DateFormatters.timeAgo(from: lastDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
