import Foundation
import SwiftData

@MainActor
class PollingService: ObservableObject {
    static let shared = PollingService()

    private var timer: Timer?
    @Published var pollingInterval: TimeInterval = 300
    private var seenPRIds: Set<String> = []
    private var isFirstLoad = true

    private init() {}

    func startPolling(interval: TimeInterval = 300) {
        pollingInterval = interval
        stopPolling()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }

        Task {
            await poll()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func poll() async {
        do {
            let prs = try await GitHubService.shared.fetchPRsToReview()

            let newPRs = prs.filter { !seenPRIds.contains($0.id) }

            if !isFirstLoad && !newPRs.isEmpty {
                for pr in newPRs {
                    await NotificationService.shared.sendNotification(
                        title: "New PR for Review",
                        body: "\(pr.title)\n\(pr.author?.displayName ?? "") - \(pr.repository.shortName)",
                        url: pr.url,
                        action: .soundAndBanner
                    )
                }
            }

            for pr in prs {
                seenPRIds.insert(pr.id)
            }

            isFirstLoad = false

            await NotificationService.shared.updateBadge(count: prs.count)

        } catch {
            print("Polling error: \(error)")
        }
    }

    func markAsSeen(prId: String) {
        seenPRIds.insert(prId)
    }

    func resetSeenPRs() {
        seenPRIds.removeAll()
        isFirstLoad = true
    }
}
