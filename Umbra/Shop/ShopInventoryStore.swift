// Owns shop stock state and coordinates buy/sell operations with roster and inventory refreshes.

import Foundation
import Observation

@MainActor
@Observable
final class ShopInventoryStore {
    private let service: GuildService

    private var itemsByID: [Int: MasterData.Item] = [:]
    private var nameResolver: EquipmentDisplayNameResolver?
    private var sectionKeyByItemID: [CompositeItemID: EquipmentSectionKey] = [:]

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
        var newSectionKeyByItemID: [CompositeItemID: EquipmentSectionKey] = [:]
        for stack in stock.normalizedCompositeItemStacks() {
            let item = cachedItem(for: stack.itemID, quantity: stack.count)
            groupedItems[item.sectionKey, default: []].append(item)
            newSectionKeyByItemID[item.itemID] = item.sectionKey
        }

        for key in groupedItems.keys {
            groupedItems[key]?.sort(by: EquipmentCachedItem.isOrderedBefore)
        }

        shopItemsBySection = groupedItems
        sectionKeyByItemID = newSectionKeyByItemID
        orderedSectionKeys = groupedItems.keys.sorted(by: EquipmentSectionKey.isOrderedBefore)
        isLoaded = true
    }

    func applyInventoryChanges(
        _ itemCounts: [CompositeItemID: Int],
        masterData: MasterData
    ) {
        guard isLoaded, !itemCounts.isEmpty else {
            return
        }

        configure(masterData: masterData)

        for (itemID, count) in itemCounts where count != 0 {
            if count > 0 {
                incrementInventory(itemID: itemID, by: count)
            } else {
                decrementInventory(itemID: itemID, by: -count)
            }
        }
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
                try loadIfNeeded(masterData: masterData)
                try equipmentStore.loadIfNeeded(masterData: masterData)
                try service.buyShopItem(itemID: itemID, count: count, masterData: masterData)
                rosterStore.refreshFromPersistence()
                equipmentStore.applyInventoryChanges([itemID: count], masterData: masterData)
                applyInventoryChanges([itemID: -count], masterData: masterData)
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
                try loadIfNeeded(masterData: masterData)
                try equipmentStore.loadIfNeeded(masterData: masterData)
                try service.sellInventoryItem(itemID: itemID, count: count, masterData: masterData)
                rosterStore.refreshFromPersistence()
                equipmentStore.applyInventoryChanges([itemID: -count], masterData: masterData)
                applyInventoryChanges([itemID: count], masterData: masterData)
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func organize(
        itemID: CompositeItemID,
        masterData: MasterData,
        rosterStore: GuildRosterStore
    ) {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                try loadIfNeeded(masterData: masterData)
                try service.organizeShopInventoryItem(
                    itemID: itemID,
                    masterData: masterData
                )
                rosterStore.refreshFromPersistence()
                applyInventoryChanges(
                    [itemID: -ShopCatalog.stockOrganizationBundleSize],
                    masterData: masterData
                )
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func configureAutoSell(
        itemIDs: Set<CompositeItemID>,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore
    ) {
        guard !isMutating, !itemIDs.isEmpty else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                try loadIfNeeded(masterData: masterData)
                try equipmentStore.loadIfNeeded(masterData: masterData)
                let movedCounts = Dictionary(
                    uniqueKeysWithValues: itemIDs.map { ($0, equipmentStore.inventoryQuantity(for: $0)) }
                )
                _ = try service.configureAutoSell(
                    itemIDs: itemIDs,
                    masterData: masterData
                )
                rosterStore.refreshFromPersistence()
                equipmentStore.applyInventoryChanges(
                    Dictionary(uniqueKeysWithValues: movedCounts.map { ($0.key, -$0.value) }),
                    masterData: masterData
                )
                applyInventoryChanges(movedCounts, masterData: masterData)
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

    private func incrementInventory(
        itemID: CompositeItemID,
        by amount: Int
    ) {
        guard amount > 0 else {
            return
        }

        let sectionKey = sectionKeyByItemID[itemID] ?? cachedItem(for: itemID, quantity: amount).sectionKey
        var items = shopItemsBySection[sectionKey] ?? []

        if let index = items.firstIndex(where: { $0.itemID == itemID }) {
            items[index].quantity += amount
        } else {
            insert(cachedItem(for: itemID, quantity: amount), into: &items)
            sectionKeyByItemID[itemID] = sectionKey
            if orderedSectionKeys.contains(sectionKey) == false {
                orderedSectionKeys.append(sectionKey)
                orderedSectionKeys.sort(by: EquipmentSectionKey.isOrderedBefore)
            }
        }

        shopItemsBySection[sectionKey] = items
    }

    private func decrementInventory(
        itemID: CompositeItemID,
        by amount: Int
    ) {
        guard let sectionKey = sectionKeyByItemID[itemID],
              var items = shopItemsBySection[sectionKey],
              let index = items.firstIndex(where: { $0.itemID == itemID }) else {
            return
        }

        let newQuantity = items[index].quantity - amount
        if newQuantity > 0 {
            items[index].quantity = newQuantity
            shopItemsBySection[sectionKey] = items
            return
        }

        items.remove(at: index)
        sectionKeyByItemID.removeValue(forKey: itemID)

        if items.isEmpty {
            shopItemsBySection.removeValue(forKey: sectionKey)
            orderedSectionKeys.removeAll { $0 == sectionKey }
        } else {
            shopItemsBySection[sectionKey] = items
        }
    }

    private func insert(
        _ item: EquipmentCachedItem,
        into items: inout [EquipmentCachedItem]
    ) {
        if let index = items.firstIndex(where: { EquipmentCachedItem.isOrderedBefore(item, $0) }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
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
