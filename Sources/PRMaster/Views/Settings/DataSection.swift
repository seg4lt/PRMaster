import SwiftUI

struct DataSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Management")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Button {
                    Task {
                        await viewModel.refreshRepoCache()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isRefreshingRepoCache {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Repository Cache")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isRefreshingRepoCache)
            }

            if let error = viewModel.repoCacheError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let cacheAge = viewModel.getRepoCacheAge() {
                Text("\(viewModel.cachedRepoCount) repos cached \(cacheAge)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Refresh if you've gained access to new repositories or organizations.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
