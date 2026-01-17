import SwiftUI

struct PollingSection: View {
    @Binding var pollingInterval: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh Interval")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $pollingInterval) {
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
                Text("10 minutes").tag(600.0)
                Text("15 minutes").tag(900.0)
                Text("30 minutes").tag(1800.0)
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Text("How often to check for new PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
