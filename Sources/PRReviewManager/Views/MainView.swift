import SwiftUI
import SwiftData

struct MainView: View {
    @StateObject private var viewModel = PRListViewModel.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                Text("To Review").tag(0)
                Text("My PRs").tag(1)
                Text("Filters").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            TabView(selection: $selectedTab) {
                PRListView(prs: viewModel.toReviewPRs)
                    .tag(0)
                MyPRsView()
                    .tag(1)
                FiltersView()
                    .tag(2)
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}
