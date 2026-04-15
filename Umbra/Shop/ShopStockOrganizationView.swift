// Presents cat-ticket exchanges for exact 6-value shop stacks without aggregating across stacks.

import SwiftUI

struct ShopStockOrganizationView: View {
    private static let previewThreshold = 80

    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let shopStore: ShopInventoryStore

    @State private var loadError: String?
    @State private var presentedItemDetail: StockOrganizationPresentedItemDetail?

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        shopStore: ShopInventoryStore
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.shopStore = shopStore
    }

    var body: some View {
        List {
            if let message = currentErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("同じレアアイテムを99個集めるとキャット・チケットと交換できます。")
                    .foregroundStyle(.secondary)
            }

            if !shopStore.isLoaded {
                Section("在庫整理") {
                    ProgressView()
                }
            } else {
                if rows.isEmpty {
                    Section("対象スタック") {
                        Text("在庫整理できる在庫がありません。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sections) { section in
                        Section(section.key.title) {
                            ForEach(section.rows) { row in
                                stockOrganizationRow(for: row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .playerStatusContentInsetAware()
        .navigationTitle("在庫整理")
        .navigationBarTitleDisplayMode(.inline)
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
                try shopStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var currentErrorMessage: String? {
        loadError ?? shopStore.lastOperationError
    }

    private var rows: [StockOrganizationRow] {
        shopStore.orderedSectionKeys
            .flatMap { sectionKey in
                (shopStore.shopItemsBySection[sectionKey] ?? []).compactMap { item in
                    guard item.rarity != .normal,
                          let baseItem = masterData.items.first(where: { $0.id == item.itemID.baseItemId }) else {
                        return nil
                    }

                    let availableExchangeCount = item.quantity / ShopCatalog.stockOrganizationBundleSize
                    let remainder = item.quantity % ShopCatalog.stockOrganizationBundleSize
                    let remainingCount = availableExchangeCount == 0
                        ? ShopCatalog.stockOrganizationBundleSize - item.quantity
                        : remainder

                    guard item.quantity >= Self.previewThreshold else {
                        return nil
                    }

                    return StockOrganizationRow(
                        item: item,
                        itemID: item.itemID,
                        summaryText: [
                            "\(item.rarity.displayName) / 在庫 \(item.quantity)個",
                            "交換 \(ShopCatalog.stockOrganizationTicketCount(for: baseItem.basePrice))枚",
                            availableExchangeCount > 0
                                ? "交換可能 \(availableExchangeCount)回 / 余り \(remainder)個"
                                : "あと \(remainingCount)個"
                        ].joined(separator: " / "),
                        availableExchangeCount: availableExchangeCount
                    )
                }
            }
    }

    private var sections: [StockOrganizationSection] {
        let grouped = Dictionary(grouping: rows, by: \.item.sectionKey)
        return grouped.keys
            .sorted(by: EquipmentSectionKey.isOrderedBefore)
            .map { key in
                StockOrganizationSection(
                    key: key,
                    rows: grouped[key]?.sorted { lhs, rhs in
                        lhs.itemID.isOrdered(before: rhs.itemID)
                    } ?? []
                )
            }
    }

    private func stockOrganizationRow(
        for row: StockOrganizationRow
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ShopItemSummaryContent(
                    item: row.item,
                    detailText: row.summaryText
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(shopStore.isMutating ? "整理中..." : "99個整理する") {
                    shopStore.organize(
                        itemID: row.itemID,
                        masterData: masterData,
                        rosterStore: rosterStore
                    )
                }
                .disabled(shopStore.isMutating || row.availableExchangeCount == 0)
            }

            ShopItemDetailButton(itemID: row.itemID) { itemID in
                presentedItemDetail = StockOrganizationPresentedItemDetail(itemID: itemID)
            }
        }
    }
}

private struct StockOrganizationRow: Identifiable {
    let item: EquipmentCachedItem
    let itemID: CompositeItemID
    let summaryText: String
    let availableExchangeCount: Int

    var id: String {
        itemID.stableKey
    }
}

private struct StockOrganizationSection: Identifiable {
    let key: EquipmentSectionKey
    let rows: [StockOrganizationRow]

    var id: EquipmentSectionKey {
        key
    }
}

private struct StockOrganizationPresentedItemDetail: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}
