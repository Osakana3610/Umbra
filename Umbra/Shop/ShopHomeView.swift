// Hosts the store tab's top-level navigation and the trading flows reachable from it.
// Keeps the in-game shop menu structure in one place so equipment changes, buy/sell,
// enhancement, and stock-management entry points stay ordered consistently.

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
        .playerStatusContentInsetAware()
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
        .playerStatusContentInsetAware()
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
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var presentedPurchaseSheet: PresentedPurchaseSheet?
    @State private var presentedSaleSheet: PresentedSaleSheet?
    @State private var currentFilterCatalog: ItemBrowserFilterOptions
    @State private var visibleSections: [TradeSection] = []

    init(
        mode: ShopTradeMode,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore,
        shopStore: ShopInventoryStore
    ) {
        self.mode = mode
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.equipmentStore = equipmentStore
        self.shopStore = shopStore
        _currentFilterCatalog = State(
            initialValue: ItemBrowserFilterOptions(itemIDs: [CompositeItemID](), masterData: masterData)
        )
    }

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
            .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
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
                    // The trading screen derives filters and row affordances from both stores, so
                    // load them together before presenting either buy or sell content.
                    try equipmentStore.loadIfNeeded(masterData: masterData)
                    try shopStore.loadIfNeeded(masterData: masterData)
                    loadError = nil
                } catch {
                    loadError = error.localizedDescription
                }
            }
            .task(id: tradePresentationInputs) {
                rebuildTradePresentation()
            }
    }

    private var tradeList: some View {
        return Group {
            if #available(iOS 26.0, *) {
                tradeListView(showsSectionIndex: true)
            } else {
                tradeListView(showsSectionIndex: false)
            }
        }
        .listStyle(.insetGrouped)
        .equipmentSectionIndexVisibility()
        .playerStatusContentInsetAware()
    }

    private func tradeListView(
        showsSectionIndex: Bool
    ) -> some View {
        List {
            if let loadError {
                Section(mode.rawValue) {
                    Text(loadError)
                        .foregroundStyle(.red)
                }
            } else if !isCurrentSourceLoaded {
                Section(mode.rawValue) {
                    ShopTradeLoadingRow()
                }
            } else if visibleSections.isEmpty {
                Section(mode.rawValue) {
                    Text(emptyStateMessage(filterCatalog: currentFilterCatalog))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleSections) { section in
                    tradeSection(section, in: visibleSections, showsSectionIndex: showsSectionIndex)
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
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        mode == .buy ? "商店在庫を検索" : "所持アイテムを検索"
    }

    private var tradePresentationInputs: TradePresentationInputs {
        TradePresentationInputs(
            searchText: trimmedSearchText,
            itemFilter: itemFilter,
            sectionKeys: sourceSectionKeys,
            itemsBySection: sourceItemsBySection
        )
    }

    private var isCurrentSourceLoaded: Bool {
        switch mode {
        case .buy:
            shopStore.isLoaded
        case .sell:
            equipmentStore.isLoaded
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

    private func rebuildTradePresentation() {
        let itemIDs = sourceSectionKeys.flatMap { sourceItemsBySection[$0]?.map(\.itemID) ?? [] }
        currentFilterCatalog = ItemBrowserFilterOptions(itemIDs: itemIDs, masterData: masterData)
        visibleSections = sourceSectionKeys.compactMap { key in
            let rows = (sourceItemsBySection[key] ?? []).filter(matchesFilters)
            guard !rows.isEmpty else {
                return nil
            }
            return TradeSection(key: key, rows: rows)
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

    private func emptyStateMessage(filterCatalog: ItemBrowserFilterOptions) -> String {
        if !trimmedSearchText.isEmpty || itemFilter.isActive(in: filterCatalog) {
            return mode == .buy
                ? "検索条件またはフィルター条件に一致する商店在庫はありません。"
                : "検索条件またはフィルター条件に一致する所持アイテムはありません。"
        }

        return mode == .buy
            ? "商店在庫はありません。"
            : "売却できる所持アイテムはありません。"
    }

    @ViewBuilder
    private func tradeSection(
        _ section: TradeSection,
        in sections: [TradeSection],
        showsSectionIndex: Bool
    ) -> some View {
        if showsSectionIndex {
            if #available(iOS 26.0, *) {
                // The section index is only available on the newer list implementation, so keep the
                // fallback path structurally identical and vary only the index decoration.
                Section(section.key.title) {
                    tradeRows(for: section)
                }
                .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: sections))
            }
        } else {
            Section(section.key.title) {
                tradeRows(for: section)
            }
        }
    }

    private func tradeRows(for section: TradeSection) -> some View {
        ForEach(section.rows) { item in
            tradeRow(for: item)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
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
            isMutating: shopStore.isMutating,
            onPresentPurchaseSheet: { selectedItem in
                presentedPurchaseSheet = PresentedPurchaseSheet(item: selectedItem)
            },
            onPresentSaleSheet: { selectedItem in
                presentedSaleSheet = PresentedSaleSheet(item: selectedItem)
            },
            onShowDetail: { itemID in
                presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
            }
        )
    }
}

private struct ShopTradeItemRow: View {
    let item: EquipmentCachedItem
    let masterData: MasterData
    let mode: ShopTradeMode
    let isMutating: Bool
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
        let sellPrice = ShopPricingCalculator.sellPrice(for: item.itemID, masterData: masterData)
        switch mode {
        case .buy:
            let purchasePrice = ShopPricingCalculator.purchasePrice(for: item.itemID, masterData: masterData)
            return "在庫 \(item.quantity.formatted()) / 購入 \(purchasePrice.formatted())G / 売却 \(sellPrice.formatted())G"
        case .sell:
            return "所持 \(item.quantity.formatted()) / 売却 \(sellPrice.formatted())G"
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
                Text("在庫数 \(item.quantity.formatted())")
                    .font(.body)
                    .padding(.vertical, 4)
            }

            Section("購入情報") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1個あたり \(unitPurchasePrice.formatted())G")
                    Text("全部購入 \(allPurchasePrice.formatted())G")
                    Text("所持金 \(availableGold.formatted())G")
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
        ShopPricingCalculator.purchasePrice(for: item.itemID, masterData: masterData)
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
                Text("所持数 \(item.quantity.formatted())")
                    .font(.body)
                    .padding(.vertical, 4)
            }

            Section("売却情報") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1個あたり \(unitSellPrice.formatted())G")
                    Text("全部売却 \(allSellPrice.formatted())G")
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
        ShopPricingCalculator.sellPrice(for: item.itemID, masterData: masterData)
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

private struct TradePresentationInputs: Equatable {
    let searchText: String
    let itemFilter: ItemBrowserFilter
    let sectionKeys: [EquipmentSectionKey]
    let itemsBySection: [EquipmentSectionKey: [EquipmentCachedItem]]
}

extension TradeSection: EquipmentSectionIndexable {}
