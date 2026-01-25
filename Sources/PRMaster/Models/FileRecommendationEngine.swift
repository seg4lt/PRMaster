import Foundation
import SwiftUI

struct FileRecommendation {
    let filePath: String
    let reason: RecommendationReason
    let confidence: Double // 0-1
    let score: Double

    enum RecommendationReason {
        case hasComments
        case veryComplex
        case manyChanges
        case configChange
        case testChange
        case highRiskExtension

        var description: String {
            switch self {
            case .hasComments: return "Has unresolved comments"
            case .veryComplex: return "High complexity - review while fresh"
            case .manyChanges: return "Large number of changes"
            case .configChange: return "Config file - needs careful review"
            case .testChange: return "Test coverage changes"
            case .highRiskExtension: return "High-risk file type"
            }
        }

        var icon: String {
            switch self {
            case .hasComments: return "bubble.left.fill"
            case .veryComplex: return "exclamationmark.octagon.fill"
            case .manyChanges: return "plus.circle"
            case .configChange: return "gear"
            case .testChange: return "testtube"
            case .highRiskExtension: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .hasComments: return .blue
            case .veryComplex: return .red
            case .manyChanges: return .orange
            case .configChange: return .purple
            case .testChange: return .green
            case .highRiskExtension: return .yellow
            }
        }
    }
}

struct FileRecommendationEngine {
    @MainActor
    static func recommendNextFile(
        from files: [ChangedFile],
        viewStatuses: [String: FileViewStatus],
        commentViewModel: ReviewCommentViewModel
    ) -> FileRecommendation? {
        let unviewedFiles = files.filter { file in
            viewStatuses[file.path]?.isViewed != true
        }

        guard !unviewedFiles.isEmpty else { return nil }

        var bestRecommendation: FileRecommendation?
        var bestScore: Double = 0

        for file in unviewedFiles {
            let recommendation = scoreFile(file, commentViewModel: commentViewModel)

            if recommendation.score > bestScore {
                bestScore = recommendation.score
                bestRecommendation = recommendation
            }
        }

        return bestRecommendation
    }

    @MainActor
    private static func scoreFile(
        _ file: ChangedFile,
        commentViewModel: ReviewCommentViewModel
    ) -> FileRecommendation {
        var score: Double = 0
        var factors: [FileRecommendation.RecommendationReason] = []
        var confidence: Double = 1.0

        // Factor 1: Has comments (highest priority)
        if commentViewModel.hasCommentsForFile(filePath: file.path) {
            let _ = commentViewModel.getCommentCountForFile(filePath: file.path)
            score += 100
            factors.append(.hasComments)
            confidence = 1.0
        }

        // Calculate complexity
        let complexity = FileComplexityCalculator.calculate(for: file)

        // Factor 2: Very complex files
        if complexity.level == .veryComplex {
            score += 75
            factors.append(.veryComplex)
        } else if complexity.level == .complex {
            score += 50
        }

        // Factor 3: Many changes
        let totalChanges = (file.additions ?? 0) + (file.deletions ?? 0)
        if totalChanges > 500 {
            score += 40
            factors.append(.manyChanges)
        } else if totalChanges > 200 {
            score += 25
        } else if totalChanges > 100 {
            score += 10
        }

        // Factor 4: Config files
        if complexity.factors.isConfigFile {
            score += 60
            factors.append(.configChange)
        }

        // Factor 5: High risk extension
        if complexity.factors.extensionRisk == .high {
            score += 30
            factors.append(.highRiskExtension)
        }

        // Factor 6: Test files (lower priority unless they have comments)
        if complexity.factors.isTestFile && !factors.contains(.hasComments) {
            score = max(score - 30, 10)
            confidence *= 0.7
        }

        // Select the primary reason
        let primaryReason = factors.first ?? .manyChanges

        return FileRecommendation(
            filePath: file.path,
            reason: primaryReason,
            confidence: confidence,
            score: score
        )
    }
}
