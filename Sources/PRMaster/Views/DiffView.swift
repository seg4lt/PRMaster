import SwiftUI
import Foundation

private struct ViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    @Published var isInitialLoad = true
    @Published var error: String?
    @Published var files: [ChangedFile] = []
    @Published var commentViewModel: ReviewCommentViewModel
    @Published var fileViewStatuses: [String: FileViewStatus] = [:]
    @Published var showIncrementalDiff = false

    private var parsedDiffLinesCache: [String: [DiffLine]] = [:]
    private var viewStartTimes: [String: Date] = [:]

    private let pr: EnrichedPullRequest
    private let prKey: String
    var reviewHistory: ReviewSubmissionHistory?  // Make accessible to view

    init(pr: EnrichedPullRequest) {
        self.pr = pr
        self.prKey = "\(pr.pr.repository.nameWithOwner)#\(pr.pr.number)"
        self.commentViewModel = ReviewCommentViewModel(pr: pr, filePaths: [])

        // Load review history
        Task {
            let history = await ReviewHistoryService.shared.getHistory(prKey: prKey)
            await MainActor.run {
                self.reviewHistory = history
                self.showIncrementalDiff = history.lastReviewCommit != nil
            }
        }
    }

    func updateCommentFilePaths() {
        let filePaths = files.map { $0.path }
        commentViewModel = ReviewCommentViewModel(pr: pr, filePaths: filePaths)

        // Update file view statuses
        Task {
            let statuses = await FileViewStatusService.shared.getStatusForPR(prKey: prKey, filePaths: filePaths)
            await MainActor.run {
                self.fileViewStatuses = statuses
            }
        }
    }

    /// Mark a file as viewed
    func markFileAsViewed(filePath: String) {
        Task {
            // Calculate view duration
            var duration: TimeInterval? = nil
            if let startTime = viewStartTimes[filePath] {
                duration = Date().timeIntervalSince(startTime)
                viewStartTimes.removeValue(forKey: filePath)
            }

            await FileViewStatusService.shared.markAsViewed(prKey: prKey, filePath: filePath, duration: duration)

            // Update local cache
            if var status = fileViewStatuses[filePath] {
                status.isViewed = true
                status.viewedAt = Date()
                status.viewDuration = duration
                fileViewStatuses[filePath] = status
            }
        }
    }

    /// Mark a file as unviewed
    func markFileAsUnviewed(filePath: String) {
        Task {
            await FileViewStatusService.shared.markAsUnviewed(prKey: prKey, filePath: filePath)

            // Update local cache
            if var status = fileViewStatuses[filePath] {
                status.isViewed = false
                status.viewedAt = nil
                status.viewDuration = nil
                fileViewStatuses[filePath] = status
            }
        }
    }

    /// Track when user starts viewing a file
    func trackFileViewStart(filePath: String) {
        viewStartTimes[filePath] = Date()
    }

    /// Get review progress
    var reviewProgress: (viewed: Int, total: Int) {
        let viewedCount = fileViewStatuses.values.filter { $0.isViewed }.count
        return (viewedCount, fileViewStatuses.count)
    }

    /// Check if user has previously reviewed this PR
    var hasPreviousReview: Bool {
        reviewHistory?.lastReviewCommit != nil
    }

    /// Toggle incremental diff mode
    func toggleIncrementalDiff() {
        showIncrementalDiff.toggle()
    }

    func getDiffLines(for file: ChangedFile) -> [DiffLine] {
        parsedDiffLinesCache[file.path] ?? []
    }

    private func rebuildParsedDiffLinesCache(from files: [ChangedFile]) {
        var newCache: [String: [DiffLine]] = [:]
        for file in files {
            guard let patch = file.patch else { continue }
            newCache[file.path] = parseDiffWithLineNumbers(patch, filePath: file.path)
        }
        parsedDiffLinesCache = newCache
    }

    func loadDiff() async {
        print("[PRMaster] Starting diff load for PR \(pr.pr.repository.nameWithOwner)#\(pr.pr.number)")
        isLoading = true
        error = nil
        parsedDiffLinesCache.removeAll()

        let startTime = Date()

        do {
            // Check if we should load incremental diff
            let loadIncremental = showIncrementalDiff && reviewHistory?.lastReviewCommit != nil
            let cacheKey = loadIncremental ? "\(pr.pr.id)-incremental" : pr.pr.id

            // Step 0: Try cache (skip network + parsing)
            if let cachedFiles = await DiffCacheService.shared.loadDiff(for: pr) {
                print("[PRMaster] ✓ Using cached diff for \(pr.pr.repository.nameWithOwner)#\(pr.pr.number) (\(cachedFiles.count) files)")
                self.files = cachedFiles
                rebuildParsedDiffLinesCache(from: cachedFiles)

                print("[PRMaster] Step 1: Loading comments...")
                updateCommentFilePaths()
                await commentViewModel.loadComments()
                print("[PRMaster] ✓ Comments loaded")

                isLoading = false
                isInitialLoad = false

                // Load comments in background
                Task {
                    updateCommentFilePaths()
                    await commentViewModel.loadComments()
                }

                return
            }

            // Step 1: Fetch file metadata via GraphQL
            print("[PRMaster] Step 1: Fetching file metadata...")
            let metadataStart = Date()
            let detail = try await GitHubService.shared.fetchPRDiff(
                owner: pr.pr.repository.owner,
                repo: pr.pr.repository.name,
                number: pr.pr.number
            )
            let metadataTime = Date().timeIntervalSince(metadataStart)
            print("[PRMaster] ✓ Metadata fetched in \(String(format: "%.2f", metadataTime))s")

            var files = detail?.files?.nodes ?? []
            print("[PRMaster] Found \(files.count) files")

            // Step 2: Fetch diff (full or incremental)
            print("[PRMaster] Step 2: Fetching diff content...")
            let diffStart = Date()

            let diffRaw: String
            if loadIncremental, let sinceCommit = reviewHistory?.lastReviewCommit {
                print("[PRMaster] Loading incremental diff since commit: \(sinceCommit.prefix(7))")
                diffRaw = try await GitHubService.shared.fetchPRIncrementalDiff(
                    owner: pr.pr.repository.owner,
                    repo: pr.pr.repository.name,
                    number: pr.pr.number,
                    sinceCommit: sinceCommit
                )
            } else {
                print("[PRMaster] Loading full diff")
                diffRaw = try await GitHubService.shared.fetchPRDiffRaw(
                    owner: pr.pr.repository.owner,
                    repo: pr.pr.repository.name,
                    number: pr.pr.number
                )
            }

            let diffTime = Date().timeIntervalSince(diffStart)
            print("[PRMaster] ✓ Diff fetched in \(String(format: "%.2f", diffTime))s (\(diffRaw.count) bytes)")

            // Step 3: Parse diff and associate with files
            print("[PRMaster] Step 3: Parsing diff...")
            let parseStart = Date()
            let parsedPatches = parseUnifiedDiff(diffRaw)

            // Step 4: Match patches with files by path
            for index in files.indices {
                if let patch = parsedPatches[files[index].path] {
                    files[index].patch = patch
                }
            }
            let parseTime = Date().timeIntervalSince(parseStart)
            print("[PRMaster] ✓ Diff parsed in \(String(format: "%.2f", parseTime))s")

            self.files = files
            rebuildParsedDiffLinesCache(from: files)

            // Only cache full diffs, not incremental ones
            if !loadIncremental {
                await DiffCacheService.shared.saveDiff(for: pr, files: files)
            }

            print("[PRMaster] ✓ Updated files array with \(files.count) files")

            // Step 5: Load comments
            print("[PRMaster] Step 4: Loading comments...")
            updateCommentFilePaths()
            await commentViewModel.loadComments()
            print("[PRMaster] ✓ Comments loaded")

            // Performance logging
            let totalTime = Date().timeIntervalSince(startTime)
            print("[PRMaster] ✅ Diff Load Complete: metadata=\(String(format: "%.2f", metadataTime))s, diff=\(String(format: "%.2f", diffTime))s, parse=\(String(format: "%.2f", parseTime))s, total=\(String(format: "%.2f", totalTime))s")
        } catch {
            print("[PRMaster] ❌ Error loading diff: \(error)")
            self.error = error.localizedDescription
        }

        isLoading = false
        isInitialLoad = false
        print("[PRMaster] Loading state: isLoading=\(isLoading), isInitialLoad=\(isInitialLoad), files.count=\(files.count), error=\(error?.description ?? "none")")
    }

    func parseDiffWithLineNumbers(_ patch: String, filePath: String) -> [DiffLine] {
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

            // Skip everything until we hit first hunk
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

            lines.append(DiffLine(content: line, oldLineNumber: oldNum, newLineNumber: newNum, filePath: filePath, commitId: nil))
        }

        return lines
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
    @State private var hasRequestedPreview: Bool = false
    @State private var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "diffFontSize")
        }
    }
    @State private var showViewedFilesSection: Bool = false  // Start collapsed

    init(pr: EnrichedPullRequest) {
        self.pr = pr
        self._viewModel = StateObject(wrappedValue: PRDiffViewModel(pr: pr))
        self._fontSize = State(initialValue: UserDefaults.standard.object(forKey: "diffFontSize") as? CGFloat ?? 13.0)
    }

    private var viewedFiles: [ChangedFile] {
        viewModel.files.filter { file in
            viewModel.fileViewStatuses[file.path]?.isViewed == true
        }
    }

    private var unviewedFiles: [ChangedFile] {
        viewModel.files.filter { file in
            viewModel.fileViewStatuses[file.path]?.isViewed != true
        }
    }

    private func increaseFontSize() {
        fontSize = min(fontSize + 1, 30)
    }

    private func decreaseFontSize() {
        fontSize = max(fontSize - 1, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if !hasRequestedPreview {
                previewPromptView
            } else if viewModel.isInitialLoad && viewModel.isLoading {
                skeletonDiffView
            } else if viewModel.error != nil {
                errorView
            } else if viewModel.files.isEmpty {
                emptyView
            } else if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                    Text("Loading details...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                diffFilesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showReviewPanel) {
            ReviewSubmissionPanel(
                commentViewModel: viewModel.commentViewModel,
                pr: pr
            )
        }
        .onAppear {
            // Setup keyboard monitoring for marking files as viewed
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard hasRequestedPreview && !viewModel.isLoading && !viewModel.files.isEmpty else {
                    return event
                }

                // Cmd+Shift+V: Mark first unviewed file as viewed
                if event.modifierFlags.contains(.command) &&
                   event.modifierFlags.contains(.shift) &&
                   event.charactersIgnoringModifiers == "v" {
                    if let firstUnviewed = unviewedFiles.first {
                        viewModel.markFileAsViewed(filePath: firstUnviewed.path)
                    }
                    return nil
                }

                // 'v': Mark currently expanded file as viewed
                if event.charactersIgnoringModifiers == "v" &&
                   !event.modifierFlags.contains(.command) &&
                   !event.modifierFlags.contains(.control) {
                    // Find currently expanded file
                    for file in viewModel.files {
                        if expandedFiles.contains(file.id) {
                            viewModel.markFileAsViewed(filePath: file.path)
                            withAnimation {
                                expandedFiles.remove(file.id)
                            }
                            break
                        }
                    }
                    return nil
                }

                // Arrow keys for navigation between files
                if !event.modifierFlags.contains(.command) &&
                   !event.modifierFlags.contains(.control) &&
                   !event.modifierFlags.contains(.option) {

                    let allFiles = viewModel.files
                    guard let currentIndex = allFiles.firstIndex(where: { expandedFiles.contains($0.id) }) else {
                        return event
                    }

                    switch event.charactersIgnoringModifiers {
                    case "j":
                        // Move to next file and expand it
                        if currentIndex < allFiles.count - 1 {
                            withAnimation {
                                expandedFiles.remove(allFiles[currentIndex].id)
                                expandedFiles.insert(allFiles[currentIndex + 1].id)
                                viewModel.trackFileViewStart(filePath: allFiles[currentIndex + 1].path)
                            }
                        }
                        return nil

                    case "k":
                        // Move to previous file and expand it
                        if currentIndex > 0 {
                            withAnimation {
                                expandedFiles.remove(allFiles[currentIndex].id)
                                expandedFiles.insert(allFiles[currentIndex - 1].id)
                                viewModel.trackFileViewStart(filePath: allFiles[currentIndex - 1].path)
                            }
                        }
                        return nil

                    case " ":
                        // Toggle current file expansion
                        withAnimation {
                            if expandedFiles.contains(allFiles[currentIndex].id) {
                                expandedFiles.remove(allFiles[currentIndex].id)
                            } else {
                                expandedFiles.insert(allFiles[currentIndex].id)
                                viewModel.trackFileViewStart(filePath: allFiles[currentIndex].path)
                            }
                        }
                        return nil

                    default:
                        return event
                    }
                }

                return event
            }
        }
    }

    private func startPreview() {
        guard !viewModel.isLoading else { return }
        hasRequestedPreview = true
        Task {
            await viewModel.loadDiff()
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

                    // Review progress indicator
                    if !viewModel.files.isEmpty {
                        let progress = viewModel.reviewProgress
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                            Text("\(progress.viewed)/\(progress.total)")
                                .font(.caption2)
                        }
                        .foregroundStyle(progress.viewed == progress.total ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((progress.viewed == progress.total ? Color.green : Color.secondary).opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }

            Spacer()

            if !hasRequestedPreview {
                Button(action: startPreview) {
                    Label("Preview PR", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isLoading)
            } else if !viewModel.isLoading && !viewModel.files.isEmpty {
                HStack(spacing: 12) {
                    // Incremental diff toggle
                    if viewModel.hasPreviousReview {
                        Button(action: { viewModel.toggleIncrementalDiff() }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.showIncrementalDiff ? "clock.fill" : "clock")
                                    .font(.caption)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.showIncrementalDiff ? "New Changes" : "All Changes")
                                        .font(.caption)
                                        .fontWeight(.medium)

                                    if viewModel.showIncrementalDiff, let lastReviewDate = viewModel.reviewHistory?.lastReviewAt {
                                        Text("Since \(DateFormatters.timeAgo(from: lastReviewDate))")
                                            .font(.caption2)
                                    }
                                }

                                if viewModel.showIncrementalDiff {
                                    Image(systemName: "circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .foregroundStyle(viewModel.showIncrementalDiff ? .blue : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.showIncrementalDiff ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle between full diff and changes since your last review")
                    }

                    HStack(spacing: 4) {
                        Button(action: decreaseFontSize) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("-", modifiers: .command)
                        .help("Decrease font size (Cmd+-)")

                        Text(String(format: "%.0f", fontSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)

                        Button(action: increaseFontSize) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("=", modifiers: .command)
                        .help("Increase font size (Cmd+=)")
                    }

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

                    Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var previewPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Preview required")
                .font(.headline)

            Text("Click Preview PR to load the diff and comments. Cached diffs will open instantly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(action: startPreview) {
                Label("Preview PR", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

    private var skeletonDiffView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonDiffFileRow()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
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
                hasRequestedPreview = true
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
                // Unviewed files section
                if !unviewedFiles.isEmpty {
                    sectionHeader(title: "Unviewed Files", count: unviewedFiles.count, icon: "circle", color: .orange)

                    ForEach(unviewedFiles) { file in
                        FileDiffView(
                            file: file,
                            isExpanded: expandedFiles.contains(file.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedFiles.contains(file.id) {
                                        expandedFiles.remove(file.id)
                                    } else {
                                        expandedFiles.insert(file.id)
                                        viewModel.trackFileViewStart(filePath: file.path)
                                    }
                                }
                            },
                            onViewed: {
                                viewModel.markFileAsViewed(filePath: file.path)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedFiles.remove(file.id)
                                }
                            },
                            commitId: nil,
                            pr: pr,
                            fontSize: fontSize,
                            diffViewModel: viewModel,
                            commentViewModel: viewModel.commentViewModel
                        )
                    }
                }

                // Viewed files section
                if !viewedFiles.isEmpty {
                    sectionHeader(
                        title: "Viewed Files",
                        count: viewedFiles.count,
                        icon: "checkmark.circle.fill",
                        color: .green,
                        isExpanded: $showViewedFilesSection
                    )

                    if showViewedFilesSection {
                        ForEach(viewedFiles) { file in
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
                                onViewed: {
                                    viewModel.markFileAsUnviewed(filePath: file.path)
                                },
                                commitId: nil,
                                pr: pr,
                                fontSize: fontSize,
                                diffViewModel: viewModel,
                                commentViewModel: viewModel.commentViewModel
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(title: String, count: Int, icon: String, color: Color, isExpanded: Binding<Bool>? = nil) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if let isExpanded = isExpanded {
                    isExpanded.wrappedValue.toggle()
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let isExpanded = isExpanded {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}

struct FileDiffView: View {
    let file: ChangedFile
    let isExpanded: Bool
    let onToggle: () -> Void
    let onViewed: () -> Void
    var commitId: String? = nil
    let pr: EnrichedPullRequest
    let fontSize: CGFloat
    @ObservedObject var diffViewModel: PRDiffViewModel
    @ObservedObject var commentViewModel: ReviewCommentViewModel

    private var fileName: String {
        (file.path as NSString).lastPathComponent
    }

    private var directory: String {
        (file.path as NSString).deletingLastPathComponent
    }

    private var isViewed: Bool {
        diffViewModel.fileViewStatuses[file.path]?.isViewed == true
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
                } else if file.patch != nil {
                    InlineDiffView(
                        file: file,
                        commitId: commitId,
                        pr: pr,
                        fontSize: fontSize,
                        diffViewModel: diffViewModel,
                        commentViewModel: commentViewModel
                    )
                }
            }
        }
    }

    private var fileHeader: some View {
        HStack(spacing: 0) {
            // Main file header button
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // View status indicator
                    if isViewed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

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
            }
            .buttonStyle(.plain)

            // Mark as viewed/unviewed button
            Button(action: onViewed) {
                Image(systemName: isViewed ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundColor(isViewed ? .secondary : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .help(isViewed ? "Mark as unviewed" : "Mark as viewed")
        }
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
    let file: ChangedFile
    let commitId: String?
    let pr: EnrichedPullRequest
    let fontSize: CGFloat
    @ObservedObject var diffViewModel: PRDiffViewModel
    @ObservedObject var commentViewModel: ReviewCommentViewModel

    private var filePath: String { file.path }
    private var patch: String? { file.patch }

    @State private var expandedCommentLines = Set<String>()
    @State private var viewportWidth: CGFloat = 0

    private var diffLines: [DiffLine] {
        diffViewModel.getDiffLines(for: file)
    }

    private func lineIdentifier(_ line: DiffLine) -> String {
        let side: CommentSide = line.type == .removed ? .left : .right
        return "\(line.filePath)-\(line.oldLineNumber ?? line.newLineNumber ?? 0)-\(side.rawValue)"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
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
                            fontSize: fontSize,
                            onCommentToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let identifier = lineIdentifier(line)
                                    let existingDraft = commentViewModel.getDraftForLine(
                                        filePath: filePath,
                                        line: lineNumber ?? 0,
                                        side: side
                                    )

                                    if existingDraft != nil {
                                        if expandedCommentLines.contains(identifier) {
                                            expandedCommentLines.remove(identifier)
                                        } else {
                                            expandedCommentLines.insert(identifier)
                                        }
                                    } else {
                                        _ = commentViewModel.addDraft(
                                            filePath: filePath,
                                            line: lineNumber ?? 0,
                                            side: side
                                        )
                                        expandedCommentLines.insert(identifier)
                                    }
                                }
                            },
                            onAddComment: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let existingDraft = commentViewModel.getDraftForLine(
                                        filePath: filePath,
                                        line: lineNumber ?? 0,
                                        side: side
                                    )

                                    if existingDraft == nil {
                                        _ = commentViewModel.addDraft(
                                            filePath: filePath,
                                            line: lineNumber ?? 0,
                                            side: side
                                        )
                                        expandedCommentLines.insert(lineIdentifier(line))
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
                                onSaveDraft: { _ in
                                    // Draft is already saved via onDraftBodyChange
                                },
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
            // Ensure the content is at least as wide as the viewport so row backgrounds can fill to the right edge.
            .frame(minWidth: viewportWidth, alignment: .leading)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ViewportWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(ViewportWidthPreferenceKey.self) { newValue in
            if abs(viewportWidth - newValue) > 0.5 {
                viewportWidth = newValue
            }
        }
        .frame(maxWidth: .infinity)
        .font(.system(size: fontSize, design: .monospaced))
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct DiffLineView: View {
    let line: DiffLine
    let commentCount: Int
    let fontSize: CGFloat
    let onCommentToggle: () -> Void
    let onAddComment: () -> Void

    init(line: DiffLine, commentCount: Int = 0, fontSize: CGFloat = 13.0, onCommentToggle: @escaping () -> Void = {}, onAddComment: @escaping () -> Void = {}) {
        self.line = line
        self.commentCount = commentCount
        self.fontSize = fontSize
        self.onCommentToggle = onCommentToggle
        self.onAddComment = onAddComment
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
                    .font(.system(size: fontSize * 0.8, design: .monospaced))

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)

                // New line number
                Text(line.newLineNumber.map(String.init) ?? "")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
                    .font(.system(size: fontSize * 0.8, design: .monospaced))

                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(height: fontSize + 8)
            .background(Color(NSColor.textBackgroundColor))

            // Comment indicator
            if commentCount > 0 {
                Button(action: onCommentToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: fontSize * 0.8))
                        Text("\(commentCount)")
                            .font(.system(size: fontSize * 0.8))
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
                Button(action: onAddComment) {
                    Image(systemName: "plus")
                        .font(.system(size: fontSize * 0.8))
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
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(foregroundColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(backgroundColor ?? Color.clear)
        }
        .frame(height: line.type == .context ? fontSize + 8 : nil)
    }
}

struct SkeletonDiffFileRow: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    // File name placeholder
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: .random(in: 150...250), height: 13)

                    // Directory placeholder
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 11)
                }

                Spacer()

                // Stats placeholder
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 30, height: 11)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 30, height: 11)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(
            Animation.easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}
