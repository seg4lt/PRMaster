import SwiftUI

struct AISummaryView: View {
    @StateObject private var viewModel = AISummaryViewModel()
    @State private var providerStatus: AIProviderStatus = .notInstalled(message: "Checking...")

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
        }
        .task {
            await checkProviderStatus()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Weekly Summary")
                    .font(.headline)
                Spacer()
                providerStatusBadge
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $viewModel.startDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("End Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $viewModel.endDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Repos (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("owner/repo, owner/repo2", text: $viewModel.repoFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.generateSummaries()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isLoading ? "Generating..." : "Generate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading || !providerStatus.isAvailable)

                if viewModel.isLoading {
                    Button("Cancel") {
                        viewModel.cancelGeneration()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var providerStatusBadge: some View {
        HStack(spacing: 4) {
            switch providerStatus {
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Claude Ready")
            case .notInstalled(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(msg)
            case .notAuthenticated(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(msg)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(msg)
            }
        }
        .font(.caption)
    }

    private var contentSection: some View {
        Group {
            if viewModel.weeklySummaries.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.weeklySummaries.enumerated()), id: \.element.id) { index, summary in
                            WeeklySummaryCard(
                                summary: summary,
                                onRetry: {
                                    Task {
                                        await viewModel.retrySummary(at: index)
                                    }
                                }
                            )
                        }

                        if viewModel.hasMorePending {
                            AISummarySkeleton()
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.purple.opacity(0.5))

            Text("No summaries yet")
                .font(.headline)

            Text("Select a date range and click Generate to\nsummarize your commit activity by week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func checkProviderStatus() async {
        let provider = AIProviderType.claude.createProvider()
        providerStatus = await provider.checkAvailability()
    }
}
