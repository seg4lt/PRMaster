import Foundation
import SwiftUI

struct FileGroup: Identifiable {
    let id: String  // Directory path
    let path: String  // Directory path
    var files: [ChangedFile]
    var isExpanded: Bool

    var displayName: String {
        if path == "/" || path.isEmpty {
            return "Root"
        }
        return (path as NSString).lastPathComponent
    }

    var fileCount: Int {
        files.count
    }

    var totalAdditions: Int {
        files.compactMap { $0.additions }.reduce(0, +)
    }

    var totalDeletions: Int {
        files.compactMap { $0.deletions }.reduce(0, +)
    }

    var maxComplexity: FileComplexity {
        files.map { FileComplexityCalculator.calculate(for: $0) }
            .max(by: { $0.score < $1.score }) ?? FileComplexity(
                filePath: "",
                score: 0,
                level: .trivial,
                factors: FileComplexity.ComplexityFactors(
                    linesChanged: 0,
                    filesTouched: 0,
                    isBinary: false,
                    isTestFile: false,
                    isConfigFile: false,
                    hasMajorRefactoring: false,
                    extensionRisk: .low
                )
            )
    }

    var hasComments: Bool {
        // This will be computed dynamically
        false
    }
}

@MainActor
class FileGroupingViewModel: ObservableObject {
    @Published var groups: [FileGroup] = []
    @Published var groupingEnabled: Bool = false

    func updateGroups(for files: [ChangedFile]) {
        guard groupingEnabled else {
            groups = []
            return
        }

        let grouped = Dictionary(grouping: files) { file -> String in
            let path = file.path
            let dir = (path as NSString).deletingLastPathComponent
            return dir.isEmpty ? "/" : dir
        }

        groups = grouped.map { (path, files) in
            FileGroup(
                id: path,
                path: path,
                files: files.sorted { $0.path < $1.path },
                isExpanded: false
            )
        }.sorted { $0.path < $1.path }
    }

    func toggleGroup(_ groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].isExpanded.toggle()
    }

    func expandAll() {
        for index in groups.indices {
            groups[index].isExpanded = true
        }
    }

    func collapseAll() {
        for index in groups.indices {
            groups[index].isExpanded = false
        }
    }

    func getComplexityColor(for group: FileGroup) -> Color {
        group.maxComplexity.level.displayColor
    }

    func getComplexityIcon(for group: FileGroup) -> String {
        group.maxComplexity.level.icon
    }
}
