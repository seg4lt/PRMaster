import SwiftUI

struct GHStatusSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub CLI Status")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                switch viewModel.ghStatus {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking...")
                        .foregroundStyle(.secondary)
                case .authenticated(let user):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Authenticated as @\(user)")
                case .notAuthenticated:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("Not authenticated")
                    Button("Run gh auth login") {
                        viewModel.openTerminalWithCommand("gh auth login")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .notInstalled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("gh CLI not installed")
                    Button("Install Homebrew gh") {
                        viewModel.openTerminalWithCommand("brew install gh")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.caption)
        }
    }
}
