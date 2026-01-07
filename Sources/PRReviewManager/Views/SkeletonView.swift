import SwiftUI

struct SkeletonPRRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status indicator placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: .random(in: 150...250), height: 13)

                // Metadata row placeholder
                HStack(spacing: 6) {
                    // Repo badge
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 11)

                    // Author
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 50, height: 11)

                    // Time
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 30, height: 11)
                }
            }

            Spacer()

            // Status badge placeholder
            Capsule()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 70, height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(
            Animation.easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

struct SkeletonListView: View {
    let count: Int

    init(count: Int = 5) {
        self.count = count
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 1) {
                ForEach(0..<count, id: \.self) { _ in
                    SkeletonPRRow()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EnrichingIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
            Text("Loading details...")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
