import Foundation

enum ShellError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case commandNotFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output, let code):
            return "Command failed with exit code \(code): \(output)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        }
    }
}

actor ShellExecutor {
    static let shared = ShellExecutor()

    private init() {}

    func execute(_ command: String, arguments: [String] = []) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ShellError.commandNotFound(command)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.commandFailed(output, process.terminationStatus)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func executeGH(_ arguments: [String]) async throws -> String {
        try await execute("gh", arguments: arguments)
    }
}
