import SwiftUI

struct PRListView: View {
    let prs: [EnrichedPullRequest]
    let currentUser: String?
    let isLoading: Bool
    let emptyMessage: String
    let isCompact: Bool

    @State private var selectedPR: EnrichedPullRequest?

    init(prs: [EnrichedPullRequest], currentUser: String? = nil, isLoading: Bool, emptyMessage: String, isCompact: Bool = true) {
        self.prs = prs
        self.currentUser = currentUser
        self.isLoading = isLoading
        self.emptyMessage = emptyMessage
        self.isCompact = isCompact
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && prs.isEmpty {
                loadingView
            } else if prs.isEmpty {
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
        SkeletonListView(count: 5)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await PRListViewModel.shared.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(prs) { pr in
                    PRRowView(
                        pr: pr,
                        isSelected: selectedPR?.id == pr.id,
                        isMyPR: pr.pr.author?.login == currentUser,
                        isCompact: isCompact
                    )
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

struct PRRowView: View {
    let pr: EnrichedPullRequest
    let isSelected: Bool
    let isMyPR: Bool
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                metadataRow
            }
            Spacer()
            reviewStatusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var statusIndicator: some View {
        Circle()
            .fill(pr.pr.isDraft ? Color.gray : Color.green)
            .frame(width: 8, height: 8)
            .padding(.top, 5)
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(pr.pr.title)
                .font(.system(.body, design: .default))
                .fontWeight(.medium)
                .lineLimit(1)
            if pr.pr.isDraft {
                Text("DRAFT")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if pr.detail?.hasConflicts == true {
                Text("CONFLICTS")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private var metadataRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let author = pr.pr.author {
                    Text(author.displayName)
                        .foregroundStyle(.secondary)
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(pr.pr.timeAgo)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(pr.pr.repository.shortName)
                    .foregroundStyle(.secondary)
            }
            if let head = pr.detail?.headRefName, let base = pr.detail?.baseRefName {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tertiary)
                    Text(head)
                        .foregroundStyle(.blue)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    Text(base)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    private var reviewStatusBadge: some View {
        Group {
            if let decision = pr.reviewDecision {
                HStack(spacing: 4) {
                    Image(systemName: decision.icon)
                    if !isCompact {
                        Text(decision.displayText)
                    }
                }
                .font(.caption)
                .foregroundColor(decision.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(decision.color.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }
}
