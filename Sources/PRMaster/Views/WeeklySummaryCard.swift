import SwiftUI
import AppKit

struct SummaryCard: View {
    let summary: DateRangeSummary
    let onRetry: () -> Void
    let onDelete: () -> Void
    let onUpdate: (Date, Date) -> Void

    @State private var copied = false
    @State private var showingUpdatePopover = false
    @State private var newStartDate: Date
    @State private var newEndDate: Date

    init(summary: DateRangeSummary, onRetry: @escaping () -> Void, onDelete: @escaping () -> Void, onUpdate: @escaping (Date, Date) -> Void) {
        self.summary = summary
        self.onRetry = onRetry
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self._newStartDate = State(initialValue: summary.dateRange.startDate)
        self._newEndDate = State(initialValue: summary.dateRange.endDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(summary.dateRange.dateLabel)
                    .font(.headline)

                Text("\(summary.dateRange.commits.count) commits")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                // Action buttons for completed summaries
                if case .completed(let text) = summary.status {
                    HStack(spacing: 8) {
                        // Delete button
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete summary")

                        // Copy button
                        Button {
                            copyToClipboard(text)
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundColor(copied ? .green : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy summary")

                        // Update button with popover
                        Button {
                            // Reset dates to current summary's dates
                            newStartDate = summary.dateRange.startDate
                            newEndDate = summary.dateRange.endDate
                            showingUpdatePopover = true
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Re-generate with new date range")
                        .popover(isPresented: $showingUpdatePopover, arrowEdge: .bottom) {
                            updatePopoverContent
                        }
                    }
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

    private var updatePopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update Date Range")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $newStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $newEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            HStack {
                Button("Cancel") {
                    showingUpdatePopover = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Re-generate") {
                    showingUpdatePopover = false
                    onUpdate(newStartDate, newEndDate)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
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
