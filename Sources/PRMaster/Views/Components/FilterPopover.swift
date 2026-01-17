import SwiftUI

/// A generic multi-select filter popover component
struct FilterPopover<Item: Hashable>: View {
    let items: [Item]
    let selectedItems: Set<Item>
    let itemLabel: (Item) -> String
    let onToggle: (Item) -> Void
    let onClearAll: () -> Void
    var maxHeight: CGFloat = 200
    var width: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Clear All") {
                onClearAll()
            }
            .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items), id: \.self) { item in
                        Button {
                            onToggle(item)
                        } label: {
                            HStack {
                                Image(systemName: selectedItems.contains(item) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedItems.contains(item) ? .accentColor : .secondary)
                                Text(itemLabel(item))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: maxHeight)
        }
        .frame(width: width)
    }
}

/// Convenience initializer for String items
extension FilterPopover where Item == String {
    init(
        items: [String],
        selectedItems: Set<String>,
        onToggle: @escaping (String) -> Void,
        onClearAll: @escaping () -> Void,
        maxHeight: CGFloat = 200,
        width: CGFloat = 180
    ) {
        self.items = items
        self.selectedItems = selectedItems
        self.itemLabel = { $0 }
        self.onToggle = onToggle
        self.onClearAll = onClearAll
        self.maxHeight = maxHeight
        self.width = width
    }
}
