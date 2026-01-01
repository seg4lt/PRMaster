import SwiftUI
import SwiftData
import AppKit

class FullWindowController: NSObject, NSWindowDelegate {
    static let shared = FullWindowController()
    private var windowController: NSWindowController?

    func openWindow(modelContainer: ModelContainer) {
        NSApp.setActivationPolicy(.regular)

        if let window = windowController?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PR Review Manager"
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowController = nil
    }
}

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
            MainView()
                .modelContainer(modelContainer)
                .frame(width: 500, height: 700)
        } label: {
            Image(systemName: "arrow.triangle.pull")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @StateObject private var viewModel = PRListViewModel.shared

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.pull")
            if !viewModel.toReviewPRs.isEmpty {
                Text("\(viewModel.toReviewPRs.count)")
            }
        }
    }
}
