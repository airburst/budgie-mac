import BudgieMacKit
import SwiftData
import SwiftUI

/// S-015: the category tree, filtered by the search field.
struct CategoriesPage: View {
    @Environment(AppModel.self) private var model
    @Query private var categories: [Category]
    @State private var search = ""
    @State private var selection: PersistentIdentifier?

    var body: some View {
        let nodes = CategoryTree.nodes(categories, search: search)
        Group {
            if categories.allSatisfy(\.deleted) {
                ContentUnavailableView {
                    Label("No Categories", systemImage: "folder")
                } description: {
                    Text("Categories say what money was for, like Groceries or Salary.")
                }
            } else if nodes.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(nodes, children: \.children, selection: $selection) { node in
                    CategoryRow(category: node.category)
                        .tag(node.id)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Categories")
        .navigationTitle("Categories")
    }
}

private struct CategoryRow: View {
    let category: Category

    var body: some View {
        let count = category.liveChildren.count
        HStack(spacing: Space.sm) {
            Label(category.name, systemImage: category.parent == nil ? "folder" : "tag")
            if category.kind != .expense {
                Text(category.kind == .income ? "Income" : "Transfer")
                    .font(.caption)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
            Spacer()
            if count > 0 {
                Text(count == 1 ? "1 sub-category" : "\(count) sub-categories")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
