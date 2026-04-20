// Presents the first jewel-enhancement screen where the player chooses the base item to modify.
// Inventory and equipped rows are shown in one ordering so the player can start enhancement from
// either a shared stack or an item currently worn by a character.

import SwiftUI

struct ShopJewelEnhancementView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    @State private var loadError: String?
    @State private var itemFilter = ItemBrowserFilter()
    @State private var presentedItemDetail: ItemDetailSheetPresentation?

    var body: some View {
        List {
            Section {
                Text("強化したいアイテムを選ぶと、次の画面で組み合わせる宝石を選べます。宝石の基本能力値はそのまま、戦闘能力値は半分が加算されます。")
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("宝石を外す") {
                    ShopJewelExtractionView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                }
            }

            if let message = currentErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            if !equipmentStore.isLoaded {
                Section("宝石強化") {
                    ProgressView()
                }
            } else if baseSections.isEmpty {
                Section("ベースアイテム") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(baseSections) { section in
                    if #available(iOS 26.0, *) {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                baseRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: baseSections))
                    } else {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                baseRow(for: row)
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
        .navigationTitle("宝石強化")
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
            itemIDs: enhancementItemIDs,
            masterData: masterData
        )
    }

    private var enhancementItemIDs: [CompositeItemID] {
        let inventoryIDs = inventoryItems
            .filter { item in
                item.itemID.jewelItemId == 0 && item.category != .jewel
            }
            .map(\.itemID)
        let equippedIDs = rosterStore.characters.flatMap { character in
            character.orderedEquippedItemStacks.map(\.itemID)
        }
        .filter { itemID in
            guard let baseItem = masterData.items.first(where: { $0.id == itemID.baseItemId }) else {
                return false
            }
            return itemID.jewelItemId == 0 && baseItem.category != .jewel
        }
        // The filter catalog spans both inventory and equipped candidates because the next screen can
        // start from either source.
        return inventoryIDs + equippedIDs
    }

    private var baseSections: [ShopEnhancementSection] {
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            // The base item must be a non-jewel identity that has not already been jewel-enhanced.
            item.itemID.jewelItemId == 0
                && item.category != .jewel
                && itemFilter.matches(itemID: item.itemID, category: item.category)
        }
    }

    private var emptyStateMessage: String {
        if itemFilter.isActive(in: currentFilterCatalog) {
            return "フィルター条件に一致するベースアイテムがありません。"
        }

        return "宝石強化できる在庫がありません。"
    }

    @ViewBuilder
    private func baseRow(
        for row: ShopEnhancementRow
    ) -> some View {
        switch row {
        case .inventory, .equipped:
            NavigationLink {
                ShopJewelEnhancementJewelSelectionView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    baseRow: row
                )
            } label: {
                ShopEnhancementDetailRow(row: row) { itemID in
                    presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
