// Presents jewel enhancement with owned and equipped items visible in the same section ordering.

import SwiftUI

struct ShopJewelEnhancementView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    @State private var loadError: String?
    @State private var itemFilter = ItemBrowserFilter()
    @State private var presentedItemDetail: JewelEnhancementPresentedItemDetail?

    var body: some View {
        List {
            Section {
                Text("強化したいアイテムを選ぶと、次の画面で組み合わせる宝石を選べます。宝石の基本能力値と戦闘能力値の半分が加算されます。")
                    .foregroundStyle(.secondary)
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
                Section("親") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(baseSections) { section in
                    Section(section.key.title) {
                        ForEach(section.rows) { row in
                            baseRow(for: row)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        return inventoryIDs + equippedIDs
    }

    private var baseSections: [ShopEnhancementSection] {
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            item.itemID.jewelItemId == 0
                && item.category != .jewel
                && itemFilter.matches(itemID: item.itemID, category: item.category)
        }
    }

    private var emptyStateMessage: String {
        if itemFilter.isActive(in: currentFilterCatalog) {
            return "フィルター条件に一致する親アイテムがありません。"
        }

        return "宝石強化できる在庫がありません。"
    }

    @ViewBuilder
    private func baseRow(
        for row: ShopEnhancementRow
    ) -> some View {
        switch row {
        case .inventory(let item):
            NavigationLink {
                ShopJewelEnhancementJewelSelectionView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    baseRow: row
                )
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ShopEnhancementInventorySummaryContent(
                        item: item
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShopItemDetailButton(itemID: item.itemID) { itemID in
                        presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
                    }
                }
            }
            .buttonStyle(.plain)
        case .equipped(let item, _, let characterName, let portraitAssetName):
            NavigationLink {
                ShopJewelEnhancementJewelSelectionView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    baseRow: row
                )
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ShopEnhancementEquippedRowContent(
                        item: item,
                        characterName: characterName,
                        portraitAssetName: portraitAssetName
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShopItemDetailButton(itemID: item.itemID) { itemID in
                        presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ShopJewelEnhancementJewelSelectionView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let baseRow: ShopEnhancementRow

    @Environment(\.dismiss) private var dismiss
    @State private var itemFilter = ItemBrowserFilter()
    @State private var presentedItemDetail: JewelEnhancementPresentedItemDetail?
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
                Text("選んだ宝石を組み合わせると、確認後に宝石強化を実行します。親1個に宝石1個を組み合わせます。")
                    .foregroundStyle(.secondary)
            }

            if let message = equipmentStore.lastOperationError {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("親") {
                switch baseRow {
                case .inventory(let item):
                    HStack(alignment: .center, spacing: 12) {
                        ShopEnhancementInventorySummaryContent(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ShopItemDetailButton(itemID: item.itemID) { itemID in
                            presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
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
                            presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
                        }
                    }
                }
            }

            if jewelSections.isEmpty {
                Section("宝石") {
                    Text(jewelEmptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(jewelSections) { section in
                    Section(section.key.title) {
                        ForEach(section.rows) { row in
                            jewelRow(for: row)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        .alert(
            pendingEnhancement?.title ?? "",
            isPresented: Binding(
                get: { pendingEnhancement != nil },
                set: { isPresented in
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
        equipmentStore.orderedSectionKeys.flatMap { sectionKey in
            equipmentStore.inventoryItemsBySection[sectionKey] ?? []
        }
    }

    private var currentFilterCatalog: ItemBrowserFilterCatalog {
        ItemBrowserFilterCatalog(
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
        return inventoryIDs + equippedIDs
    }

    private var jewelSections: [ShopEnhancementSection] {
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
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

                pendingEnhancement = PendingJewelEnhancement(
                    jewelItemID: item.itemID,
                    jewelCharacterId: nil,
                    title: "宝石強化",
                    message: [
                        "親: \(baseRow.displayName)",
                        "宝石: \(item.displayName)",
                        "結果: \(nameResolver.displayName(for: resultItemID))",
                        "この内容で宝石強化しますか？"
                    ].joined(separator: "\n")
                )
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ShopEnhancementInventorySummaryContent(
                        item: item
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShopItemDetailButton(itemID: item.itemID) { itemID in
                        presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(equipmentStore.isMutating)
        case .equipped(let item, let characterId, let characterName, let portraitAssetName):
            Button {
                let resultItemID = resultItemID(jewelItemID: item.itemID)

                pendingEnhancement = PendingJewelEnhancement(
                    jewelItemID: item.itemID,
                    jewelCharacterId: characterId,
                    title: "宝石強化",
                    message: [
                        "親: \(baseRow.displayName)",
                        "宝石: \(item.displayName)",
                        "結果: \(nameResolver.displayName(for: resultItemID))",
                        "この内容で宝石強化しますか？"
                    ].joined(separator: "\n")
                )
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ShopEnhancementEquippedRowContent(
                        item: item,
                        characterName: characterName,
                        portraitAssetName: portraitAssetName
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShopItemDetailButton(itemID: item.itemID) { itemID in
                        presentedItemDetail = JewelEnhancementPresentedItemDetail(itemID: itemID)
                    }
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

private struct JewelEnhancementPresentedItemDetail: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}
