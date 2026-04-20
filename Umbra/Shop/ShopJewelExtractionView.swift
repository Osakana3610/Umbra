// Presents jewel-enhanced items and lets the player detach the socketed jewel back into inventory.

import SwiftUI

struct ShopJewelExtractionView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var loadError: String?
    @State private var itemFilter = ItemBrowserFilter()
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var pendingExtraction: PendingJewelExtraction?
    @State private var currentFilterCatalog = ItemBrowserFilterOptions(
        itemIDs: [CompositeItemID](),
        masterData: MasterData.current
    )
    @State private var visibleSections: [ShopEnhancementSection] = []

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.equipmentStore = equipmentStore
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        List {
            Section {
                Text("宝石強化されたアイテムから宝石を外します。ベースアイテムは現在の所持場所のまま残り、外した宝石はインベントリへ戻ります。")
                    .foregroundStyle(.secondary)
            }

            if let message = currentErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            if visibleSections.isEmpty {
                Section("宝石を外す") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleSections) { section in
                    if #available(iOS 26.0, *) {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                extractionRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: visibleSections))
                    } else {
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                extractionRow(for: row)
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
        .navigationTitle("宝石を外す")
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
            pendingExtraction?.title ?? "",
            isPresented: Binding(
                get: { pendingExtraction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingExtraction = nil
                    }
                }
            ),
            presenting: pendingExtraction
        ) { extraction in
            Button("外す") {
                equipmentStore.extractJewel(
                    itemID: extraction.itemID,
                    characterId: extraction.characterId,
                    masterData: masterData,
                    rosterStore: rosterStore
                )
                pendingExtraction = nil
                dismiss()
            }

            Button("キャンセル", role: .cancel) {
                pendingExtraction = nil
            }
        } message: { extraction in
            Text(extraction.message)
        }
        .task {
            do {
                try equipmentStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
        .task(
            id: ShopEnhancementPresentationInput(
                itemFilter: itemFilter,
                searchText: "",
                inventoryRevision: equipmentStore.contentRevision,
                rosterRevision: rosterStore.contentRevision
            )
        ) {
            rebuildPresentation()
        }
    }

    private var currentErrorMessage: String? {
        loadError ?? equipmentStore.lastOperationError
    }

    private func rebuildPresentation() {
        let inventoryItems = equipmentStore.displayOrderedInventoryItems
        let inventoryIDs = inventoryItems
            .filter { $0.itemID.jewelItemId > 0 }
            .map(\.itemID)
        let equippedIDs = rosterStore.characters.flatMap { character in
            character.orderedEquippedItemStacks.map(\.itemID)
        }
        .filter { $0.jewelItemId > 0 }

        currentFilterCatalog = ItemBrowserFilterOptions(
            itemIDs: inventoryIDs + equippedIDs,
            masterData: masterData
        )

        visibleSections = ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            item.itemID.jewelItemId > 0
                && itemFilter.matches(itemID: item.itemID, category: item.category)
        }
    }

    private var emptyStateMessage: String {
        if itemFilter.isActive(in: currentFilterCatalog) {
            return "フィルター条件に一致する宝石強化済みアイテムがありません。"
        }

        return "宝石強化されたアイテムがありません。"
    }

    @ViewBuilder
    private func extractionRow(for row: ShopEnhancementRow) -> some View {
        Button {
            pendingExtraction = PendingJewelExtraction(
                itemID: row.itemID,
                characterId: characterId(for: row),
                title: "宝石を外す",
                message: [
                    "対象: \(row.displayName)",
                    "結果(ベースアイテム): \(nameResolver.displayName(for: baseItemID(for: row.itemID)))",
                    "返却宝石: \(nameResolver.displayName(for: jewelItemID(for: row.itemID)))",
                    "この内容で宝石を外しますか？"
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

    private func characterId(for row: ShopEnhancementRow) -> Int? {
        switch row {
        case .inventory:
            nil
        case .equipped(_, let characterId, _, _):
            characterId
        }
    }

    private func baseItemID(for itemID: CompositeItemID) -> CompositeItemID {
        CompositeItemID(
            baseSuperRareId: itemID.baseSuperRareId,
            baseTitleId: itemID.baseTitleId,
            baseItemId: itemID.baseItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
    }

    private func jewelItemID(for itemID: CompositeItemID) -> CompositeItemID {
        CompositeItemID(
            baseSuperRareId: itemID.jewelSuperRareId,
            baseTitleId: itemID.jewelTitleId,
            baseItemId: itemID.jewelItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
    }
}

private struct PendingJewelExtraction: Identifiable {
    let itemID: CompositeItemID
    let characterId: Int?
    let title: String
    let message: String

    var id: String {
        if let characterId {
            return "\(itemID.stableKey)|\(characterId)"
        }
        return itemID.stableKey
    }
}
