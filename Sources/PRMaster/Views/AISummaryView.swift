import SwiftUI

struct AISummaryView: View {
    @ObservedObject private var viewModel = AISummaryViewModel.shared
    @State private var isRepoPickerExpanded = false
    @State private var copiedAll = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .zIndex(1) // Keep dropdown above dismiss layer
            Divider()
            contentSection
        }
        .background {
            // Full-screen tap to dismiss dropdown
            if isRepoPickerExpanded {
                Color.black.opacity(0.001) // Nearly invisible but captures taps
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRepoPickerExpanded = false
                        }
                    }
            }
        }
        .task {
            await viewModel.checkProviderStatusIfNeeded()
            await viewModel.loadReposIfNeeded()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Summary")
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
                    Text("Repositories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RepoPickerView(viewModel: viewModel, isExpanded: $isRepoPickerExpanded)
                        .frame(width: 250)
                }

                Spacer()

                Button {
                    viewModel.generateSummaries()
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
                .disabled(viewModel.isLoading || viewModel.isCheckingProvider || viewModel.selectedRepos.isEmpty)

                if viewModel.isLoading {
                    Button("Cancel") {
                        viewModel.cancelGeneration()
                    }
                    .buttonStyle(.bordered)
                } else if !viewModel.summaries.isEmpty {
                    Button {
                        copyAllSummaries()
                    } label: {
                        Image(systemName: copiedAll ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("Copy all summaries")

                    Button {
                        viewModel.clearCache()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Clear cached summaries")
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var providerStatusBadge: some View {
        let providerName = viewModel.selectedProviderType.displayName
        HStack(spacing: 4) {
            if viewModel.isCheckingProvider {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Checking \(providerName)...")
            } else {
                switch viewModel.providerStatus {
                case .available:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(providerName) Ready")
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
        }
        .font(.caption)
    }

    private var contentSection: some View {
        VStack(spacing: 0) {
            // Always show error banner if present
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.error = nil
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .padding(8)
                .background(Color.red.opacity(0.1))
            }

            // Show status message during loading
            if let statusMessage = viewModel.statusMessage {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.05))
            }

            // Main content
            if viewModel.summaries.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.summaries.enumerated()), id: \.element.id) { index, summary in
                            SummaryCard(
                                summary: summary,
                                onRetry: {
                                    viewModel.retrySummary(at: index)
                                },
                                onDelete: {
                                    viewModel.deleteSummary(id: summary.id)
                                },
                                onUpdate: { startDate, endDate in
                                    viewModel.updateSummary(id: summary.id, startDate: startDate, endDate: endDate)
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

            Text("Select repositories and a date range,\nthen click Generate to summarize your commits")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.selectedRepos.isEmpty && !viewModel.isLoadingRepos {
                Text("↑ Select at least one repository to get started")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyAllSummaries() {
        let allText = viewModel.summaries.compactMap { summary -> String? in
            guard case .completed(let text) = summary.status else { return nil }
            return text
        }.joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)

        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedAll = false
        }
    }
}
