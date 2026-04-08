import SwiftUI
import AppKit

struct ConversationListView: View {
    let groups: [ConversationGroup]
    let isLoading: Bool
    let currentUser: String?

    @State private var selectedConversation: ConversationItem?
    @FocusState private var isKeyboardFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if isLoading && groups.isEmpty {
                    loadingView
                } else if groups.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }

            if let selectedConversation {
                Divider()
                ConversationDetailView(conversation: selectedConversation)
                    .frame(minWidth: 320, idealWidth: 400)
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

    private var needsReply: [ConversationItem] {
        group.conversations.filter(\.hasRepliesToCurrentUser)
    }

    private var otherConversations: [ConversationItem] {
        group.conversations.filter { !$0.hasRepliesToCurrentUser }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // PR header
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
                    if !needsReply.isEmpty {
                        Text("·")
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.backward.fill")
                                .font(.caption2)
                            Text("\(needsReply.count) awaiting reply")
                        }
                        .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // "Needs your reply" section
            if !needsReply.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text("Needs your reply")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ForEach(needsReply) { conversation in
                    conversationButton(conversation)
                    if conversation.id != needsReply.last?.id || !otherConversations.isEmpty {
                        Divider().padding(.leading, 12)
                    }
                }
            }

            // Other threads section
            if !otherConversations.isEmpty {
                if !needsReply.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                        Text("Other threads")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                ForEach(otherConversations) { conversation in
                    conversationButton(conversation)
                    if conversation.id != otherConversations.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func conversationButton(_ conversation: ConversationItem) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            ConversationRowView(
                conversation: conversation,
                isSelected: selectedConversationID == conversation.id
            )
        }
        .buttonStyle(.plain)
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

                    if conversation.hasRepliesToCurrentUser {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.backward.fill")
                                .font(.system(size: 8))
                            Text("Replied to you")
                        }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                    }

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

                    if conversation.replyCount > 0 {
                        Text("·")
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 9))
                            Text("\(conversation.replyCount)")
                        }
                        .foregroundStyle(conversation.hasRepliesToCurrentUser ? .red : .secondary)
                    }
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

// MARK: - Conversation Detail

private struct ConversationDetailView: View {
    let conversation: ConversationItem

    @State private var showFullThread = false

    private var userMessages: [ConversationMessage] {
        conversation.messages.filter { conversation.isCurrentUser($0.authorLogin) }
    }

    private var otherMessageCount: Int {
        conversation.messages.count - userMessages.count
    }

    private var visibleMessages: [(index: Int, message: ConversationMessage)] {
        if showFullThread {
            return conversation.messages.enumerated().map { ($0.offset, $0.element) }
        }
        // Show only the current user's messages (with their original indices for positioning)
        return conversation.messages.enumerated().compactMap { index, msg in
            conversation.isCurrentUser(msg.authorLogin) ? (index, msg) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            if let locationText = conversation.locationText {
                Label(locationText, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            threadToggle
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

    private var threadToggle: some View {
        HStack(spacing: 6) {
            if showFullThread {
                Text("All messages (\(conversation.messages.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your comments (\(userMessages.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                if otherMessageCount > 0 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(otherMessageCount) other \(otherMessageCount == 1 ? "reply" : "replies") hidden")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if conversation.messages.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullThread.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showFullThread ? "person.fill" : "bubble.left.and.bubble.right")
                            .font(.system(size: 9))
                        Text(showFullThread ? "My comments" : "Full thread")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var messagesSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleMessages, id: \.message.id) { index, message in
                    let isFirst = index == 0
                    let isFromCurrentUser = conversation.isCurrentUser(message.authorLogin)

                    ThreadMessageView(
                        message: message,
                        isFirst: isFirst,
                        isFromCurrentUser: isFromCurrentUser
                    )
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 300)
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

// MARK: - Thread Message

private struct ThreadMessageView: View {
    let message: ConversationMessage
    let isFirst: Bool
    let isFromCurrentUser: Bool

    private var bubbleBackground: Color {
        if isFromCurrentUser {
            return Color.accentColor.opacity(0.10)
        }
        return Color.primary.opacity(0.04)
    }

    private var accentBorderColor: Color {
        if isFromCurrentUser {
            return .accentColor
        }
        return Color.primary.opacity(0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                // Reply connector
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2, height: 10)
                        .padding(.leading, 14)
                    Spacer()
                }
            }

            HStack(alignment: .top, spacing: 0) {
                if !isFirst {
                    // Left accent border for replies
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accentBorderColor)
                        .frame(width: 3)
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isFirst {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Text(message.authorDisplayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(isFromCurrentUser ? Color.accentColor : Color.primary)

                        if isFromCurrentUser {
                            Text("you")
                                .font(.system(size: 9))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(DateFormatters.timeAgo(from: message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "No message body"
                         : message.body)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, isFirst ? 0 : 0)
            }
        }
    }
}

