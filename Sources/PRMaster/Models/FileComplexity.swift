import Foundation
import SwiftUI

/// Complexity assessment for a file in a PR
struct FileComplexity: Codable {
    let filePath: String
    let score: Int  // 0-100
    let level: ComplexityLevel
    let factors: ComplexityFactors

    enum ComplexityLevel: String, Codable {
        case trivial = "Trivial"
        case simple = "Simple"
        case moderate = "Moderate"
        case complex = "Complex"
        case veryComplex = "Very Complex"

        var color: String {
            switch self {
            case .trivial: return "green"
            case .simple: return "mint"
            case .moderate: return "yellow"
            case .complex: return "orange"
            case .veryComplex: return "red"
            }
        }

        var icon: String {
            switch self {
            case .trivial: return "checkmark.circle"
            case .simple: return "checkmark.circle.fill"
            case .moderate: return "exclamationmark.circle"
            case .complex: return "exclamationmark.triangle"
            case .veryComplex: return "exclamationmark.octagon"
            }
        }

        var displayColor: Color {
            switch self {
            case .trivial: return .green
            case .simple: return .mint
            case .moderate: return .yellow
            case .complex: return .orange
            case .veryComplex: return .red
            }
        }
    }

    struct ComplexityFactors: Codable {
        let linesChanged: Int
        let filesTouched: Int
        let isBinary: Bool
        let isTestFile: Bool
        let isConfigFile: Bool
        let hasMajorRefactoring: Bool
        let extensionRisk: ExtensionRisk
    }

    enum ExtensionRisk: String, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }
}

/// Calculate complexity for a file
struct FileComplexityCalculator {
    static func calculate(for file: ChangedFile) -> FileComplexity {
        let additions = file.additions ?? 0
        let deletions = file.deletions ?? 0
        let totalChanges = additions + deletions

        var score = 0
        var factors = FileComplexity.ComplexityFactors(
            linesChanged: totalChanges,
            filesTouched: 1,
            isBinary: file.patch == nil,
            isTestFile: isTestFile(file.path),
            isConfigFile: isConfigFile(file.path),
            hasMajorRefactoring: hasMajorRefactoring(file),
            extensionRisk: extensionRisk(for: file.path)
        )

        // Score based on lines changed (0-40 points)
        if totalChanges == 0 {
            score += 0
        } else if totalChanges < 10 {
            score += 5
        } else if totalChanges < 50 {
            score += 15
        } else if totalChanges < 200 {
            score += 30
        } else {
            score += 40
        }

        // Binary files are trivial to review
        if factors.isBinary {
            score = 5
        }

        // Test files are lower priority
        if factors.isTestFile {
            score = max(score - 10, 5)
        }

        // Config files need careful review
        if factors.isConfigFile {
            score = min(score + 15, 100)
        }

        // Major refactoring adds complexity
        if factors.hasMajorRefactoring {
            score = min(score + 20, 100)
        }

        // File extension risk
        switch factors.extensionRisk {
        case .low:
            break // No adjustment
        case .medium:
            score = min(score + 10, 100)
        case .high:
            score = min(score + 20, 100)
        }

        let level: FileComplexity.ComplexityLevel
        switch score {
        case 0...20: level = .trivial
        case 21...40: level = .simple
        case 41...60: level = .moderate
        case 61...80: level = .complex
        default: level = .veryComplex
        }

        return FileComplexity(
            filePath: file.path,
            score: score,
            level: level,
            factors: factors
        )
    }

    private static func isTestFile(_ path: String) -> Bool {
        let lowercasePath = path.lowercased()
        return lowercasePath.contains("test") ||
               lowercasePath.contains("spec") ||
               lowercasePath.hasSuffix("_test.swift") ||
               lowercasePath.hasSuffix("_tests.swift") ||
               lowercasePath.contains("/tests/")
    }

    private static func isConfigFile(_ path: String) -> Bool {
        let configExtensions = [
            "json", "yaml", "yml", "toml", "ini",
            "cfg", "conf", "config", "xml"
        ]
        let configFiles = [
            "package.json", "tsconfig.json",
            "dockerfile", "docker-compose",
            "makefile", "rakefile",
            ".gitignore", ".env"
        ]

        let lowercasePath = path.lowercased()
        return configExtensions.contains(where: { lowercasePath.hasSuffix(".\($0)") }) ||
               configFiles.contains(where: { lowercasePath.contains($0) })
    }

    private static func hasMajorRefactoring(_ file: ChangedFile) -> Bool {
        guard let changeType = file.changeType else { return false }
        return changeType == "RENAMED" || file.deletions ?? 0 > 100
    }

    private static func extensionRisk(for path: String) -> FileComplexity.ExtensionRisk {
        let ext = ((path as NSString).pathExtension as String).lowercased()

        let lowRisk = ["md", "txt", "csv", "json", "yaml", "yml"]
        let highRisk = ["swift", "kt", "java", "cpp", "c", "h", "rs", "go"]

        if lowRisk.contains(ext) {
            return .low
        } else if highRisk.contains(ext) {
            return .high
        } else {
            return .medium
        }
    }
}
