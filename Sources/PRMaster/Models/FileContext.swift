import Foundation
import SwiftUI

struct FileContext: Identifiable {
    let id: String = UUID().uuidString
    let filePath: String
    let commitMessage: String?
    let relatedFiles: [String]
    let testImpact: TestImpact
    let dependencies: DependencyInfo
    let riskLevel: RiskLevel

    enum TestImpact {
        case none
        case testsModified
        case testsAdded
        case coverageChanged(change: String)
    }

    enum RiskLevel: String, CaseIterable {
        case low = "Low Risk"
        case medium = "Medium Risk"
        case high = "High Risk"
        case critical = "Critical"

        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .low: return "checkmark.shield.fill"
            case .medium: return "exclamationmark.shield.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.shield.fill"
            }
        }
    }

    struct DependencyInfo {
        let filesDependingOnThis: [String]
        let filesThisDependsOn: [String]
        let circularDeps: [String]

        var hasCircularDependencies: Bool {
            !circularDeps.isEmpty
        }
    }
}

struct FileContextAnalyzer {
    static func analyzeContext(
        for file: ChangedFile,
        allFiles: [ChangedFile],
        commitMessage: String? = nil
    ) -> FileContext {
        // Determine test impact
        let testImpact = determineTestImpact(file: file, allFiles: allFiles)

        // Analyze dependencies (basic implementation)
        let dependencies = analyzeDependencies(file: file, allFiles: allFiles)

        // Find related files
        let relatedFiles = findRelatedFiles(file: file, allFiles: allFiles)

        // Determine risk level
        let riskLevel = assessRisk(file: file, dependencies: dependencies)

        return FileContext(
            filePath: file.path,
            commitMessage: commitMessage,
            relatedFiles: relatedFiles,
            testImpact: testImpact,
            dependencies: dependencies,
            riskLevel: riskLevel
        )
    }

    private static func determineTestImpact(file: ChangedFile, allFiles: [ChangedFile]) -> FileContext.TestImpact {
        let isTestFile = FileComplexityCalculator.calculate(for: file).factors.isTestFile

        if isTestFile {
            let additions = file.additions ?? 0
            if additions > 0 {
                return .testsAdded
            } else {
                return .testsModified
            }
        }

        // Check if tests were modified for this file
        let fileName = (file.path as NSString).lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension

        let relatedTests = allFiles.filter { testFile in
            let testFileName = (testFile.path as NSString).lastPathComponent
            return testFileName.contains(baseName) ||
                   testFileName.contains("Test") ||
                   testFileName.contains("Spec")
        }

        if !relatedTests.isEmpty {
            return .coverageChanged(change: "\(relatedTests.count) test file\(relatedTests.count == 1 ? "" : "s") modified")
        }

        return .none
    }

    private static func analyzeDependencies(file: ChangedFile, allFiles: [ChangedFile]) -> FileContext.DependencyInfo {
        // Find files that might depend on this one
        let fileName = (file.path as NSString).lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension

        let filesDependingOnThis = allFiles.filter { otherFile in
            guard otherFile.path != file.path else { return false }
            let otherContent = otherFile.patch ?? ""
            return otherContent.contains("import \(baseName)") ||
                   otherContent.contains("#include \"\(baseName)") ||
                   otherContent.contains("from \(baseName)")
        }.map { $0.path }

        // Find files this depends on
        let fileContent = file.patch ?? ""
        let filesThisDependsOn = allFiles.filter { otherFile in
            guard otherFile.path != file.path else { return false }
            let otherName = ((otherFile.path as NSString).lastPathComponent as NSString).deletingPathExtension
            return fileContent.contains("import \(otherName)") ||
                   fileContent.contains("#include \"\(otherName)") ||
                   fileContent.contains("from \(otherName)")
        }.map { $0.path }

        // Check for circular dependencies
        let circularDeps = filesThisDependsOn.filter { dep in
            filesDependingOnThis.contains(dep)
        }

        return FileContext.DependencyInfo(
            filesDependingOnThis: filesDependingOnThis,
            filesThisDependsOn: filesThisDependsOn,
            circularDeps: circularDeps
        )
    }

    private static func findRelatedFiles(file: ChangedFile, allFiles: [ChangedFile]) -> [String] {
        let dir = (file.path as NSString).deletingLastPathComponent

        // Find files in the same directory
        let sameDirFiles = allFiles
            .filter { (($0.path as NSString).deletingLastPathComponent) == dir }
            .map { $0.path }
            .filter { $0 != file.path }

        return sameDirFiles
    }

    private static func assessRisk(file: ChangedFile, dependencies: FileContext.DependencyInfo) -> FileContext.RiskLevel {
        var riskScore = 0

        // Circular dependencies
        if dependencies.hasCircularDependencies {
            riskScore += 50
        }

        // Many files depend on this
        if dependencies.filesDependingOnThis.count > 5 {
            riskScore += 30
        } else if dependencies.filesDependingOnThis.count > 2 {
            riskScore += 15
        }

        // Complexity
        let complexity = FileComplexityCalculator.calculate(for: file)
        riskScore += Int(Double(complexity.score) * 0.3)

        // Config file
        if complexity.factors.isConfigFile {
            riskScore += 25
        }

        // High risk extension
        if complexity.factors.extensionRisk == .high {
            riskScore += 20
        }

        switch riskScore {
        case 0...30: return .low
        case 31...50: return .medium
        case 51...70: return .high
        default: return .critical
        }
    }
}
