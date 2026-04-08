// Owns shop stock state and coordinates buy/sell operations with roster and inventory refreshes.

import Foundation
import Observation

@MainActor
@Observable
final class ShopInventoryStore {
    private let service: GuildService

    private var itemsByID: [Int: MasterData.Item] = [:]
    private var nameResolver: EquipmentDisplayNameResolver?

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var shopItemsBySection: [EquipmentSectionKey: [EquipmentCachedItem]] = [:]
    private(set) var orderedSectionKeys: [EquipmentSectionKey] = []

    init(service: GuildService) {
        self.service = service
    }

    func loadIfNeeded(masterData: MasterData) throws {
        guard !isLoaded else {
            return
        }

        try reload(masterData: masterData)
    }

    func reload(masterData: MasterData) throws {
        configure(masterData: masterData)

        let stock = try service.loadShopInventoryStacks(masterData: masterData)
        var groupedItems: [EquipmentSectionKey: [EquipmentCachedItem]] = [:]
        for stack in stock.normalizedCompositeItemStacks() {
            let item = cachedItem(for: stack.itemID, quantity: stack.count)
            groupedItems[item.sectionKey, default: []].append(item)
        }

        for key in groupedItems.keys {
            groupedItems[key]?.sort(by: EquipmentCachedItem.isOrderedBefore)
        }

        shopItemsBySection = groupedItems
        orderedSectionKeys = groupedItems.keys.sorted(by: EquipmentSectionKey.isOrderedBefore)
        isLoaded = true
    }

    func buy(
        itemID: CompositeItemID,
        count: Int,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore
    ) {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                try service.buyShopItem(itemID: itemID, count: count, masterData: masterData)
                rosterStore.refreshFromPersistence()
                try equipmentStore.reload(masterData: masterData)
                try reload(masterData: masterData)
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func sell(
        itemID: CompositeItemID,
        count: Int,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore
    ) {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                try service.sellInventoryItem(itemID: itemID, count: count, masterData: masterData)
                rosterStore.refreshFromPersistence()
                try equipmentStore.reload(masterData: masterData)
                try reload(masterData: masterData)
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    private func configure(masterData: MasterData) {
        if itemsByID.isEmpty {
            itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        }
        if nameResolver == nil {
            nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
        }
    }

    private func cachedItem(
        for itemID: CompositeItemID,
        quantity: Int
    ) -> EquipmentCachedItem {
        let baseItem = itemsByID[itemID.baseItemId]!

        return EquipmentCachedItem(
            itemID: itemID,
            stackKey: itemID.stableKey,
            equippedRowID: itemID.stableKey + "|shop",
            quantity: quantity,
            displayName: nameResolver?.displayName(for: itemID) ?? baseItem.name,
            category: baseItem.category,
            rarity: baseItem.rarity
        )
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
