import SwiftUI

struct ReviewSubmissionPanel: View {
    @ObservedObject var commentViewModel: ReviewCommentViewModel
    let pr: EnrichedPullRequest
    @Environment(\.dismiss) private var dismiss
    @State private var reviewEvent: ReviewEvent = .comment
    @State private var reviewBody: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    enum ReviewEvent: String, CaseIterable {
        case approve = "APPROVE"
        case requestChanges = "REQUEST_CHANGES"
        case comment = "COMMENT"

        var displayName: String {
            switch self {
            case .approve: return "Approve"
            case .requestChanges: return "Request Changes"
            case .comment: return "Comment"
            }
        }

        var icon: String {
            switch self {
            case .approve: return "checkmark.circle.fill"
            case .requestChanges: return "xmark.circle.fill"
            case .comment: return "bubble.left.fill"
            }
        }

        var color: Color {
            switch self {
            case .approve: return .green
            case .requestChanges: return .red
            case .comment: return .blue
            }
        }
    }

    var hasDrafts: Bool {
        !commentViewModel.drafts.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Submit Review")
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

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Review event selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Review Action")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $reviewEvent) {
                            ForEach(ReviewEvent.allCases, id: \.self) { event in
                                HStack {
                                    Image(systemName: event.icon)
                                        .foregroundColor(event.color)
                                    Text(event.displayName)
                                }
                                .tag(event)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Review body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review Summary (Optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $reviewBody)
                            .frame(minHeight: 100, maxHeight: 200)
                            .font(.body)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }

                    // Draft comments list
                    if hasDrafts {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Draft Comments (\(commentViewModel.drafts.count))")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(commentViewModel.drafts) { draft in
                                    DraftCommentRow(
                                        draft: draft,
                                        onDelete: {
                                            commentViewModel.deleteDraft(draft)
                                        }
                                    )
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(20)
            }

            // Error banner
            if let errorMessage = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.body)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)

                Button(action: discardAllDrafts) {
                    Text("Discard All")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting || !hasDrafts)

                Button(action: submitReview) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 700)
    }

    private func discardAllDrafts() {
        commentViewModel.clearDrafts()
        dismiss()
    }

    private func submitReview() {
        Task {
            isSubmitting = true
            errorMessage = nil

            do {
                // Convert drafts to API format
                let commentsArray = commentViewModel.drafts.compactMap { draft -> [String: Any]? in
                    guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }

                    return [
                        "path": draft.filePath,
                        "line": draft.line,
                        "side": draft.side.rawValue,
                        "body": draft.body
                    ]
                }

                let commitId = pr.detail?.commits?.nodes.first?.commit.oid ?? ""

                // Submit review
                _ = try await GitHubService.shared.createPullRequestReview(
                    owner: pr.pr.repository.owner,
                    repo: pr.pr.repository.name,
                    number: pr.pr.number,
                    commitId: commitId,
                    event: reviewEvent.rawValue,
                    body: reviewBody,
                    comments: commentsArray
                )

                // Record review history for incremental diffs
                let prKey = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
                await ReviewHistoryService.shared.recordReview(
                    prKey: prKey,
                    commitId: commitId,
                    event: reviewEvent.rawValue
                )

                // Clear file view status after successful review
                await FileViewStatusService.shared.clearPR(prKey: prKey)

                // Clear drafts and dismiss
                commentViewModel.clearDrafts()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }
}

struct DraftCommentRow: View {
    let draft: CommentDraft
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Line \(draft.line) • \(draft.side.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.body.isEmpty ? "(empty)" : draft.body)
                    .font(.body)
                    .foregroundStyle(draft.body.isEmpty ? .secondary : .primary)
                    .lineLimit(2)

                if draft.isModified {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                        Text("Edited")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete draft")
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}
