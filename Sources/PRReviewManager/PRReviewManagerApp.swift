import SwiftUI
import SwiftData

@main
struct PRReviewManagerApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: NotificationFilter.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text("PR Review Manager - Loading...")
                .frame(width: 400, height: 500)
        } label: {
            Image(systemName: "arrow.triangle.pull")
        }
        .menuBarExtraStyle(.window)
    }
}
