// Presents recipe-based enhancement placeholders while still exposing owned and equipped item usage.

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
    @State private var presentedItemDetail: PresentedRecipeEnhancementItemDetail?

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
                    Section(section.key.title) {
                        ForEach(section.rows) { row in
                            itemRow(for: row)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        .sheet(item: $presentedItemDetail) { presentedItemDetail in
            NavigationStack {
                ItemDetailView(
                    itemID: presentedItemDetail.itemID,
                    masterData: masterData
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") {
                            self.presentedItemDetail = nil
                        }
                    }
                }
            }
        }
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
        equipmentStore.orderedSectionKeys.flatMap { sectionKey in
            equipmentStore.inventoryItemsBySection[sectionKey] ?? []
        }
    }

    private var currentErrorMessage: String? {
        loadError ?? equipmentStore.lastOperationError
    }

    private var currentFilterCatalog: ItemBrowserFilterCatalog {
        ItemBrowserFilterCatalog(
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
        switch row {
        case .inventory(let item):
            HStack(alignment: .center, spacing: 12) {
                ShopEnhancementInventorySummaryContent(
                    item: item
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ShopItemDetailButton(itemID: item.itemID) { itemID in
                    presentedItemDetail = PresentedRecipeEnhancementItemDetail(itemID: itemID)
                }
            }
        case .equipped(let item, _, let characterName, let portraitAssetName):
            HStack(alignment: .center, spacing: 12) {
                ShopEnhancementEquippedRowContent(
                    item: item,
                    characterName: characterName,
                    portraitAssetName: portraitAssetName
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ShopItemDetailButton(itemID: item.itemID) { itemID in
                    presentedItemDetail = PresentedRecipeEnhancementItemDetail(itemID: itemID)
                }
            }
        }
    }
}

private struct PresentedRecipeEnhancementItemDetail: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}
