import SwiftUI

struct PRListView: View {
    let prs: [PullRequest]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(prs) { pr in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pr.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(pr.repository.nameWithOwner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Divider()
                }
            }
        }
    }
}
