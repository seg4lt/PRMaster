import SwiftUI

struct PRDetailView: View {
    let pr: EnrichedPullRequest

    @State private var isSubmittingReview = false
    @State private var showRequestChangesInput = false
    @State private var requestChangesBody = ""
    @State private var isAddingReviewer = false

    private var currentUser: String? {
        PRListViewModel.shared.currentUser
    }

    /// True if the current user is the PR author (can't review own PR)
    private var isOwnPR: Bool {
        guard let user = currentUser else { return false }
        return pr.pr.author?.login.lowercased() == user.lowercased()
    }

    /// True if the current user is already a requested reviewer or has submitted a review
    private var isAlreadyReviewer: Bool {
        guard let user = currentUser?.lowercased() else { return false }
        let isRequested = pr.requestedReviewers.contains { $0.lowercased() == user }
        let hasReviewed = pr.reviews.contains { $0.author?.login.lowercased() == user }
        return isRequested || hasReviewed
    }

    /// True if user is a pending reviewer (requested but hasn't reviewed yet)
    private var isPendingReviewer: Bool {
        guard let user = currentUser?.lowercased() else { return false }
        return pr.pendingReviewers.contains { $0.lowercased() == user }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            reviewersSection
            Divider()
            checksSection
            Divider()
            if !isOwnPR {
                reviewActionsSection
                Divider()
            }
            actionsSection
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pr.pr.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Text(pr.pr.repository.nameWithOwner)
                    .foregroundStyle(.secondary)
                Text("#\(pr.pr.number)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if let author = pr.pr.author {
                HStack {
                    Text("Author:")
                        .foregroundStyle(.secondary)
                    Text(author.displayName)
                }
                .font(.caption)
            }

            HStack {
                Text("Created:")
                    .foregroundStyle(.secondary)
                Text(DateFormatters.fullDate(pr.pr.createdAt))
            }
            .font(.caption)

            if let decision = pr.reviewDecision {
                HStack(spacing: 4) {
                    Image(systemName: decision.icon)
                    Text(decision.displayText)
                }
                .foregroundColor(decision.color)
                .font(.caption)
            }

            if let status = pr.detail?.mergeableStatus {
                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                    Text(status.text)
                }
                .foregroundColor(status.color)
                .font(.caption)
            }
        }
    }

    private var reviewersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviewers")
                .font(.subheadline)
                .fontWeight(.medium)

            let reviewedAuthors = pr.latestReviewsByAuthor
            let pendingReviewers = pr.pendingReviewers

            if reviewedAuthors.isEmpty && pendingReviewers.isEmpty {
                Text("No reviewers assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    // Show reviewers who have reviewed (with their status)
                    ForEach(Array(reviewedAuthors.keys.sorted()), id: \.self) { author in
                        if let review = reviewedAuthors[author] {
                            ReviewerBadge(author: author, state: review.state)
                        }
                    }
                    // Show pending reviewers (waiting icon)
                    ForEach(pendingReviewers, id: \.self) { reviewer in
                        PendingReviewerBadge(author: reviewer)
                    }
                }
            }
        }
    }

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checks")
                .font(.subheadline)
                .fontWeight(.medium)

            if let checks = pr.detail?.statusCheckRollup?.contexts?.nodes, !checks.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(checks) { check in
                        CheckBadge(check: check)
                    }
                }
            } else {
                Text("No checks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                // Approve button
                Button {
                    isSubmittingReview = true
                    Task {
                        await PRListViewModel.shared.submitReview(for: pr, event: "APPROVE", body: nil)
                        isSubmittingReview = false
                    }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .disabled(isSubmittingReview)

                // Request Changes button
                Button {
                    showRequestChangesInput.toggle()
                } label: {
                    Label("Request Changes", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .disabled(isSubmittingReview)

                // Add me as reviewer button (only if not already reviewing)
                if !isAlreadyReviewer {
                    Button {
                        isAddingReviewer = true
                        Task {
                            await PRListViewModel.shared.addSelfAsReviewer(for: pr)
                            isAddingReviewer = false
                        }
                    } label: {
                        Label("Add Me as Reviewer", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAddingReviewer)
                }
            }

            if isSubmittingReview || isAddingReviewer {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(isAddingReviewer ? "Adding reviewer..." : "Submitting review...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showRequestChangesInput {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What changes are needed?")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $requestChangesBody)
                        .font(.subheadline)
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Button {
                            isSubmittingReview = true
                            let body = requestChangesBody
                            Task {
                                await PRListViewModel.shared.submitReview(
                                    for: pr,
                                    event: "REQUEST_CHANGES",
                                    body: body.isEmpty ? nil : body
                                )
                                isSubmittingReview = false
                                showRequestChangesInput = false
                                requestChangesBody = ""
                            }
                        } label: {
                            Text("Submit")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(isSubmittingReview)

                        Button {
                            showRequestChangesInput = false
                            requestChangesBody = ""
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                if let url = URL(string: pr.pr.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.pr.url, forType: .string)
            } label: {
                Label("Copy Link", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct CheckBadge: View {
    let check: CheckContext

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: check.icon)
                .foregroundColor(check.color)
            Text(check.badgeDisplayName)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(check.color.opacity(0.1))
        .clipShape(Capsule())
        .help(check.displayName)
        .onTapGesture {
            if let urlString = check.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct ReviewerBadge: View {
    let author: String
    let state: ReviewState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon)
                .foregroundColor(state.color)
            Text("@\(author)")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct PendingReviewerBadge: View {
    let author: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .foregroundColor(.orange)
            Text("@\(author)")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
