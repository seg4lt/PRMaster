import SwiftUI
import AppKit

struct ConversationListView: View {
    let groups: [ConversationGroup]
    let isLoading: Bool

    @State private var selectedConversation: ConversationItem?
    @FocusState private var isKeyboardFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && groups.isEmpty {
                loadingView
            } else if groups.isEmpty {
                emptyView
            } else {
                listView
            }

            if let selectedConversation {
                Divider()
                ConversationDetailView(conversation: selectedConversation)
            }
        }
        .focusable()
        .focused($isKeyboardFocused)
        .onAppear {
            isKeyboardFocused = true
        }
        .onChange(of: selectedConversation?.id) { _, _ in
            isKeyboardFocused = true
        }
        .onKeyPress(.escape) {
            guard selectedConversation != nil else { return .ignored }
            selectedConversation = nil
            return .handled
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading conversations...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No active conversations")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("You'll see mentions and unresolved threads you're part of here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    ConversationGroupSection(
                        group: group,
                        selectedConversationID: selectedConversation?.id,
                        onSelect: { conversation in
                            isKeyboardFocused = true
                            if selectedConversation?.id == conversation.id {
                                selectedConversation = nil
                            } else {
                                selectedConversation = conversation
                            }
                        }
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct ConversationGroupSection: View {
    let group: ConversationGroup
    let selectedConversationID: String?
    let onSelect: (ConversationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.prTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(group.repoNameWithOwner)
                    Text("#\(group.prNumber)")
                    Text("·")
                    Text("\(group.conversations.count) open")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ForEach(group.conversations) { conversation in
                Button {
                    onSelect(conversation)
                } label: {
                    ConversationRowView(
                        conversation: conversation,
                        isSelected: selectedConversationID == conversation.id
                    )
                }
                .buttonStyle(.plain)

                if conversation.id != group.conversations.last?.id {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ConversationRowView: View {
    let conversation: ConversationItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: conversation.kind == .reviewThread ? "arrowshape.turn.up.left.fill" : "at")
                .foregroundStyle(conversation.kind == .reviewThread ? .blue : .orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.kind.badgeLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(conversation.kind == .reviewThread ? .blue : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((conversation.kind == .reviewThread ? Color.blue : Color.orange).opacity(0.12))
                        .clipShape(Capsule())

                    if let locationText = conversation.locationText {
                        Text(locationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(conversation.previewText)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(conversation.latestAuthorLogin.map { "@\($0)" } ?? "Unknown")
                    Text("·")
                    Text(DateFormatters.timeAgo(from: conversation.latestActivityAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct ConversationDetailView: View {
    let conversation: ConversationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            if let locationText = conversation.locationText {
                Label(locationText, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            messagesSection
            Divider()
            actionsSection
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.prTitle)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(conversation.repoNameWithOwner)
                    .foregroundStyle(.secondary)
                Text("#\(conversation.prNumber)")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(conversation.kind.badgeLabel)
                    .foregroundStyle(conversation.kind == .reviewThread ? .blue : .orange)
            }
            .font(.caption)

            Text("Latest activity \(DateFormatters.fullDate(conversation.latestActivityAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var messagesSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(conversation.messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(message.authorDisplayName)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(DateFormatters.fullDate(message.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No message body" : message.body)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 260)
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                if let url = URL(string: conversation.exactURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in GitHub", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                if let url = URL(string: conversation.prURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open PR", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

