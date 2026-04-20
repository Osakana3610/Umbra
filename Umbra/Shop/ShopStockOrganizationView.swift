// Presents the stock-organization screen that converts large rare shop stacks into cat tickets.
// The screen previews only stacks that are close enough to matter so the player can focus on
// exchange-ready stock instead of every low-count item in the shop inventory.

import SwiftUI

struct ShopStockOrganizationView: View {
    private static let previewThreshold = 80

    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let shopStore: ShopInventoryStore

    @State private var loadError: String?
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var visibleSections: [StockOrganizationSection] = []

    private let itemsByID: [Int: MasterData.Item]

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        shopStore: ShopInventoryStore
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.shopStore = shopStore
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
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
                if visibleSections.isEmpty {
                    Section("対象スタック") {
                        Text("在庫整理できる在庫がありません。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(visibleSections) { section in
                        if #available(iOS 26.0, *) {
                            Section(section.key.title) {
                                ForEach(section.rows) { row in
                                    stockOrganizationRow(for: row)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            }
                            .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: visibleSections))
                        } else {
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
        }
        .listStyle(.insetGrouped)
        .equipmentSectionIndexVisibility()
        .playerStatusContentInsetAware()
        .navigationTitle("在庫整理")
        .navigationBarTitleDisplayMode(.inline)
        .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
        .task {
            do {
                try shopStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
        .task(id: shopStore.contentRevision) {
            rebuildVisibleSections()
        }
    }

    private var currentErrorMessage: String? {
        loadError ?? shopStore.lastOperationError
    }

    private func rebuildVisibleSections() {
        guard shopStore.isLoaded else {
            visibleSections = []
            return
        }

        let rows: [StockOrganizationRow] = shopStore.displayOrderedShopItems.compactMap { item in
            guard item.rarity != .normal,
                  let baseItem = itemsByID[item.itemID.baseItemId] else {
                return nil
            }

            let availableExchangeCount = item.quantity / ShopPricingCalculator.stockOrganizationBundleSize
            let remainder = item.quantity % ShopPricingCalculator.stockOrganizationBundleSize
            let remainingCount = availableExchangeCount == 0
                ? ShopPricingCalculator.stockOrganizationBundleSize - item.quantity
                : remainder

            // Preview only near-threshold stacks so the list acts as a progress view toward
            // the 99-item exchange instead of duplicating the entire shop inventory browser.
            guard item.quantity >= Self.previewThreshold else {
                return nil
            }

            return StockOrganizationRow(
                item: item,
                itemID: item.itemID,
                summaryText: [
                    "\(item.rarity.displayName) / 在庫 \(item.quantity)個",
                    "交換 \(ShopPricingCalculator.stockOrganizationTicketCount(for: baseItem.basePrice))枚",
                    availableExchangeCount > 0
                        ? "交換可能 \(availableExchangeCount)回 / 余り \(remainder)個"
                        : "あと \(remainingCount)個"
                ].joined(separator: " / "),
                availableExchangeCount: availableExchangeCount
            )
        }

        let grouped = Dictionary(grouping: rows) { row in
            row.item.sectionKey
        }
        visibleSections = grouped.keys
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
                    // One tap performs exactly one 99-item conversion even when the stack could be
                    // exchanged multiple times, which keeps the mutation explicit.
                    shopStore.organize(
                        itemID: row.itemID,
                        masterData: masterData,
                        rosterStore: rosterStore
                    )
                }
                .disabled(shopStore.isMutating || row.availableExchangeCount == 0)
            }

            ShopItemDetailButton(itemID: row.itemID) { itemID in
                presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
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

extension StockOrganizationSection: EquipmentSectionIndexable {}
