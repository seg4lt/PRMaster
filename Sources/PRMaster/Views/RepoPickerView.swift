import SwiftUI

struct RepoPickerView: View {
    @ObservedObject var viewModel: AISummaryViewModel
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)

                if viewModel.selectedRepos.isEmpty {
                    Text("Select repositories...")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.selectedRepos.count) selected")
                        .foregroundColor(.primary)
                }

                Spacer()

                if viewModel.isLoadingRepos {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isExpanded {
                dropdownContent
                    .offset(y: 36)
            }
        }
    }

    private var dropdownContent: some View {
        VStack(spacing: 8) {
            RepoListPicker(
                availableRepos: viewModel.availableRepos,
                selectedRepos: viewModel.selectedReposBinding,
                searchText: viewModel.repoSearchTextBinding,
                height: 180
            )
        }
        .padding(10)
        .frame(width: 280)
        .background(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
