// Presents the recipe-based enhancement browsers while recipes are not yet implemented.
// The view still exposes the candidate inventory and equipped rows so future enhancement flows can
// reuse the same browsing and filtering structure without redesigning the screen.

import SwiftUI

struct ShopNormalSynthesisView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    var body: some View {
        ShopRecipeEnhancementBrowserView(
            title: "通常合成",
            unavailableMessage: "レシピ未定義のため実行できません。",
            masterData: masterData,
            rosterStore: rosterStore,
            equipmentStore: equipmentStore
        )
    }
}

struct ShopTitleInheritanceView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    var body: some View {
        ShopRecipeEnhancementBrowserView(
            title: "称号継承",
            unavailableMessage: "レシピ未定義のため実行できません。",
            masterData: masterData,
            rosterStore: rosterStore,
            equipmentStore: equipmentStore
        )
    }
}

private struct ShopRecipeEnhancementBrowserView: View {
    let title: String
    let unavailableMessage: String
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    @State private var itemFilter = ItemBrowserFilter()
    @State private var loadError: String?
    @State private var presentedItemDetail: ItemDetailSheetPresentation?

    var body: some View {
        List {
            Section {
                Text(unavailableMessage)
                    .foregroundStyle(.secondary)
            }

            if let currentErrorMessage {
                Section {
                    Text(currentErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            if !equipmentStore.isLoaded {
                Section(title) {
                    ProgressView()
                }
            } else if sections.isEmpty {
                Section("対象アイテム") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sections) { section in
                    if #available(iOS 26.0, *) {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                itemRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: sections))
                    } else {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                itemRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .equipmentSectionIndexVisibility()
        .playerStatusContentInsetAware()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentFilterCatalog.hasOptions {
                ToolbarItem(placement: .topBarTrailing) {
                    ItemBrowserFilterButton(
                        catalog: currentFilterCatalog,
                        filter: $itemFilter
                    )
                }
            }
        }
        .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
        .task {
            do {
                try equipmentStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var inventoryItems: [EquipmentCachedItem] {
        equipmentStore.displayOrderedInventoryItems
    }

    private var currentErrorMessage: String? {
        loadError ?? equipmentStore.lastOperationError
    }

    private var currentFilterCatalog: ItemBrowserFilterOptions {
        ItemBrowserFilterOptions(
            // Recipe enhancement can eventually consume both inventory items and currently equipped
            // items, so the filter catalog is built from both sources now.
            itemIDs: inventoryItems.map(\.itemID) + rosterStore.characters.flatMap { character in
                character.orderedEquippedItemStacks.map(\.itemID)
            },
            masterData: masterData
        )
    }

    private var sections: [ShopEnhancementSection] {
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            itemFilter.matches(itemID: item.itemID, category: item.category)
        }
    }

    private var emptyStateMessage: String {
        if itemFilter.isActive(in: currentFilterCatalog) {
            return "フィルター条件に一致するアイテムがありません。"
        }

        return "対象アイテムがありません。"
    }

    @ViewBuilder
    private func itemRow(
        for row: ShopEnhancementRow
    ) -> some View {
        ShopEnhancementDetailRow(row: row) { itemID in
            presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
        }
    }
}
