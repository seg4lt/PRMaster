import SwiftUI

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    let onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))

            Text(error.message)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer()

            if let actionLabel = error.actionLabel, let action = onAction {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            if error.isRetryable, let retry = onRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ErrorBannerList: View {
    let errors: [AppError]
    let onDismiss: (AppError) -> Void
    let onRetry: () -> Void

    var body: some View {
        if !errors.isEmpty {
            VStack(spacing: 4) {
                ForEach(errors) { error in
                    ErrorBanner(
                        error: error,
                        onDismiss: { onDismiss(error) },
                        onRetry: error.isRetryable ? onRetry : nil,
                        onAction: actionForError(error)
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    private func actionForError(_ error: AppError) -> (() -> Void)? {
        switch error {
        case .ghCLINotFound:
            return { openURL("https://cli.github.com") }
        case .ghCLINotAuthenticated:
            return { openTerminal("gh auth login") }
        default:
            return nil
        }
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
