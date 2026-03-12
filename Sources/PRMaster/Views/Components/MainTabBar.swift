import SwiftUI

/// Tab bar component for MainView
struct MainTabBar: View {
    let tabs: [Tab]
    @Binding var selectedTab: Tab
    let badgeCount: (Tab) -> Int
    let isCompact: Bool
    let lastUpdate: Date?
    let isLoading: Bool
    let isEnriching: Bool
    let onRefresh: () -> Void
    var onOpenWindow: (() -> Void)?

    @State private var currentTime = Date()

    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    count: badgeCount(tab),
                    isCompact: isCompact
                ) {
                    selectedTab = tab
                }
            }

            Spacer()

            if let lastUpdate = lastUpdate {
                Text(timeAgoText(from: lastUpdate))
                    .font(.system(size: isCompact ? 9 : 11))
                    .foregroundStyle(.tertiary)
            }

            if isCompact {
                compactActions
            }
        }
        .padding(.horizontal, isCompact ? 4 : 8)
        .padding(.vertical, isCompact ? 2 : 6)
        .frame(height: isCompact ? 28 : nil)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            currentTime = Date()
        }
    }

    @ViewBuilder
    private var compactActions: some View {
        if isLoading || isEnriching {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else {
            Button {
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }

        if let action = onOpenWindow {
            Button(action: action) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Open Full Window")
        }
    }

    private func timeAgoText(from date: Date) -> String {
        let seconds = Int(currentTime.timeIntervalSince(date))
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
}

/// Individual tab button
struct TabButton: View {
    let tab: Tab
    let isSelected: Bool
    let count: Int
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 3 : 4) {
                Image(systemName: tab.icon)
                    .font(isCompact ? .system(size: 9) : .caption)
                Text(tab.displayName(isCompact: isCompact))
                    .font(isCompact ? .system(size: 10) : .caption)
                if count > 0 {
                    Text("\(count)")
                        .font(isCompact ? .system(size: 9) : .caption2)
                        .padding(.horizontal, isCompact ? 4 : 5)
                        .padding(.vertical, isCompact ? 1 : 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .frame(height: isCompact ? 18 : nil)
            .padding(.horizontal, isCompact ? 5 : 10)
            .padding(.vertical, isCompact ? 2 : 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4 : 6))
        }
        .buttonStyle(.plain)
    }
}
