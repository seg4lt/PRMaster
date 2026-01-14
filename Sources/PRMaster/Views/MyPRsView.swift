import SwiftUI

struct MyPRsView: View {
    @ObservedObject var viewModel: PRListViewModel
    @State private var selectedPR: EnrichedPullRequest?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.myOpenPRs.isEmpty {
                loadingView
            } else if viewModel.myOpenPRs.isEmpty {
                emptyView
            } else {
                listView
            }

            if let selected = selectedPR {
                Divider()
                PRDetailView(pr: selected)
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No open PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.myOpenPRs) { pr in
                    MyPRRowView(pr: pr, isSelected: selectedPR?.id == pr.id)
                        .onTapGesture {
                            if selectedPR?.id == pr.id {
                                selectedPR = nil
                            } else {
                                selectedPR = pr
                            }
                        }
                }
            }
        }
    }
}

struct MyPRRowView: View {
    let pr: EnrichedPullRequest
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.pr.title)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(pr.pr.repository.shortName)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Created \(DateFormatters.shortDate(pr.pr.createdAt))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if !pr.reviews.isEmpty {
                    reviewSummaryView
                }
            }

            Spacer()

            if let decision = pr.reviewDecision {
                Image(systemName: decision.icon)
                    .foregroundColor(decision.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var reviewSummaryView: some View {
        HStack(spacing: 4) {
            // Show reviewers who have submitted reviews
            ForEach(Array(pr.latestReviewsByAuthor.keys.sorted().prefix(3)), id: \.self) { author in
                if let review = pr.latestReviewsByAuthor[author] {
                    HStack(spacing: 2) {
                        Image(systemName: review.state.icon)
                            .foregroundColor(review.state.color)
                        Text("@\(author)")
                    }
                    .font(.caption2)
                }
            }
            // Show pending reviewers
            ForEach(pr.pendingReviewers.prefix(2), id: \.self) { reviewer in
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                    Text("@\(reviewer)")
                }
                .font(.caption2)
            }
            let totalReviewers = pr.latestReviewsByAuthor.count + pr.pendingReviewers.count
            if totalReviewers > 5 {
                Text("+\(totalReviewers - 5)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
