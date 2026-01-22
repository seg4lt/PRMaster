import Foundation

enum LocalGitError: Error, LocalizedError {
    case gitNotFound
    case invalidRepository(String)
    case commandFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git command not found"
        case .invalidRepository(let path):
            return "Invalid git repository at: \(path)"
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .parseError(let message):
            return "Failed to parse git output: \(message)"
        }
    }
}

actor LocalGitService {
    static let shared = LocalGitService()

    private let shell = ShellExecutor.shared

    private init() {}

    // MARK: - Repository Validation

    func validateRepository(path: String) async -> Bool {
        do {
            let output = try await executeGit(arguments: ["rev-parse", "--git-dir"], workingDirectory: path)
            return !output.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Commit Fetching

    func fetchCommits(
        localPath: String,
        author: String,
        startDate: Date,
        endDate: Date,
        repositoryName: String
    ) async throws -> [Commit] {
        // Format: YYYY-MM-DD
        let since = formatDateForGit(startDate)
        let until = formatDateForGit(endDate)

        // Git log format: SHA|Message|ISO8601Date
        // Using --all to include all branches
        let arguments = [
            "log",
            "--author=\(author)",
            "--since=\(since)",
            "--until=\(until)",
            "--pretty=format:%H|%s|%aI",
            "--all"
        ]

        let output = try await executeGit(arguments: arguments, workingDirectory: localPath)
        return try parseCommitLog(output, repositoryName: repositoryName)
    }

    private func formatDateForGit(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func parseCommitLog(_ output: String, repositoryName: String) throws -> [Commit] {
        guard !output.isEmpty else { return [] }

        let lines = output.components(separatedBy: .newlines)
        var commits: [Commit] = []

        for line in lines {
            guard !line.isEmpty else { continue }

            let parts = line.components(separatedBy: "|")
            guard parts.count == 3 else {
                throw LocalGitError.parseError("Invalid log line format: \(line)")
            }

            let sha = parts[0]
            let message = parts[1]
            let dateString = parts[2]

            let dateFormatter = ISO8601DateFormatter()
            guard let date = dateFormatter.date(from: dateString) else {
                throw LocalGitError.parseError("Invalid date format: \(dateString)")
            }

            let commit = Commit(
                sha: sha,
                message: message,
                authorDate: date,
                repository: repositoryName
            )
            commits.append(commit)
        }

        return commits
    }

    // MARK: - Commit Diffs

    func fetchCommitDiff(localPath: String, sha: String) async throws -> String {
        let arguments = [
            "show",
            sha,
            "--format=",
            "--no-color"
        ]

        let diff = try await executeGit(arguments: arguments, workingDirectory: localPath)
        return filterDiff(diff)
    }

    func fetchCommitDiffs(
        commits: [Commit],
        localPath: String,
        concurrencyLimit: Int = 5
    ) async -> [String: String] {
        var allDiffs: [String: String] = [:]

        await withTaskGroup(of: [(String, String)].self) { group in
            for chunk in commits.chunked(into: concurrencyLimit) {
                group.addTask {
                    var chunkDiffs: [(String, String)] = []

                    await withTaskGroup(of: (String, String?).self) { chunkGroup in
                        for commit in chunk {
                            chunkGroup.addTask {
                                do {
                                    let diff = try await self.fetchCommitDiff(localPath: localPath, sha: commit.sha)
                                    return (commit.sha, diff)
                                } catch {
                                    // Return nil on failure - we'll proceed without the diff
                                    return (commit.sha, nil)
                                }
                            }
                        }

                        for await (sha, diff) in chunkGroup {
                            if let diff = diff {
                                chunkDiffs.append((sha, diff))
                            }
                        }
                    }

                    return chunkDiffs
                }
            }

            for await chunkResults in group {
                for (sha, diff) in chunkResults {
                    allDiffs[sha] = diff
                }
            }
        }

        return allDiffs
    }

    // MARK: - Diff Filtering

    private func filterDiff(_ diff: String) -> String {
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

        let sections = diff.components(separatedBy: "diff --git ")

        let filtered = sections.filter { section in
            guard !section.isEmpty else { return false }

            if section.contains("Binary files") { return false }

            let firstLine = section.components(separatedBy: "\n").first ?? ""
            for pattern in lockFilePatterns {
                if firstLine.contains(pattern) { return false }
            }

            return true
        }

        return filtered.map { "diff --git " + $0 }.joined()
    }

    // MARK: - Git Execution

    private func executeGit(arguments: [String], workingDirectory: String, timeout: TimeInterval = 30) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.nix-profile/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
        } catch {
            throw LocalGitError.gitNotFound
        }

        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                throw LocalGitError.commandFailed("Timeout after \(timeout) seconds")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw LocalGitError.commandFailed(output)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
