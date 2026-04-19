// Owns the observable shop stock cache used by the store UI.
// Wraps shop mutations so roster gold, player inventory, and shop inventory stay synchronized
// without forcing every screen to reload from persistence after each operation.

import Foundation
import Observation

@MainActor
@Observable
final class ShopInventoryStore {
    private let service: ShopTradingService

    private var itemsByID: [Int: MasterData.Item] = [:]
    private var nameResolver: EquipmentDisplayNameResolver?
    private var sectionKeyByItemID: [CompositeItemID: EquipmentSectionKey] = [:]

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var shopItemsBySection: [EquipmentSectionKey: [EquipmentCachedItem]] = [:]
    private(set) var orderedSectionKeys: [EquipmentSectionKey] = []

    var displayOrderedShopItems: [EquipmentCachedItem] {
        orderedSectionKeys.flatMap { shopItemsBySection[$0] ?? [] }
    }

    init(service: ShopTradingService) {
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

        // The store updates its in-memory section cache incrementally after successful mutations so
        // the UI reflects the change immediately without a full reload from Core Data.
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
                // Refresh persistent player state first, then mirror the same delta into both cached
                // inventories so every visible screen stays in sync with one mutation.
                rosterStore.refreshFromPersistence()
                equipmentStore.applyInventoryChanges([itemID: count], masterData: masterData)
                applyInventoryChanges([itemID: -count], masterData: masterData)
            } catch {
                lastOperationError = UserFacingErrorMessage.resolve(error)
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
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
                    [itemID: -ShopPricingCalculator.stockOrganizationBundleSize],
                    masterData: masterData
                )
            } catch {
                lastOperationError = UserFacingErrorMessage.resolve(error)
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
                // Auto-sell moves every owned stack for the selected identities into the shop at once,
                // so capture those counts before the service mutates persistence.
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
            }
        }
    }

    private func configure(masterData: MasterData) {
        // These lookup tables are stable for one master-data snapshot, so build them lazily and reuse
        // them across incremental cache updates.
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
        let baseItem = itemsByID[itemID.baseItemId]

        return EquipmentCachedItem(
            itemID: itemID,
            stackKey: itemID.stableKey,
            equippedRowID: itemID.stableKey + "|shop",
            quantity: quantity,
            displayName: nameResolver?.displayName(for: itemID) ?? baseItem?.name ?? "不明なアイテム",
            category: baseItem?.category ?? .misc,
            rarity: baseItem?.rarity ?? .normal
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
            // New identities must be inserted in sorted order because section rows are rendered
            // directly from the cached arrays.
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
            // Prune empty sections immediately so the section index and visible headers do not leave
            // behind empty buckets after a trade.
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

}
