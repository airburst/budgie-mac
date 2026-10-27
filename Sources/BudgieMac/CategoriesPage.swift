import BudgieMacKit
import SwiftData
import SwiftUI

/// S-015: the category tree, filtered by the search field.
struct CategoriesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Query private var categories: [Category]
    @State private var search = ""
    @State private var selection: PersistentIdentifier?

    private var selected: Category? {
        categories.first { $0.persistentModelID == selection }
    }

    @ViewBuilder private func menu(for category: Category) -> some View {
        Button("Edit Category…") { model.categorySheet = .edit(category.persistentModelID) }
        if category.parent == nil {
            Button("Add Sub-category…") { model.categorySheet = .add(parent: category.persistentModelID) }
        }
        Divider()
        let blocked = CategoryDeletion.blocked(category)
        Button("Delete…", role: .destructive) { model.deleteCategory(category, undoManager: undoManager) }
            .disabled(blocked != nil)
            .help(blocked ?? "Delete this category")
    }

    var body: some View {
        let nodes = CategoryTree.nodes(categories, search: search)
        Group {
            if categories.allSatisfy(\.softDeleted) {
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
                .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                    if let id = ids.first, let category = categories.first(where: { $0.persistentModelID == id }) {
                        menu(for: category)
                    }
                } primaryAction: { ids in
                    if let id = ids.first { model.categorySheet = .edit(id) }
                }
                .onDeleteCommand {
                    if let category = selected, CategoryDeletion.blocked(category) == nil {
                        model.deleteCategory(category, undoManager: undoManager)
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Categories")
        .toolbar {
            ToolbarItem {
                Menu("Add Category", systemImage: "plus") {
                    Button("Add Category…") { model.categorySheet = .add(parent: nil) }
                    Button("Add Sub-category…") { model.categorySheet = .add(parent: (selected?.parent ?? selected)?.persistentModelID) }
                        .disabled(selected == nil)
                } primaryAction: {
                    model.categorySheet = .add(parent: nil)
                }
                .help("Add a category")
            }
        }
        .sheet(item: Bindable(model).categorySheet) { mode in
            NavigationStack { CategorySheet(mode: mode) }
        }
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
