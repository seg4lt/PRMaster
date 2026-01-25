import SwiftUI

struct ReviewChecklistPanel: View {
    @ObservedObject var viewModel: ReviewChecklistViewModel
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Checklist")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Ensure you've completed all review tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                    // Progress overview
                    progressOverview

                    // Checklist sections
                    ForEach(ChecklistCategory.allCases, id: \.self) { category in
                        checklistSection(category: category)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Text("Press Esc or click outside to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Review Later") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Complete Review") {
                    onComplete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmitReview)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 700)
    }

    private var progressOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review Progress")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(viewModel.completionPercentage * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.completionPercentage == 1.0 ? .green : .orange)
            }

            ProgressView(value: viewModel.completionPercentage, total: 1.0)
                .progressViewStyle(.linear)
                .tint(viewModel.completionPercentage == 1.0 ? .green : .orange)

            if !viewModel.canSubmitReview {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Complete all applicable items before submitting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func checklistSection(category: ChecklistCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                    .font(.headline)

                Text(category.rawValue)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Items in this category
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.items.filter { $0.item.category == category }) { itemStatus in
                    ChecklistItemRow(status: itemStatus)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ChecklistItemRow: View {
    let status: ChecklistItemStatus

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: status.isComplete ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundColor(status.isComplete ? .green : (status.isApplicable ? Color.secondary : Color.gray.opacity(0.5)))

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.item.rawValue)
                        .font(.body)
                        .strikethrough(status.isComplete)
                        .foregroundStyle(status.isApplicable ? .primary : .secondary)

                    if !status.isApplicable {
                        Text("N/A")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                if let details = status.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Icon
            Image(systemName: status.item.icon)
                .font(.caption)
                .foregroundColor(status.isComplete ? .green : .secondary)
                .opacity(status.isApplicable ? 1.0 : 0.5)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ReviewChecklistPanel(viewModel: ReviewChecklistViewModel(), onComplete: {})
}
