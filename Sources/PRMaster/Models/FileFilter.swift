import Foundation
import SwiftUI

enum FilterCategory: String, CaseIterable, Identifiable {
    case all = "All Files"
    case unviewed = "Unviewed"
    case viewed = "Viewed"
    case withComments = "Has Comments"
    case veryComplex = "Very Complex"
    case complex = "Complex"
    case moderate = "Moderate"
    case simple = "Simple"
    case trivial = "Trivial"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "doc.text"
        case .unviewed: return "circle"
        case .viewed: return "checkmark.circle.fill"
        case .withComments: return "bubble.left.fill"
        case .veryComplex, .complex, .moderate, .simple, .trivial:
            return FileComplexity.ComplexityLevel(rawValue: rawValue)?.icon ?? "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .all: return .blue
        case .unviewed: return .orange
        case .viewed: return .green
        case .withComments: return .blue
        case .veryComplex: return .red
        case .complex: return .orange
        case .moderate: return .yellow
        case .simple: return .mint
        case .trivial: return .green
        }
    }
}

@MainActor
class FileFilterViewModel: ObservableObject {
    @Published var selectedCategory: FilterCategory = .all
    @Published var searchText: String = ""

    func filterFiles(
        _ files: [ChangedFile],
        viewStatuses: [String: FileViewStatus],
        commentViewModel: ReviewCommentViewModel
    ) -> [ChangedFile] {
        var filtered = files

        // Apply category filter
        switch selectedCategory {
        case .all:
            break
        case .unviewed:
            filtered = filtered.filter { file in
                viewStatuses[file.path]?.isViewed != true
            }
        case .viewed:
            filtered = filtered.filter { file in
                viewStatuses[file.path]?.isViewed == true
            }
        case .withComments:
            filtered = filtered.filter { file in
                commentViewModel.hasCommentsForFile(filePath: file.path)
            }
        case .veryComplex, .complex, .moderate, .simple, .trivial:
            let targetLevel = FileComplexity.ComplexityLevel(rawValue: selectedCategory.rawValue)
            filtered = filtered.filter { file in
                let complexity = FileComplexityCalculator.calculate(for: file)
                return complexity.level == targetLevel
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { file in
                file.path.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    func isActive() -> Bool {
        selectedCategory != .all || !searchText.isEmpty
    }

    func clear() {
        selectedCategory = .all
        searchText = ""
    }
}
