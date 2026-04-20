// Presents the second jewel-enhancement screen where the player picks the jewel for one selected
// base item.
// This screen mirrors the base-item browser so both inventory jewels and equipped jewels can be
// chosen, then stages the exact mutation payload for a confirmation alert.

import SwiftUI

struct ShopJewelEnhancementJewelSelectionView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let baseRow: ShopEnhancementRow

    @Environment(\.dismiss) private var dismiss
    @State private var itemFilter = ItemBrowserFilter()
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var pendingEnhancement: PendingJewelEnhancement?

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore,
        baseRow: ShopEnhancementRow
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.equipmentStore = equipmentStore
        self.baseRow = baseRow
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        List {
            Section {
                Text("選んだ宝石を組み合わせると、確認後に宝石強化を実行します。ベースアイテム1個に宝石1個を組み合わせます。")
                    .foregroundStyle(.secondary)
            }

            if let message = equipmentStore.lastOperationError {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("ベースアイテム") {
                ShopEnhancementDetailRow(row: baseRow) { itemID in
                    presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                }
            }

            if jewelSections.isEmpty {
                Section("宝石") {
                    Text(jewelEmptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(jewelSections) { section in
                    if #available(iOS 26.0, *) {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                jewelRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: jewelSections))
                    } else {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                jewelRow(for: row)
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
        .navigationTitle("宝石を選ぶ")
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
        .alert(
            pendingEnhancement?.title ?? "",
            isPresented: Binding(
                get: { pendingEnhancement != nil },
                set: { isPresented in
                    // The confirmation alert is driven by optional state so dismissing it must
                    // also clear the pending enhancement payload.
                    if !isPresented {
                        pendingEnhancement = nil
                    }
                }
            ),
            presenting: pendingEnhancement
        ) { enhancement in
            Button("強化する") {
                equipmentStore.enhanceWithJewel(
                    baseItemID: baseRow.itemID,
                    baseCharacterId: baseCharacterId,
                    jewelItemID: enhancement.jewelItemID,
                    jewelCharacterId: enhancement.jewelCharacterId,
                    masterData: masterData,
                    rosterStore: rosterStore
                )
                pendingEnhancement = nil
                dismiss()
            }

            Button("キャンセル", role: .cancel) {
                pendingEnhancement = nil
            }
        } message: { enhancement in
            Text(enhancement.message)
        }
    }

    private var inventoryItems: [EquipmentCachedItem] {
        equipmentStore.displayOrderedInventoryItems
    }

    private var currentFilterCatalog: ItemBrowserFilterOptions {
        ItemBrowserFilterOptions(
            itemIDs: jewelItemIDs,
            masterData: masterData
        )
    }

    private var jewelItemIDs: [CompositeItemID] {
        let inventoryIDs = inventoryItems
            .filter { $0.category == .jewel && $0.itemID.jewelItemId == 0 }
            .map(\.itemID)
        let equippedIDs = rosterStore.characters.flatMap { character in
            character.orderedEquippedItemStacks.map(\.itemID)
        }
        .filter { itemID in
            guard let baseItem = masterData.items.first(where: { $0.id == itemID.baseItemId }) else {
                return false
            }
            return itemID.jewelItemId == 0 && baseItem.category == .jewel
        }
        // Filter choices are based on all jewels that could legally be consumed, regardless of
        // whether they currently live in inventory or on a character.
        return inventoryIDs + equippedIDs
    }

    private var jewelSections: [ShopEnhancementSection] {
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            // Jewel inputs follow the same "plain identity only" rule as base items; already enhanced
            // gear cannot be consumed as the jewel ingredient.
            item.itemID.jewelItemId == 0
                && item.category == .jewel
                && itemFilter.matches(itemID: item.itemID, category: item.category)
        }
    }

    private var jewelEmptyStateMessage: String {
        if itemFilter.isActive(in: currentFilterCatalog) {
            return "フィルター条件に一致する宝石がありません。"
        }

        return "使える宝石がありません。"
    }

    @ViewBuilder
    private func jewelRow(
        for row: ShopEnhancementRow
    ) -> some View {
        switch row {
        case .inventory(let item):
            Button {
                let resultItemID = resultItemID(jewelItemID: item.itemID)

                // The confirmation message is built from the resolved display name so the player sees
                // the final composite identity before committing the mutation.
                pendingEnhancement = PendingJewelEnhancement(
                    jewelItemID: item.itemID,
                    jewelCharacterId: nil,
                    title: "宝石強化",
                    message: [
                        "ベースアイテム: \(baseRow.displayName)",
                        "宝石: \(item.displayName)",
                        "結果: \(nameResolver.displayName(for: resultItemID))",
                        "この内容で宝石強化しますか？"
                    ].joined(separator: "\n")
                )
            } label: {
                ShopEnhancementDetailRow(row: row) { itemID in
                    presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(equipmentStore.isMutating)
        case .equipped(let item, let characterId, _, _):
            Button {
                let resultItemID = resultItemID(jewelItemID: item.itemID)

                pendingEnhancement = PendingJewelEnhancement(
                    jewelItemID: item.itemID,
                    jewelCharacterId: characterId,
                    title: "宝石強化",
                    message: [
                        "ベースアイテム: \(baseRow.displayName)",
                        "宝石: \(item.displayName)",
                        "結果: \(nameResolver.displayName(for: resultItemID))",
                        "この内容で宝石強化しますか？"
                    ].joined(separator: "\n")
                )
            } label: {
                ShopEnhancementDetailRow(row: row) { itemID in
                    presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(equipmentStore.isMutating)
        }
    }

    private func resultItemID(
        jewelItemID: CompositeItemID
    ) -> CompositeItemID {
        return CompositeItemID(
            baseSuperRareId: baseRow.itemID.baseSuperRareId,
            baseTitleId: baseRow.itemID.baseTitleId,
            baseItemId: baseRow.itemID.baseItemId,
            // The jewel contributes only its own title and super-rare parts into the resulting
            // composite identity; the base side stays unchanged.
            jewelSuperRareId: jewelItemID.baseSuperRareId,
            jewelTitleId: jewelItemID.baseTitleId,
            jewelItemId: jewelItemID.baseItemId
        )
    }

    private var baseCharacterId: Int? {
        switch baseRow {
        case .inventory:
            nil
        case .equipped(_, let characterId, _, _):
            characterId
        }
    }
}

private struct PendingJewelEnhancement: Identifiable {
    let jewelItemID: CompositeItemID
    let jewelCharacterId: Int?
    let title: String
    let message: String

    var id: String {
        jewelItemID.stableKey
    }
}
