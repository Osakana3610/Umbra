// Defines the store's initial stock and temporary buy/sell pricing rules.

import Foundation

enum ShopCatalog {
    static let sellbackRate = 0.05
    static let superRareValueMultiplier = 2.0
    static let stockOrganizationBundleSize = 99

    static func initialInventory(masterData: MasterData) -> [CompositeItemStack] {
        masterData.items
            .map { CompositeItemStack(itemID: .baseItem(itemId: $0.id), count: 1) }
            .sorted { $0.itemID.isOrdered(before: $1.itemID) }
    }

    static func purchasePrice(
        for itemID: CompositeItemID,
        masterData: MasterData
    ) -> Int {
        // Catalog values can rise above the economy ceiling once titles, super rares, and jewel
        // enhancement stack, so clamp before exposing any store-facing price.
        let rawCatalogPrice = Int(catalogValue(for: itemID, masterData: masterData).rounded())
        return max(1, min(rawCatalogPrice, EconomyPricing.maximumEconomicPrice))
    }

    static func sellPrice(
        for itemID: CompositeItemID,
        masterData: MasterData
    ) -> Int {
        // Sellback is computed from the already-clamped purchase price so capped items do not pay
        // out as if their uncapped theoretical value were reachable in gold.
        max(1, Int((Double(purchasePrice(for: itemID, masterData: masterData)) * sellbackRate).rounded()))
    }

    static func stockOrganizationTicketCount(
        for basePrice: Int
    ) -> Int {
        switch basePrice {
        case 80_000...319_999:
            1
        case 320_000...1_279_999:
            2
        case 1_280_000...5_119_999:
            3
        case 5_120_000...20_479_999:
            4
        case 20_480_000...81_919_999:
            5
        default:
            6
        }
    }

    private static func catalogValue(
        for itemID: CompositeItemID,
        masterData: MasterData
    ) -> Double {
        let itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        let titlesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0) })
        return componentValue(
            itemId: itemID.baseItemId,
            titleId: itemID.baseTitleId,
            superRareId: itemID.baseSuperRareId,
            basePriceScale: 1.0,
            itemsByID: itemsByID,
            titlesByID: titlesByID
        ) + componentValue(
            itemId: itemID.jewelItemId,
            titleId: itemID.jewelTitleId,
            superRareId: itemID.jewelSuperRareId,
            basePriceScale: 0.5,
            itemsByID: itemsByID,
            titlesByID: titlesByID
        )
    }

    private static func componentValue(
        itemId: Int,
        titleId: Int,
        superRareId: Int,
        basePriceScale: Double,
        itemsByID: [Int: MasterData.Item],
        titlesByID: [Int: MasterData.Title]
    ) -> Double {
        guard let item = itemsByID[itemId] else {
            return 0
        }

        // Jewel enhancement contributes at half weight while title and super-rare bonuses scale
        // whichever component they are attached to.
        let titleMultiplier = titleId > 0 ? (titlesByID[titleId]?.positiveMultiplier ?? 1.0) : 1.0
        let superRareMultiplier = superRareId > 0 ? superRareValueMultiplier : 1.0
        return Double(item.basePrice) * basePriceScale * titleMultiplier * superRareMultiplier
    }
}
