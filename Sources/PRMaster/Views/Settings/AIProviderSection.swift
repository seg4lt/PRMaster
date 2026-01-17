import SwiftUI

struct AIProviderSection: View {
    @Binding var selectedProvider: String
    @Binding var selectedModel: String
    @Binding var tokenRatio: Int
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Provider")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProviderType.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)

            statusView

            modelSelectionView

            if selectedProvider == AIProviderType.copilot.rawValue {
                tokenRatioView
            }

            Text("Used for AI Weekly Summary feature")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 6) {
            switch viewModel.aiProviderStatus {
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(viewModel.providerDisplayName(for: selectedProvider)) ready")
            case .notInstalled(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(msg)
                installButton
            case .notAuthenticated(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(msg)
                loginButton
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(msg)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var installButton: some View {
        if selectedProvider == AIProviderType.claude.rawValue {
            Button("Install Claude Code") {
                if let url = URL(string: "https://claude.ai/code") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Install Copilot CLI") {
                if let url = URL(string: "https://githubnext.com/projects/copilot-cli") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var loginButton: some View {
        if selectedProvider == AIProviderType.claude.rawValue {
            Button("Run claude login") {
                viewModel.openTerminalWithCommand("claude login")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Run copilot auth") {
                viewModel.openTerminalWithCommand("copilot auth")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var modelSelectionView: some View {
        if let providerType = AIProviderType(rawValue: selectedProvider) {
            HStack {
                Text("Model:")
                    .font(.caption)

                if providerType == .copilot {
                    if viewModel.isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading models...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if viewModel.copilotModels.isEmpty {
                        TextField("Model name", text: $selectedModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                    } else {
                        Picker("", selection: $selectedModel) {
                            ForEach(viewModel.copilotModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                } else {
                    Picker("", selection: $selectedModel) {
                        ForEach(providerType.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
            .padding(.top, 4)
        }
    }

    private var tokenRatioView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper("Token ratio: \(tokenRatio) chars/token", value: $tokenRatio, in: 1...4)

            Text("Lower = more accurate for code, fewer tokens per batch")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("If you get 'exceeds token limit' errors, try lowering this value")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .padding(.top, 4)
    }
}
