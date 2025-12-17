import Foundation
import SwiftUI

@MainActor
class PRListViewModel: ObservableObject {
    static let shared = PRListViewModel()

    @Published var toReviewPRs: [PullRequest] = []
    @Published var isLoading = false
    @Published var currentUser: String?

    private init() {}

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            currentUser = try await GitHubService.shared.getCurrentUser()
            toReviewPRs = try await GitHubService.shared.getReviewRequests()
        } catch {
            print("Error loading data: \(error)")
        }
    }
}
