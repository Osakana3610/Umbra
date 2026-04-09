// Defines the store's initial stock and temporary buy/sell pricing rules.

import Foundation

enum ShopCatalog {
    static let purchasePriceDivisor = 100.0
    static let sellbackRate = 0.5
    static let titleValueMultiplier = 1.2
    static let superRareValueMultiplier = 1.5
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
        max(1, Int((catalogValue(for: itemID, masterData: masterData) / purchasePriceDivisor).rounded()))
    }

    static func sellPrice(
        for itemID: CompositeItemID,
        masterData: MasterData
    ) -> Int {
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
        let baseValue = Double(itemsByID[itemID.baseItemId]?.basePrice ?? 0)
        let jewelValue = Double(itemsByID[itemID.jewelItemId]?.basePrice ?? 0)
        let titleMultiplier = pow(
            titleValueMultiplier,
            Double(nonZeroCount(itemID.baseTitleId, itemID.jewelTitleId))
        )
        let superRareMultiplier = pow(
            superRareValueMultiplier,
            Double(nonZeroCount(itemID.baseSuperRareId, itemID.jewelSuperRareId))
        )
        return (baseValue + jewelValue) * titleMultiplier * superRareMultiplier
    }

    private static func nonZeroCount(_ values: Int...) -> Int {
        values.reduce(into: 0) { partialResult, value in
            if value > 0 {
                partialResult += 1
            }
        }
    }
}
