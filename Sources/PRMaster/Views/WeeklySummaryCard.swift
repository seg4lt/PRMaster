import SwiftUI
import AppKit

struct WeeklySummaryCard: View {
    let summary: WeeklySummary
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(summary.week.weekLabel)
                    .font(.headline)

                Text("\(summary.week.commits.count) commits")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                // Copy button for completed summaries
                if case .completed(let text) = summary.status {
                    Button {
                        copyToClipboard(text)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(copied ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy summary")
                }
            }

            Divider()

            // Content based on status
            statusContent
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusContent: some View {
        switch summary.status {
        case .pending:
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Waiting...")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating summary...")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

        case .completed(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

        case .error(let message):
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Error")
                            .foregroundColor(.red)
                    }
                    .font(.subheadline.weight(.medium))

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
