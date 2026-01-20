import SwiftUI

struct InlineCommentView: View {
    let comments: [PullRequestReviewComment]
    let draft: CommentDraft?
    let onDraftBodyChange: (CommentDraft, String) -> Void
    let onDeleteDraft: (CommentDraft) -> Void
    let onEditComment: (PullRequestReviewComment) -> Void
    let onDeleteComment: (PullRequestReviewComment) -> Void
    let onReply: (PullRequestReviewComment, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Existing comments
            ForEach(comments) { comment in
                CommentBubbleView(
                    comment: comment,
                    onEdit: { onEditComment(comment) },
                    onDelete: { onDeleteComment(comment) },
                    onReply: { onReply(comment, $0) }
                )
            }

            // Draft comment
            if let draft = draft {
                CommentDraftView(
                    draft: draft,
                    onBodyChange: { onDraftBodyChange(draft, $0) },
                    onDelete: { onDeleteDraft(draft) }
                )
            }
        }
        .padding(.leading, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct CommentBubbleView: View {
    let comment: PullRequestReviewComment
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReply: (String) -> Void

    @State private var isExpanded: Bool = true
    @State private var isReplying: Bool = false
    @State private var replyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: comment.user.avatar_url ?? "")) { image in
                    image.resizable()
                } placeholder: {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.user.displayName)
                            .font(.system(.body, design: .default))
                            .fontWeight(.semibold)

                        Text(comment.updated_at, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                Spacer()

                Menu {
                    Button("Edit") {
                        onEdit()
                    }
                    .disabled(!comment.isMyComment)

                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    .disabled(!comment.isMyComment)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .menuStyle(.borderlessButton)
            }

            // Body
            Text(comment.displayBody)
                .font(.body)
                .textSelection(.enabled)
                .padding(.vertical, 4)

            // Reply section
            if isReplying {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $replyText)
                        .frame(minHeight: 60, maxHeight: 150)
                        .font(.body)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)

                    HStack(spacing: 8) {
                        Button("Reply") {
                            onReply(replyText)
                            replyText = ""
                            isReplying = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Cancel") {
                            replyText = ""
                            isReplying = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding(.top, 8)
            } else {
                Button(action: { isReplying = true }) {
                    Text("Reply")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct CommentDraftView: View {
    let draft: CommentDraft
    let onBodyChange: (String) -> Void
    let onDelete: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Draft comment")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete draft")
            }

            TextEditor(text: Binding(
                get: { draft.body },
                set: { onBodyChange($0) }
            ))
            .frame(minHeight: 80, maxHeight: 200)
            .font(.body)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}
