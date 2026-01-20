import SwiftUI

enum DiffLineType {
    case added
    case removed
    case context
    case header
}

struct DiffLine {
    let content: String
    let type: DiffLineType
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let filePath: String
    let commitId: String?

    init(content: String, oldLineNumber: Int? = nil, newLineNumber: Int? = nil, filePath: String = "", commitId: String? = nil) {
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.filePath = filePath
        self.commitId = commitId

        if content.hasPrefix("+") && !content.hasPrefix("+++") {
            type = .added
        } else if content.hasPrefix("-") && !content.hasPrefix("---") {
            type = .removed
        } else if content.hasPrefix("@@") {
            type = .header
        } else {
            type = .context
        }
    }
}

@MainActor
class PRDiffViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var files: [ChangedFile] = []
    @Published var commentViewModel: ReviewCommentViewModel

    private let pr: EnrichedPullRequest

    init(pr: EnrichedPullRequest) {
        self.pr = pr
        self.commentViewModel = ReviewCommentViewModel(pr: pr, filePaths: [])
    }

    func updateCommentFilePaths() {
        let filePaths = files.map { $0.path }
        commentViewModel = ReviewCommentViewModel(pr: pr, filePaths: filePaths)
    }

    func loadDiff() async {
        isLoading = true
        error = nil

        do {
            // Step 1: Fetch file metadata via GraphQL
            let detail = try await GitHubService.shared.fetchPRDiff(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )

            var files = detail?.files?.nodes ?? []

            // Step 2: Fetch full diff via REST API
            let diffRaw = try await GitHubService.shared.fetchPRDiffRaw(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )

            // Step 3: Parse diff and associate with files
            let parsedPatches = parseUnifiedDiff(diffRaw)

            // Step 4: Match patches with files by path
            for index in files.indices {
                if let patch = parsedPatches[files[index].path] {
                    files[index].patch = patch
                }
            }

            self.files = files

            // Step 5: Load comments
            updateCommentFilePaths()
            await commentViewModel.loadComments()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func parseUnifiedDiff(_ diff: String) -> [String: String] {
        var patches: [String: String] = [:]
        let sections = diff.components(separatedBy: "diff --git ")

        for section in sections {
            guard !section.isEmpty else { continue }

            // Extract file path from +++ b/path line
            let lines = section.components(separatedBy: "\n")
            var filePath: String?

            for line in lines {
                if line.hasPrefix("+++") {
                    // Format: +++ b/path/to/file
                    let parts = line.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        var path = String(parts[1])
                        if path.hasPrefix("b/") {
                            path = String(path.dropFirst(2))
                        }
                        filePath = path
                    }
                    break
                }
            }

            if let path = filePath {
                patches[path] = "diff --git " + section
            }
        }

        return patches
    }
}

struct PRDiffView: View {
    let pr: EnrichedPullRequest
    @StateObject private var viewModel: PRDiffViewModel
    @State private var expandedFiles = Set<String>()
    @State private var showReviewPanel: Bool = false

    init(pr: EnrichedPullRequest) {
        self.pr = pr
        self._viewModel = StateObject(wrappedValue: PRDiffViewModel(pr: pr))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if viewModel.isLoading {
                loadingView
        } else if let error = viewModel.error {
            errorView
        } else if viewModel.files.isEmpty {
                emptyView
            } else {
                diffFilesList
            }
        }
        .task {
            if viewModel.files.isEmpty && !viewModel.isLoading {
                await viewModel.loadDiff()
            }
        }
        .sheet(isPresented: $showReviewPanel) {
            ReviewSubmissionPanel(
                commentViewModel: viewModel.commentViewModel,
                pr: pr
            )
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.pr.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(pr.pr.repository.nameWithOwner)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("#\(pr.pr.number)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Spacer()

            if !viewModel.isLoading && !viewModel.files.isEmpty {
                HStack(spacing: 12) {
                    if !viewModel.commentViewModel.drafts.isEmpty {
                        Button(action: { showReviewPanel = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.caption)
                                Text("Submit Review")
                                    .font(.body)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading diff...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 48))
            Text("Failed to load diff")
                .font(.headline)
            Text(viewModel.error ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await viewModel.loadDiff()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No files changed")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diffFilesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.files) { file in
                    FileDiffView(
                        file: file,
                        isExpanded: expandedFiles.contains(file.id),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedFiles.contains(file.id) {
                                    expandedFiles.remove(file.id)
                                } else {
                                    expandedFiles.insert(file.id)
                                }
                            }
                        },
                        commitId: nil,
                        pr: pr,
                        commentViewModel: viewModel.commentViewModel
                    )
                }
            }
        }
    }
}

struct FileDiffView: View {
    let file: ChangedFile
    let isExpanded: Bool
    let onToggle: () -> Void
    var commitId: String? = nil
    let pr: EnrichedPullRequest
    @ObservedObject var commentViewModel: ReviewCommentViewModel

    private var fileName: String {
        (file.path as NSString).lastPathComponent
    }

    private var directory: String {
        (file.path as NSString).deletingLastPathComponent
    }

    private var isLockFile: Bool {
        let lockFilePatterns = [
            "package-lock.json",
            "yarn.lock",
            "pnpm-lock.yaml",
            "Gemfile.lock",
            "Cargo.lock",
            "poetry.lock",
            "Podfile.lock",
            "composer.lock",
            "go.sum",
            "flake.lock"
        ]
        return lockFilePatterns.contains { file.path.contains($0) }
    }

    private var isBinaryFile: Bool {
        file.patch == nil && ((file.additions ?? 0) + (file.deletions ?? 0)) > 0
    }

    private var changeIcon: String {
        switch file.changeType {
        case "ADDED": return "plus"
        case "DELETED": return "minus"
        case "RENAMED": return "arrow.right"
        case "COPIED": return "doc.on.doc"
        default: return "pencil"
        }
    }

    private var changeColor: Color {
        switch file.changeType {
        case "ADDED": return .green
        case "DELETED": return .red
        case "RENAMED": return .blue
        case "COPIED": return .blue
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader

            if isExpanded {
                Divider()

                if isLockFile {
                    lockFileWarning
                } else if isBinaryFile {
                    binaryFileWarning
                } else if let patch = file.patch {
                    InlineDiffView(
                        patch: patch,
                        filePath: file.path,
                        commitId: commitId,
                        pr: pr,
                        commentViewModel: commentViewModel
                    )
                }
            }
        }
    }

    private var fileHeader: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: changeIcon)
                    .font(.caption)
                    .foregroundColor(changeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    if !directory.isEmpty && directory != "." {
                        Text(directory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let additions = file.additions, let deletions = file.deletions {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text("+\(additions)")
                                .foregroundColor(.green)
                        }
                        .font(.caption)

                        HStack(spacing: 2) {
                            Text("-\(deletions)")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isExpanded ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .buttonStyle(.plain)
        }
        .buttonStyle(.plain)
    }

    private var lockFileWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundColor(.orange)
            Text("Lock file - changes not displayed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var binaryFileWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .foregroundColor(.orange)
            Text("Binary file - cannot display diff")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct InlineDiffView: View {
    let patch: String
    let filePath: String
    let commitId: String?
    let pr: EnrichedPullRequest
    @ObservedObject var commentViewModel: ReviewCommentViewModel
    @State private var expandedCommentLines = Set<String>()

    private var diffLines: [DiffLine] {
        parseDiffWithLineNumbers(patch)
    }

    private func lineIdentifier(_ line: DiffLine) -> String {
        let side: CommentSide = line.type == .removed ? .left : .right
        return "\(line.filePath)-\(line.oldLineNumber ?? line.newLineNumber ?? 0)-\(side.rawValue)"
    }

    private func parseDiffWithLineNumbers(_ patch: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        let patchLines = patch.components(separatedBy: "\n")

        var oldLineNum: Int = 1
        var newLineNum: Int = 1
        var skipUntilNextHunk = false

        for line in patchLines {
            // Skip meta lines
            if line.hasPrefix("diff --git") {
                skipUntilNextHunk = true
                continue
            }
            if line.hasPrefix("index ") {
                continue
            }
            if line.hasPrefix("--- ") {
                continue
            }
            if line.hasPrefix("+++ ") {
                continue
            }

            // Parse hunk header to get line numbers
            if line.hasPrefix("@@ ") {
                skipUntilNextHunk = false

                // Extract: @@ -oldStart,oldCount +newStart,newCount @@ optional_section
                let range = line.dropFirst(3)
                let components = range.components(separatedBy: " ")
                var oldStart = oldLineNum
                var newStart = newLineNum

                for component in components {
                    if component.hasPrefix("-") {
                        // Format: -start,count
                        let numStr = component.dropFirst().components(separatedBy: ",")
                        if let start = Int(numStr[0]) {
                            oldStart = start
                        }
                    } else if component.hasPrefix("+") {
                        // Format: +start,count
                        let numStr = component.dropFirst().components(separatedBy: ",")
                        if let start = Int(numStr[0]) {
                            newStart = start
                        }
                    } else if component.hasPrefix("@@") {
                        break
                    }
                }

                oldLineNum = oldStart
                newLineNum = newStart

                // Don't add hunk header to display
                continue
            }

            // Skip everything until we hit the first hunk
            if skipUntilNextHunk {
                continue
            }

            // Process diff lines and track line numbers
            var oldNum: Int?
            var newNum: Int?

            if line.hasPrefix("-") {
                oldNum = oldLineNum
                oldLineNum += 1
            } else if line.hasPrefix("+") {
                newNum = newLineNum
                newLineNum += 1
            } else {
                // Context line
                oldNum = oldLineNum
                newNum = newLineNum
                oldLineNum += 1
                newLineNum += 1
            }

            lines.append(DiffLine(content: line, oldLineNumber: oldNum, newLineNumber: newNum, filePath: filePath, commitId: commitId))
        }

        return lines
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                    let side: CommentSide = line.type == .removed ? .left : .right
                    let lineNumber = line.type == .removed ? line.oldLineNumber : line.newLineNumber
                    let comments = commentViewModel.getCommentsForLine(
                        filePath: filePath,
                        line: lineNumber ?? 0,
                        side: side
                    )
                    let draft = commentViewModel.getDraftForLine(
                        filePath: filePath,
                        line: lineNumber ?? 0,
                        side: side
                    )
                    let hasComments = !comments.isEmpty || draft != nil

                    VStack(alignment: .leading, spacing: 0) {
                    DiffLineView(
                        line: line,
                        commentCount: comments.count,
                        onCommentToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                let identifier = lineIdentifier(line)
                                if expandedCommentLines.contains(identifier) {
                                    expandedCommentLines.remove(identifier)
                                } else {
                                    expandedCommentLines.insert(identifier)
                                }
                            }
                        }
                    )

                    if hasComments && expandedCommentLines.contains(lineIdentifier(line)) {
                        Divider()
                        InlineCommentView(
                            comments: comments,
                            draft: draft,
                            onDraftBodyChange: { commentViewModel.updateDraft($0, body: $1) },
                            onDeleteDraft: { commentViewModel.deleteDraft($0) },
                            onEditComment: { _ in
                                // TODO: Implement comment editing
                            },
                            onDeleteComment: { comment in
                                Task {
                                    try await GitHubService.shared.deleteReviewComment(
                                        owner: pr.pr.repository.owner,
                                        repo: pr.pr.repository.name,
                                        commentId: comment.id
                                    )
                                    await commentViewModel.loadComments()
                                }
                            },
                            onReply: { _, _ in
                                // TODO: Implement comment replies
                            }
                        )
                    }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct DiffLineView: View {
    let line: DiffLine
    let commentCount: Int
    let onCommentToggle: () -> Void

    init(line: DiffLine, commentCount: Int = 0, onCommentToggle: @escaping () -> Void = {}) {
        self.line = line
        self.commentCount = commentCount
        self.onCommentToggle = onCommentToggle
    }

    private var backgroundColor: Color? {
        switch line.type {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        case .header: return Color.blue.opacity(0.08)
        case .context: return nil
        }
    }

    private var foregroundColor: Color {
        switch line.type {
        case .added: return Color(red: 0.13, green: 0.6, blue: 0.18)
        case .removed: return Color(red: 0.84, green: 0.26, blue: 0.26)
        case .header: return .blue
        case .context: return .primary
        }
    }

    private var displayContent: String {
        if line.type == .added {
            String(line.content.dropFirst())
        } else if line.type == .removed {
            String(line.content.dropFirst())
        } else {
            line.content
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number gutter
            HStack(spacing: 8) {
                // Old line number
                Text(line.oldLineNumber.map(String.init) ?? "")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
                    .font(.system(.caption2, design: .monospaced))

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)

                // New line number
                Text(line.newLineNumber.map(String.init) ?? "")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
                    .font(.system(.caption2, design: .monospaced))

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(height: 24)
            .background(Color(NSColor.textBackgroundColor))

            // Comment indicator
            if commentCount > 0 {
                Button(action: onCommentToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                        Text("\(commentCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("\(commentCount) comment\(commentCount == 1 ? "" : "s")")
            } else {
                Button(action: onCommentToggle) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Add comment")
            }

            // Diff content
            HStack(alignment: .top, spacing: 8) {
                if let bgColor = backgroundColor {
                    Rectangle()
                        .fill(bgColor)
                        .frame(width: 3)
                }

                Text(displayContent)
                    .foregroundColor(foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(backgroundColor ?? Color.clear)
        }
        .frame(height: line.type == .context ? 24 : nil)
    }
}
