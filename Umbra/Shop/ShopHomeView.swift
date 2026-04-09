// Hosts the store tab's equipment access and item trading screens.

import SwiftUI

struct ShopHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore

    var body: some View {
        List {
            Section {
                NavigationLink("装備を変更する", destination: {
                    ShopEquipmentCharacterListView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                })
            } header: {
                Text("装備")
            }

            Section {
                NavigationLink("アイテムを購入する", destination: {
                    ShopTradingView(
                        mode: .buy,
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore,
                        shopStore: shopStore
                    )
                })
            } header: {
                Text("購入")
            }

            Section {
                NavigationLink("アイテムを売却する", destination: {
                    ShopTradingView(
                        mode: .sell,
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore,
                        shopStore: shopStore
                    )
                })
            } header: {
                Text("売却")
            }

            Section {
                NavigationLink("通常合成", destination: {
                    ShopNormalSynthesisView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                })

                NavigationLink("称号継承", destination: {
                    ShopTitleInheritanceView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                })

                NavigationLink("宝石強化", destination: {
                    ShopJewelEnhancementView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                })
            } header: {
                Text("強化")
            }

            Section {
                NavigationLink("自動売却", destination: {
                    ShopAutoSellView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore,
                        shopStore: shopStore
                    )
                })

                NavigationLink("在庫整理", destination: {
                    ShopStockOrganizationView(
                        masterData: masterData,
                        rosterStore: rosterStore,
                        shopStore: shopStore
                    )
                })
            } header: {
                Text("管理")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("商店")
    }
}

private struct ShopEquipmentCharacterListView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

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
            if rosterStore.characters.isEmpty {
                ContentUnavailableView(
                    "キャラクターがいません",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            } else {
                ForEach(rosterStore.characters) { character in
                    NavigationLink {
                        CharacterEquipmentView(
                            characterId: character.characterId,
                            masterData: masterData,
                            rosterStore: rosterStore,
                            equipmentStore: equipmentStore
                        )
                    } label: {
                        EquipmentCharacterRow(
                            character: character,
                            masterData: masterData,
                            nameResolver: nameResolver
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("装備")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum ShopTradeMode: String, CaseIterable, Identifiable {
    case buy = "購入"
    case sell = "売却"

    var id: String {
        rawValue
    }
}

private struct PresentedSaleSheet: Identifiable {
    let item: EquipmentCachedItem

    var id: String {
        item.id
    }
}

private struct PresentedPurchaseSheet: Identifiable {
    let item: EquipmentCachedItem

    var id: String {
        item.id
    }
}

private struct ShopTradingView: View {
    let mode: ShopTradeMode
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore

    @State private var itemFilter = ItemBrowserFilter()
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var presentedItemDetail: TradePresentedItemDetail?
    @State private var presentedPurchaseSheet: PresentedPurchaseSheet?
    @State private var presentedSaleSheet: PresentedSaleSheet?

    var body: some View {
        tradeList
            .searchable(text: $searchText, prompt: searchPrompt)
            .navigationTitle(mode.rawValue)
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
            .sheet(item: $presentedPurchaseSheet) { presentedPurchaseSheet in
                NavigationStack {
                    ShopPurchaseSheet(
                        item: presentedPurchaseSheet.item,
                        masterData: masterData,
                        availableGold: rosterStore.playerState?.gold ?? 0,
                        onBuyCount: performPurchase
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $presentedSaleSheet) { presentedSaleSheet in
                NavigationStack {
                    ShopSaleSheet(
                        item: presentedSaleSheet.item,
                        masterData: masterData,
                        onSellCount: performSale
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .task {
                do {
                    try equipmentStore.loadIfNeeded(masterData: masterData)
                    try shopStore.loadIfNeeded(masterData: masterData)
                    loadError = nil
                } catch {
                    loadError = error.localizedDescription
                }
            }
    }

    private var tradeList: some View {
        let sections = visibleSections

        return List {
            if let loadError {
                Section(mode.rawValue) {
                    Text(loadError)
                        .foregroundStyle(.red)
                }
            } else if !isCurrentSourceLoaded {
                Section(mode.rawValue) {
                    ShopTradeLoadingRow()
                }
            } else if sections.isEmpty {
                Section(mode.rawValue) {
                    Text(emptyStateMessage(filterCatalog: currentFilterCatalog))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sections) { section in
                    Section(section.key.title) {
                        ForEach(section.rows) { item in
                            tradeRow(for: item)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }

            if let error = shopStore.lastOperationError,
               !error.isEmpty {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        mode == .buy ? "商店在庫を検索" : "所持アイテムを検索"
    }

    private var isCurrentSourceLoaded: Bool {
        switch mode {
        case .buy:
            shopStore.isLoaded
        case .sell:
            equipmentStore.isLoaded
        }
    }

    private var currentFilterCatalog: ItemBrowserFilterCatalog {
        let itemIDs = sourceItems.map(\.itemID)
        return ItemBrowserFilterCatalog(itemIDs: itemIDs, masterData: masterData)
    }

    private var sourceItems: [EquipmentCachedItem] {
        switch mode {
        case .buy:
            shopStore.orderedSectionKeys.flatMap { shopStore.shopItemsBySection[$0] ?? [] }
        case .sell:
            equipmentStore.orderedSectionKeys.flatMap { equipmentStore.inventoryItemsBySection[$0] ?? [] }
        }
    }

    private var visibleSections: [TradeSection] {
        sourceSectionKeys.compactMap { key in
            let rows = (sourceItemsBySection[key] ?? []).filter(matchesFilters)
            guard !rows.isEmpty else {
                return nil
            }
            return TradeSection(key: key, rows: rows)
        }
    }

    private var sourceSectionKeys: [EquipmentSectionKey] {
        switch mode {
        case .buy:
            shopStore.orderedSectionKeys
        case .sell:
            equipmentStore.orderedSectionKeys
        }
    }

    private var sourceItemsBySection: [EquipmentSectionKey: [EquipmentCachedItem]] {
        switch mode {
        case .buy:
            shopStore.shopItemsBySection
        case .sell:
            equipmentStore.inventoryItemsBySection
        }
    }

    private func matchesFilters(_ item: EquipmentCachedItem) -> Bool {
        guard itemFilter.matches(itemID: item.itemID, category: item.category) else {
            return false
        }

        guard trimmedSearchText.isEmpty || item.displayName.localizedCaseInsensitiveContains(trimmedSearchText) else {
            return false
        }

        return true
    }

    private func emptyStateMessage(filterCatalog: ItemBrowserFilterCatalog) -> String {
        if !trimmedSearchText.isEmpty || itemFilter.isActive(in: filterCatalog) {
            return mode == .buy
                ? "検索条件またはフィルター条件に一致する商店在庫はありません。"
                : "検索条件またはフィルター条件に一致する所持アイテムはありません。"
        }

        return mode == .buy
            ? "商店在庫はありません。"
            : "売却できる所持アイテムはありません。"
    }

    private func canAffordPurchase(_ item: EquipmentCachedItem) -> Bool {
        guard mode == .buy else {
            return true
        }

        return (rosterStore.playerState?.gold ?? 0) >= ShopCatalog.purchasePrice(
            for: item.itemID,
            masterData: masterData
        )
    }

    private func performTrade(itemID: CompositeItemID) {
        _ = itemID
    }

    private func performPurchase(itemID: CompositeItemID, count: Int) {
        shopStore.buy(
            itemID: itemID,
            count: count,
            masterData: masterData,
            rosterStore: rosterStore,
            equipmentStore: equipmentStore
        )
    }

    private func performSale(itemID: CompositeItemID, count: Int) {
        shopStore.sell(
            itemID: itemID,
            count: count,
            masterData: masterData,
            rosterStore: rosterStore,
            equipmentStore: equipmentStore
        )
    }

    private func tradeRow(for item: EquipmentCachedItem) -> some View {
        ShopTradeItemRow(
            item: item,
            masterData: masterData,
            mode: mode,
            canAffordPurchase: canAffordPurchase(item),
            isMutating: shopStore.isMutating,
            onTrade: performTrade,
            onPresentPurchaseSheet: { selectedItem in
                presentedPurchaseSheet = PresentedPurchaseSheet(item: selectedItem)
            },
            onPresentSaleSheet: { selectedItem in
                presentedSaleSheet = PresentedSaleSheet(item: selectedItem)
            },
            onShowDetail: { itemID in
                presentedItemDetail = TradePresentedItemDetail(itemID: itemID)
            }
        )
    }
}

private struct ShopTradeItemRow: View {
    let item: EquipmentCachedItem
    let masterData: MasterData
    let mode: ShopTradeMode
    let canAffordPurchase: Bool
    let isMutating: Bool
    let onTrade: (CompositeItemID) -> Void
    let onPresentPurchaseSheet: (EquipmentCachedItem) -> Void
    let onPresentSaleSheet: (EquipmentCachedItem) -> Void
    let onShowDetail: (CompositeItemID) -> Void

    var body: some View {
        switch mode {
        case .buy:
            buyRow
        case .sell:
            sellRow
        }
    }

    private var buyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            itemSummary
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            detailButton
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMutating else {
                return
            }

            onPresentPurchaseSheet(item)
        }
    }

    private var sellRow: some View {
        HStack(alignment: .center, spacing: 12) {
            itemSummary
                .frame(maxWidth: .infinity, alignment: .leading)

            detailButton
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMutating else {
                return
            }

            onPresentSaleSheet(item)
        }
    }

    private var itemSummary: some View {
        ShopItemSummaryContent(
            item: item,
            detailText: detailText
        )
    }

    private var detailButton: some View {
        ShopItemDetailButton(
            itemID: item.itemID,
            onShowDetail: onShowDetail
        )
    }

    private var detailText: String {
        let sellPrice = ShopCatalog.sellPrice(for: item.itemID, masterData: masterData)
        switch mode {
        case .buy:
            let purchasePrice = ShopCatalog.purchasePrice(for: item.itemID, masterData: masterData)
            return "在庫 \(item.quantity) / 購入 \(purchasePrice)G / 売却 \(sellPrice)G"
        case .sell:
            return "所持 \(item.quantity) / 売却 \(sellPrice)G"
        }
    }

    private var isTradeDisabled: Bool {
        switch mode {
        case .buy:
            isMutating || !canAffordPurchase
        case .sell:
            isMutating
        }
    }
}

private struct ShopPurchaseSheet: View {
    let item: EquipmentCachedItem
    let masterData: MasterData
    let availableGold: Int
    let onBuyCount: (CompositeItemID, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("在庫数 \(item.quantity)")
                    .font(.body)
                    .padding(.vertical, 4)
            }

            Section("購入情報") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1個あたり \(unitPurchasePrice)G")
                    Text("全部購入 \(allPurchasePrice)G")
                    Text("所持金 \(availableGold)G")
                }
                .font(.body)
                .padding(.vertical, 4)
            }

            Section("購入する") {
                Button("1個購入") {
                    buyAndDismiss(count: 1)
                }
                .disabled(availableGold < unitPurchasePrice)

                if item.quantity >= 10 {
                    Button("10個購入") {
                        buyAndDismiss(count: 10)
                    }
                    .disabled(item.quantity < 10 || availableGold < unitPurchasePrice * 10)
                }

                Button("全部購入") {
                    buyAndDismiss(count: item.quantity)
                }
                .disabled(availableGold < allPurchasePrice)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unitPurchasePrice: Int {
        ShopCatalog.purchasePrice(for: item.itemID, masterData: masterData)
    }

    private var allPurchasePrice: Int {
        unitPurchasePrice * item.quantity
    }

    private func buyAndDismiss(count: Int) {
        onBuyCount(item.itemID, count)
        dismiss()
    }
}

private struct ShopSaleSheet: View {
    let item: EquipmentCachedItem
    let masterData: MasterData
    let onSellCount: (CompositeItemID, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("所持数 \(item.quantity)")
                    .font(.body)
                    .padding(.vertical, 4)
            }

            Section("売却情報") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1個あたり \(unitSellPrice)G")
                    Text("全部売却 \(allSellPrice)G")
                }
                .font(.body)
                .padding(.vertical, 4)
            }

            Section("売却する") {
                Button("1個売却") {
                    sellAndDismiss(count: 1)
                }

                if item.quantity >= 10 {
                    Button("10個売却") {
                        sellAndDismiss(count: 10)
                    }
                }

                Button("全部売却") {
                    sellAndDismiss(count: item.quantity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unitSellPrice: Int {
        ShopCatalog.sellPrice(for: item.itemID, masterData: masterData)
    }

    private var allSellPrice: Int {
        unitSellPrice * item.quantity
    }

    private func sellAndDismiss(count: Int) {
        onSellCount(item.itemID, count)
        dismiss()
    }
}

private struct ShopTradeLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("アイテムを読み込み中...")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

private struct TradeSection: Identifiable {
    let key: EquipmentSectionKey
    let rows: [EquipmentCachedItem]

    var id: EquipmentSectionKey {
        key
    }
}

private struct TradePresentedItemDetail: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}
