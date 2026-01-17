import SwiftUI

struct AISummarySkeleton: View {
    @State private var animating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 120, height: 16)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 60, height: 20)

                Spacer()
            }

            Divider()

            // Content skeleton - multiple lines
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 200, height: 12)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .opacity(animating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true),
            value: animating
        )
        .onAppear {
            animating = true
        }
    }
}
