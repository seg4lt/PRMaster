import Foundation
import SwiftUI

/// Tracks time spent reviewing each file and total review time
@MainActor
class ReviewSessionTimer: ObservableObject {
    @Published var fileTimings: [String: TimeInterval] = [:]
    @Published var totalSessionTime: TimeInterval = 0
    @Published var isRunning: Bool = false
    @Published var currentFile: String?

    private var sessionStartTime: Date?
    private var fileStartTime: Date?
    private var timer: Timer?

    var formattedTotalTime: String {
        formatTimeInterval(totalSessionTime)
    }

    func startSession() {
        guard !isRunning else { return }
        isRunning = true
        sessionStartTime = Date()
        startTimer()
    }

    func stopSession() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        currentFile = nil
        fileStartTime = nil
    }

    func startFile(_ filePath: String) {
        currentFile = filePath
        fileStartTime = Date()
    }

    func stopFile(_ filePath: String) {
        guard let start = fileStartTime, currentFile == filePath else { return }

        let duration = Date().timeIntervalSince(start)
        fileTimings[filePath] = (fileTimings[filePath] ?? 0) + duration

        currentFile = nil
        fileStartTime = nil
    }

    func getFileTime(_ filePath: String) -> TimeInterval {
        fileTimings[filePath] ?? 0
    }

    func getFormattedFileTime(_ filePath: String) -> String {
        formatTimeInterval(getFileTime(filePath))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.sessionStartTime else { return }
            self.totalSessionTime = Date().timeIntervalSince(start)
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
