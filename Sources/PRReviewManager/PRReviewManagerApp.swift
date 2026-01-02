import SwiftUI
import SwiftData
import AppKit
import Carbon

// App delegate to handle right-click menu on status bar and global hotkey
class AppDelegate: NSObject, NSApplicationDelegate {
    private var rightClickMenu: NSMenu?
    private var localEventMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create right-click menu
        rightClickMenu = NSMenu()
        rightClickMenu?.addItem(NSMenuItem(title: "Quit PRReviewManager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Monitor for right-clicks on status bar area
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            if let window = event.window,
               window.className.contains("NSStatusBar") || window.level == .statusBar {
                self?.rightClickMenu?.popUp(positioning: nil, at: event.locationInWindow, in: event.window?.contentView)
                return nil
            }
            return event
        }

        // Global hotkey: Option+Command+Shift+P
        setupGlobalHotkey()
    }

    private func setupGlobalHotkey() {
        let shortcutEnabled = UserDefaults.standard.object(forKey: "globalShortcutEnabled") as? Bool ?? true
        guard shortcutEnabled else { return }

        // Use Carbon hotkey API - doesn't require accessibility permissions
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5052564D) // "PRVM" as 4-char code
        hotKeyID.id = 1

        // Register: Option+Command+Shift+P
        // P = keycode 35, modifiers: cmdKey=256, shiftKey=512, optionKey=2048
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey | optionKey)
        let keyCode: UInt32 = 35 // P key

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install handler
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            NotificationCenter.default.post(name: NSNotification.Name("OpenExpandedWindow"), object: nil)
            return noErr
        }, 1, &eventType, nil, nil)

        // Register the hotkey
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
        }
    }
}

// Window controller to manage the full window
class FullWindowController: NSObject, NSWindowDelegate {
    static let shared = FullWindowController()

    private var windowController: NSWindowController?

    func openWindow(modelContainer: ModelContainer, appState: AppState) {
        // CRITICAL: Change activation policy to allow showing windows
        // MenuBarExtra apps are "accessory" by default and can't show windows
        NSApp.setActivationPolicy(.regular)

        // If window exists and is visible, just bring it to front
        if let window = windowController?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI view
        let contentView = FullWindowView()
            .modelContainer(modelContainer)
            .environmentObject(appState)
            .frame(minWidth: 800, minHeight: 600)

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PRReviewManager"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("PRReviewManagerMainWindow")
        window.delegate = self

        // Make window key and order front before creating controller
        window.makeKeyAndOrderFront(nil)

        // Create window controller and show
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Switch back to accessory mode (menu bar only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        windowController = nil
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var apiStats: (total: Int, session: Int) = (0, 0)
    @Published var apiLogs: [APICallLog] = []

    private init() {}

    func updateStats() async {
        let stats = await GitHubService.shared.getStats()
        apiStats = (stats.total, stats.session)
        apiLogs = stats.logs
    }
}

enum BadgeSource: String, CaseIterable {
    case toReview = "toReview"
    case reviewed = "reviewed"
    case myPRs = "myPRs"
    case filter = "filter"
    case none = "none"

    var displayName: String {
        switch self {
        case .toReview: return "To Review"
        case .reviewed: return "Reviewed"
        case .myPRs: return "My PRs"
        case .filter: return "Filter"
        case .none: return "None"
        }
    }

    static var allCases: [BadgeSource] {
        [.toReview, .reviewed, .myPRs, .none]  // Exclude .filter from picker
    }
}

struct BadgeSourceConfig: Codable, Identifiable {
    var id: String { source }
    var source: String
    var prefix: String
    var suffix: String
}

@main
struct PRReviewManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer
    @StateObject private var appState = AppState.shared

    init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "notificationsEnabled": true,
            "onlyFilterNotifications": false,
            "myPRNotificationsEnabled": true,
            "pollingInterval": 300.0,
            "globalShortcutEnabled": true
        ])

        do {
            modelContainer = try ModelContainer(for: NotificationFilter.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Set model container on ViewModel so it can fetch filters directly
        PRListViewModel.shared.modelContainer = modelContainer

        // Fetch data on app start
        Task {
            await PRListViewModel.shared.loadAllData()
        }

        // Listen for hotkey to open expanded window
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenExpandedWindow"),
            object: nil,
            queue: .main
        ) { [self] _ in
            FullWindowController.shared.openWindow(
                modelContainer: modelContainer,
                appState: AppState.shared
            )
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(modelContainer: modelContainer, appState: appState)
                .modelContainer(modelContainer)
                .environmentObject(appState)
                .frame(width: 500, height: 700)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @StateObject private var viewModel = PRListViewModel.shared
    @AppStorage("badgeConfig") private var badgeConfigJSON: String = "[]"
    @Query private var savedFilters: [NotificationFilter]

    private var badgeConfigs: [BadgeSourceConfig] {
        (try? JSONDecoder().decode([BadgeSourceConfig].self, from: Data(badgeConfigJSON.utf8))) ?? []
    }

    private func countFor(_ source: String) -> Int {
        if source == "toReview" {
            return viewModel.toReviewPRs.count
        } else if source == "reviewed" {
            return viewModel.reviewedPRs.count
        } else if source == "myPRs" {
            return viewModel.myOpenPRs.count
        } else if source.hasPrefix("filter:") {
            let filterIdStr = String(source.dropFirst(7))
            if let filterId = UUID(uuidString: filterIdStr),
               let filter = savedFilters.first(where: { $0.id == filterId }) {
                return viewModel.toReviewPRs.filter { filter.matches(pr: $0.pr) }.count
            }
        }
        return 0
    }

    private var badgeText: String {
        badgeConfigs.compactMap { config in
            let count = countFor(config.source)
            if count > 0 {
                return "\(config.prefix)\(count)\(config.suffix)"
            }
            return nil
        }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.pull")
            if !badgeText.isEmpty {
                Text(badgeText)
            }
        }
    }
}

struct MenuBarContentView: View {
    let modelContainer: ModelContainer
    let appState: AppState

    var body: some View {
        MainView(isCompact: true, openWindowAction: {
            FullWindowController.shared.openWindow(
                modelContainer: modelContainer,
                appState: appState
            )
        })
    }
}

struct FullWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainView(isCompact: false, showAPIStatsTab: true)
    }
}

struct APIStatsView: View {
    @State private var logs: [APICallLog] = []
    @State private var totalRequests = 0
    @State private var sessionRequests = 0
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("API Stats")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await refreshStats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            Divider()

            HStack(spacing: 20) {
                VStack {
                    Text("\(totalRequests)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(sessionRequests)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Text("Recent Calls")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if logs.isEmpty {
                VStack {
                    Spacer()
                    Text("No API calls yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(logs.reversed()) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(log.success ? .green : .red)
                                        .font(.caption)
                                    Text(log.command)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1fs", log.duration))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(DateFormatters.timeAgo(from: log.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
        }
        .task {
            await refreshStats()
        }
        .onAppear {
            // Auto-refresh every 2 seconds to catch new API calls
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    await refreshStats()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refreshStats() async {
        let stats = await GitHubService.shared.getStats()
        totalRequests = stats.total
        sessionRequests = stats.session
        logs = stats.logs
    }
}
