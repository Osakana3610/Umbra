// Defines a shared, data-driven item filter used by equipment and reward lists.

import SwiftUI

struct ItemBrowserFilter: Equatable {
    var hiddenCategories: Set<ItemCategory> = []
    var hiddenTitleIDs: Set<Int> = []
    var showsOnlySuperRare = false

    mutating func showAll() {
        hiddenCategories.removeAll()
        hiddenTitleIDs.removeAll()
        showsOnlySuperRare = false
    }

    mutating func hideAllCategories(using catalog: ItemBrowserFilterCatalog) {
        hiddenCategories = Set(catalog.categories)
    }

    mutating func hideAllTitles(using catalog: ItemBrowserFilterCatalog) {
        hiddenTitleIDs = Set(catalog.titles.map(\.id))
    }

    func matches(
        itemID: CompositeItemID,
        category: ItemCategory
    ) -> Bool {
        guard hiddenCategories.contains(category) == false else {
            return false
        }
        guard showsOnlySuperRare == false || itemID.hasSuperRareIdentity else {
            return false
        }

        return itemID.titleIDs.contains { hiddenTitleIDs.contains($0) == false }
    }

    func isActive(in catalog: ItemBrowserFilterCatalog) -> Bool {
        showsOnlySuperRare
            || hiddenCategories.isDisjoint(with: Set(catalog.categories)) == false
            || hiddenTitleIDs.isDisjoint(with: Set(catalog.titles.map(\.id))) == false
    }
}

struct ItemBrowserFilterCatalog: Equatable {
    struct TitleEntry: Identifiable, Equatable {
        let id: Int
        let label: String
    }

    let categories: [ItemCategory]
    let titles: [TitleEntry]

    init<S: Sequence>(
        itemIDs: S,
        masterData: MasterData
    ) where S.Element == CompositeItemID {
        let itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        let uniqueItemIDs = Array(Set(itemIDs))

        categories = Set(uniqueItemIDs.compactMap { itemsByID[$0.baseItemId]?.category })
            .sorted { $0.sortOrder < $1.sortOrder }

        titles = masterData.titles.map { title in
            TitleEntry(
                id: title.id,
                label: title.key == "untitled" ? "無称号" : title.name
            )
        }
    }

    var hasOptions: Bool {
        categories.isEmpty == false
    }
}

struct ItemBrowserFilterButton: View {
    let catalog: ItemBrowserFilterCatalog
    @Binding var filter: ItemBrowserFilter

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .fontWeight(filter.isActive(in: catalog) ? .semibold : .regular)
        }
        .accessibilityLabel("アイテムフィルター")
        .sheet(isPresented: $isPresented) {
            ItemBrowserFilterSheet(
                catalog: catalog,
                filter: $filter
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ItemBrowserFilterSheet: View {
    let catalog: ItemBrowserFilterCatalog
    @Binding var filter: ItemBrowserFilter

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("超レアのみ表示", isOn: $filter.showsOnlySuperRare)
                } footer: {
                    Text("超レア付きのアイテムだけを表示します。")
                }

                Section {
                    FilterSectionActionRow(
                        onShowAll: { filter.hiddenCategories.removeAll() },
                        onHideAll: { filter.hideAllCategories(using: catalog) }
                    )

                    ForEach(catalog.categories, id: \.self) { category in
                        Toggle(category.displayName, isOn: categoryBinding(category))
                    }
                } header: {
                    Text("カテゴリ")
                }

                Section {
                    FilterSectionActionRow(
                        onShowAll: { filter.hiddenTitleIDs.removeAll() },
                        onHideAll: { filter.hideAllTitles(using: catalog) }
                    )

                    ForEach(catalog.titles) { title in
                        Toggle(title.label, isOn: titleBinding(title.id))
                    }
                } header: {
                    Text("称号")
                }

                Section {
                    Button("フィルターを解除", role: .destructive) {
                        filter.showAll()
                    }
                }
            }
            .navigationTitle("アイテムフィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func categoryBinding(_ category: ItemCategory) -> Binding<Bool> {
        Binding(
            get: { filter.hiddenCategories.contains(category) == false },
            set: { isVisible in
                if isVisible {
                    filter.hiddenCategories.remove(category)
                } else {
                    filter.hiddenCategories.insert(category)
                }
            }
        )
    }

    private func titleBinding(_ titleID: Int) -> Binding<Bool> {
        Binding(
            get: { filter.hiddenTitleIDs.contains(titleID) == false },
            set: { isVisible in
                if isVisible {
                    filter.hiddenTitleIDs.remove(titleID)
                } else {
                    filter.hiddenTitleIDs.insert(titleID)
                }
            }
        )
    }
}

private struct FilterSectionActionRow: View {
    let onShowAll: () -> Void
    let onHideAll: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("すべてON", action: onShowAll)
            Button("すべてOFF", action: onHideAll)
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
    }
}

private extension CompositeItemID {
    var titleIDs: [Int] {
        [baseTitleId, jewelTitleId].filter { $0 > 0 }
    }

    var hasSuperRareIdentity: Bool {
        baseSuperRareId > 0 || jewelSuperRareId > 0
    }
}
