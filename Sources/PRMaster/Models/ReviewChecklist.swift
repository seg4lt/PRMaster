import Foundation
import SwiftUI

enum ChecklistItem: String, Identifiable {
    case viewedAllFiles = "Review all files"
    case addressedComments = "Address all comments"
    case resolvedDrafts = "Resolve all draft comments"
    case checkedConflicts = "Check for merge conflicts"
    case verifiedCIPassed = "Verify CI/CD status"
    case reviewedComplexFiles = "Review complex files"
    case checkedConfigChanges = "Review config changes"
    case reviewedTests = "Review test changes"
    case checkedBreakingChanges = "Check for breaking changes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .viewedAllFiles: return "doc.text"
        case .addressedComments: return "bubble.left.and.bubble.right"
        case .resolvedDrafts: return "pencil"
        case .checkedConflicts: return "exclamationmark.triangle"
        case .verifiedCIPassed: return "checkmark.seal"
        case .reviewedComplexFiles: return "exclamationmark.octagon"
        case .checkedConfigChanges: return "gear"
        case .reviewedTests: return "testtube"
        case .checkedBreakingChanges: return "arrow.triangle.2.circlepath"
        }
    }

    var category: ChecklistCategory {
        switch self {
        case .viewedAllFiles, .reviewedComplexFiles, .reviewedTests, .checkedConfigChanges:
            return .review
        case .addressedComments, .resolvedDrafts:
            return .collaboration
        case .checkedConflicts, .verifiedCIPassed, .checkedBreakingChanges:
            return .validation
        }
    }
}

enum ChecklistCategory: String, CaseIterable {
    case review = "Review"
    case collaboration = "Collaboration"
    case validation = "Validation"

    var icon: String {
        switch self {
        case .review: return "doc.text"
        case .collaboration: return "person.2"
        case .validation: return "checkmark.shield"
        }
    }

    var color: Color {
        switch self {
        case .review: return .blue
        case .collaboration: return .purple
        case .validation: return .green
        }
    }
}

struct ChecklistItemStatus: Identifiable {
    let item: ChecklistItem
    var isComplete: Bool
    var isApplicable: Bool
    var details: String?

    var id: String { item.rawValue }

    init(item: ChecklistItem, isComplete: Bool = false, isApplicable: Bool = true, details: String? = nil) {
        self.item = item
        self.isComplete = isComplete
        self.isApplicable = isApplicable
        self.details = details
    }
}

@MainActor
class ReviewChecklistViewModel: ObservableObject {
    @Published var items: [ChecklistItemStatus] = []

    func updateChecklist(
        files: [ChangedFile],
        viewStatuses: [String: FileViewStatus],
        commentViewModel: ReviewCommentViewModel,
        ciStatus: CIStatus?
    ) {
        var newItems: [ChecklistItemStatus] = []

        // Check if all files viewed
        let totalFiles = files.count
        let viewedFiles = files.filter { viewStatuses[$0.path]?.isViewed == true }.count
        let allFilesViewed = totalFiles > 0 && viewedFiles == totalFiles

        newItems.append(ChecklistItemStatus(
            item: .viewedAllFiles,
            isComplete: allFilesViewed,
            isApplicable: true,
            details: viewedFiles < totalFiles ? "\(viewedFiles)/\(totalFiles) files viewed" : nil
        ))

        // Check if all existing comments addressed
        let filesWithComments = files.filter { file in
            commentViewModel.hasCommentsForFile(filePath: file.path) &&
            commentViewModel.getCommentCountForFile(filePath: file.path) > 0
        }

        let allCommentsAddressed = filesWithComments.isEmpty || filesWithComments.allSatisfy { file in
            viewStatuses[file.path]?.isViewed == true
        }

        newItems.append(ChecklistItemStatus(
            item: .addressedComments,
            isComplete: allCommentsAddressed,
            isApplicable: !filesWithComments.isEmpty,
            details: !filesWithComments.isEmpty ? "\(filesWithComments.count) files with comments" : nil
        ))

        // Check if all drafts resolved
        let draftCount = commentViewModel.drafts.count
        newItems.append(ChecklistItemStatus(
            item: .resolvedDrafts,
            isComplete: draftCount == 0,
            isApplicable: true,
            details: draftCount > 0 ? "\(draftCount) draft comments" : nil
        ))

        // Check for merge conflicts
        // For now, mark as N/A - could be enhanced with git status check
        newItems.append(ChecklistItemStatus(
            item: .checkedConflicts,
            isComplete: true,
            isApplicable: false,
            details: "No conflict detection available"
        ))

        // Verify CI status
        if let ciStatus = ciStatus {
            let ciPassed = ciStatus == .success
            newItems.append(ChecklistItemStatus(
                item: .verifiedCIPassed,
                isComplete: ciPassed,
                isApplicable: true,
                details: ciStatus.rawValue
            ))
        } else {
            newItems.append(ChecklistItemStatus(
                item: .verifiedCIPassed,
                isComplete: true,
                isApplicable: false,
                details: "No CI status available"
            ))
        }

        // Check complex files reviewed
        let complexFiles = files.filter { file in
            let complexity = FileComplexityCalculator.calculate(for: file)
            return complexity.level == .veryComplex || complexity.level == .complex
        }

        let complexFilesReviewed = complexFiles.filter { file in
            viewStatuses[file.path]?.isViewed == true
        }.count

        let allComplexReviewed = complexFiles.isEmpty || complexFilesReviewed == complexFiles.count

        newItems.append(ChecklistItemStatus(
            item: .reviewedComplexFiles,
            isComplete: allComplexReviewed,
            isApplicable: !complexFiles.isEmpty,
            details: !complexFiles.isEmpty ? "\(complexFilesReviewed)/\(complexFiles.count) complex files" : nil
        ))

        // Check config changes
        let configFiles = files.filter { file in
            FileComplexityCalculator.calculate(for: file).factors.isConfigFile
        }

        let configFilesReviewed = configFiles.filter { file in
            viewStatuses[file.path]?.isViewed == true
        }.count

        let allConfigReviewed = configFiles.isEmpty || configFilesReviewed == configFiles.count

        newItems.append(ChecklistItemStatus(
            item: .checkedConfigChanges,
            isComplete: allConfigReviewed,
            isApplicable: !configFiles.isEmpty,
            details: !configFiles.isEmpty ? "\(configFilesReviewed)/\(configFiles.count) config files" : nil
        ))

        // Check test changes
        let testFiles = files.filter { file in
            FileComplexityCalculator.calculate(for: file).factors.isTestFile
        }

        let testFilesReviewed = testFiles.filter { file in
            viewStatuses[file.path]?.isViewed == true
        }.count

        let allTestsReviewed = testFiles.isEmpty || testFilesReviewed == testFiles.count

        newItems.append(ChecklistItemStatus(
            item: .reviewedTests,
            isComplete: allTestsReviewed,
            isApplicable: !testFiles.isEmpty,
            details: !testFiles.isEmpty ? "\(testFilesReviewed)/\(testFiles.count) test files" : nil
        ))

        // Check for breaking changes
        // For now, mark as N/A - could be enhanced with pattern detection
        newItems.append(ChecklistItemStatus(
            item: .checkedBreakingChanges,
            isComplete: true,
            isApplicable: false,
            details: "Manual review required"
        ))

        self.items = newItems
    }

    var completionPercentage: Double {
        guard !items.isEmpty else { return 1.0 }
        let applicableItems = items.filter { $0.isApplicable }
        guard !applicableItems.isEmpty else { return 1.0 }
        let completedItems = applicableItems.filter { $0.isComplete }
        return Double(completedItems.count) / Double(applicableItems.count)
    }

    var canSubmitReview: Bool {
        let applicableItems = items.filter { $0.isApplicable }
        return applicableItems.allSatisfy { $0.isComplete }
    }
}

enum CIStatus: String {
    case success = "Passed"
    case failure = "Failed"
    case pending = "Pending"
    case running = "Running"
    case unknown = "Unknown"
}
