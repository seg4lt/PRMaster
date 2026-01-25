import SwiftUI

struct KeyboardShortcutsHelpPanel: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    navigationSection
                    fileActionsSection
                    reviewActionsSection
                    viewControlsSection
                    bulkActionsSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Text("Press ? or Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 600)
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "arrow.triangle.turns.right.circle", title: "Navigation", color: .blue)

            VStack(spacing: 8) {
                ShortcutRow(key: "1-9", description: "Jump to first 9 unviewed files")
                ShortcutRow(key: "Tab / Shift+Tab", description: "Next / previous unviewed file")
                ShortcutRow(key: "j / k", description: "Next / previous file in list")
                ShortcutRow(key: "Space", description: "Toggle current file expanded/collapsed")
                ShortcutRow(key: "n", description: "Jump to next recommended file")
                ShortcutRow(key: "g", description: "Jump to first unviewed file")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var fileActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "doc.text", title: "File Actions", color: .green)

            VStack(spacing: 8) {
                ShortcutRow(key: "v", description: "Mark current file as viewed")
                ShortcutRow(key: "Shift+V", description: "Mark current file as unviewed")
                ShortcutRow(key: "c", description: "Add comment to current line")
                ShortcutRow(key: "Cmd+I", description: "Show review statistics")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var reviewActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "checkmark.circle", title: "Review Actions", color: .purple)

            VStack(spacing: 8) {
                ShortcutRow(key: "Cmd+Return", description: "Submit review")
                ShortcutRow(key: "Cmd+Shift+A", description: "Mark all files as viewed")
                ShortcutRow(key: "Cmd+Shift+V", description: "Clear all viewed status")
                ShortcutRow(key: "Cmd+Shift+C", description: "Clear all drafts")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var viewControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "eye", title: "View Controls", color: .orange)

            VStack(spacing: 8) {
                ShortcutRow(key: "Cmd++ / Cmd+-", description: "Increase / decrease font size")
                ShortcutRow(key: "Cmd+0", description: "Reset font size to default")
                ShortcutRow(key: "f", description: "Focus search/filter")
                ShortcutRow(key: "Esc", description: "Close panels / clear filters")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var bulkActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "bolt", title: "Bulk Actions", color: .yellow)

            VStack(spacing: 8) {
                ShortcutRow(key: "Cmd+Shift+A", description: "Mark all files as viewed")
                ShortcutRow(key: "Cmd+Shift+V", description: "Clear all viewed status")
                ShortcutRow(key: "Approve All Viewed", description: "Quick approve reviewed files")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.headline)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
                .font(.body)

            Spacer()

            KeyCap(keys: key)
        }
    }
}

struct KeyCap: View {
    let keys: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(components, id: \.self) { component in
                Text(component)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var components: [String] {
        keys.split(separator: " / ").map { String($0) }
    }
}

#Preview {
    KeyboardShortcutsHelpPanel()
}
