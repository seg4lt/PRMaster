import Foundation

enum ShellError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case commandNotFound(String)
    case timeout(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output, let code):
            return "Command failed with exit code \(code): \(output)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .timeout(let seconds):
            return "Command timed out after \(Int(seconds)) seconds"
        }
    }
}

actor ShellExecutor {
    static let shared = ShellExecutor()

    private init() {}

    func execute(_ command: String, arguments: [String] = [], timeout: TimeInterval = 30, workingDirectory: URL? = nil, disablePager: Bool = false) async throws -> String {
        print("[ShellExecutor] Executing: \(command) \(arguments.joined(separator: " ")) in \(workingDirectory?.path ?? "temp") with timeout: \(timeout)s, disablePager=\(disablePager)")

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        // Use provided working directory or fallback to temp
        process.currentDirectoryURL = workingDirectory ?? FileManager.default.temporaryDirectory

        // Add common binary paths for GUI apps launched from Finder
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()

        // Disable pager for git/gh commands to prevent hanging (when requested)
        if disablePager {
            env["GIT_PAGER"] = "cat"
            env["GH_PAGER"] = "cat"
            env["PAGER"] = "cat"
            env["LESS"] = "-FRX"
        }

        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.nix-profile/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.claude/local"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
        } catch {
            throw ShellError.commandNotFound(command)
        }

        // Wait for process with timeout
        let startTime = Date()
        while process.isRunning {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeout {
                process.terminate()
                print("[ShellExecutor] ❌ Command timed out after \(elapsed)s")
                throw ShellError.timeout(timeout)
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let elapsedTime = Date().timeIntervalSince(startTime)

        print("[ShellExecutor] ✓ Process completed in \(String(format: "%.2f", elapsedTime))s with exit code \(process.terminationStatus)")
        print("[ShellExecutor] Output size: \(output.count) bytes")

        if process.terminationStatus != 0 {
            print("[ShellExecutor] ❌ Command failed with output: \(output)")
            throw ShellError.commandFailed(output, process.terminationStatus)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func executeGH(_ arguments: [String], timeout: TimeInterval = 60, workingDirectory: URL? = nil, disablePager: Bool = false) async throws -> String {
        try await execute("gh", arguments: arguments, timeout: timeout, workingDirectory: workingDirectory, disablePager: disablePager)
    }
}
