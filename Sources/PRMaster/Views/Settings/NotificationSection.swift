import SwiftUI

struct NotificationSection: View {
    @Binding var notificationsEnabled: Bool
    @Binding var onlyFilterNotifications: Bool
    @Binding var myPRNotificationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("Enable notifications", isOn: $notificationsEnabled)

            if notificationsEnabled {
                Toggle("Only notify for filter matches", isOn: $onlyFilterNotifications)
                    .padding(.leading, 16)

                if onlyFilterNotifications {
                    Text("Notifications only sent when a PR matches an enabled filter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                } else {
                    Text("Notifications sent for all new/updated PRs in To Review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Toggle("Notify on my PR activity", isOn: $myPRNotificationsEnabled)

            Text("Get notified when someone reviews or comments on your PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
    }
}
