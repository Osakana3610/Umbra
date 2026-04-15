// Caches inventory sections and prepared equipment rows so equip and unequip update the UI immediately.

import Foundation
import Observation

@MainActor
@Observable
final class EquipmentInventoryStore {
    private let coreDataStore: GuildCoreDataStore
    private let service: GuildService
    private let equipmentStatusNotificationService: EquipmentStatusNotificationService

    private var itemsByID: [Int: MasterData.Item] = [:]
    private var nameResolver: EquipmentDisplayNameResolver?
    private var equippedItemsByCharacterID: [Int: [EquipmentCachedItem]] = [:]
    private var sectionKeyByItemID: [CompositeItemID: EquipmentSectionKey] = [:]
    private var mergedSectionsByCharacterID: [Int: [EquipmentSectionRows]] = [:]

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var inventoryItemsBySection: [EquipmentSectionKey: [EquipmentCachedItem]] = [:]
    private(set) var orderedSectionKeys: [EquipmentSectionKey] = []

    init(
        coreDataStore: GuildCoreDataStore,
        service: GuildService,
        equipmentStatusNotificationService: EquipmentStatusNotificationService
    ) {
        self.coreDataStore = coreDataStore
        self.service = service
        self.equipmentStatusNotificationService = equipmentStatusNotificationService
    }

    func loadIfNeeded(masterData: MasterData) throws {
        guard !isLoaded else {
            return
        }

        try reload(masterData: masterData)
    }

    func reload(masterData: MasterData) throws {
        configure(masterData: masterData)

        let inventoryStacks = try coreDataStore.loadInventoryStacks()
        var groupedInventory: [EquipmentSectionKey: [EquipmentCachedItem]] = [:]
        var newSectionKeyByItemID: [CompositeItemID: EquipmentSectionKey] = [:]

        for stack in inventoryStacks.normalizedCompositeItemStacks() {
            let cachedItem = cachedItem(for: stack.itemID, quantity: stack.count)
            groupedInventory[cachedItem.sectionKey, default: []].append(cachedItem)
            newSectionKeyByItemID[cachedItem.itemID] = cachedItem.sectionKey
        }

        for key in groupedInventory.keys {
            groupedInventory[key]?.sort(by: EquipmentCachedItem.isOrderedBefore)
        }

        inventoryItemsBySection = groupedInventory
        sectionKeyByItemID = newSectionKeyByItemID
        orderedSectionKeys = groupedInventory.keys.sorted(by: EquipmentSectionKey.isOrderedBefore)

        for characterID in mergedSectionsByCharacterID.keys {
            mergedSectionsByCharacterID[characterID] = buildMergedSections(for: characterID)
        }

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

        var affectedSectionKeys: Set<EquipmentSectionKey> = []
        for (itemID, count) in itemCounts where count != 0 {
            if let sectionKey = updateInventory(itemID: itemID, quantityDelta: count) {
                affectedSectionKeys.insert(sectionKey)
            }
        }

        for sectionKey in affectedSectionKeys {
            refreshMergedSections(affectedSectionKey: sectionKey)
        }
    }

    func inventoryQuantity(for itemID: CompositeItemID) -> Int {
        guard let sectionKey = sectionKeyByItemID[itemID],
              let item = inventoryItemsBySection[sectionKey]?.first(where: { $0.itemID == itemID }) else {
            return 0
        }

        return item.quantity
    }

    func synchronizeCharacter(
        _ character: CharacterRecord,
        masterData: MasterData
    ) {
        guard isLoaded else {
            return
        }

        configure(masterData: masterData)
        equippedItemsByCharacterID[character.characterId] = cachedItems(from: character.equippedItemStacks)

        guard mergedSectionsByCharacterID[character.characterId] != nil else {
            return
        }

        mergedSectionsByCharacterID[character.characterId] = buildMergedSections(for: character.characterId)
    }

    func removeCharacter(characterId: Int) {
        guard isLoaded else {
            return
        }

        equippedItemsByCharacterID.removeValue(forKey: characterId)
        mergedSectionsByCharacterID.removeValue(forKey: characterId)
    }

    func equippedItems(
        for character: CharacterRecord,
        masterData: MasterData
    ) -> [EquipmentCachedItem] {
        configure(masterData: masterData)

        if let cachedItems = equippedItemsByCharacterID[character.characterId] {
            return cachedItems
        }

        let cachedItems = cachedItems(from: character.equippedItemStacks)
        equippedItemsByCharacterID[character.characterId] = cachedItems
        return cachedItems
    }

    func hasPreparedMergedSections(for characterId: Int) -> Bool {
        mergedSectionsByCharacterID[characterId] != nil
    }

    func prepareMergedSectionsIfNeeded(
        for character: CharacterRecord,
        masterData: MasterData
    ) {
        configure(masterData: masterData)

        guard mergedSectionsByCharacterID[character.characterId] == nil else {
            return
        }

        equippedItemsByCharacterID[character.characterId] = cachedItems(from: character.equippedItemStacks)
        mergedSectionsByCharacterID[character.characterId] = buildMergedSections(for: character.characterId)
    }

    func mergedSections(for characterId: Int) -> [EquipmentSectionRows] {
        mergedSectionsByCharacterID[characterId] ?? []
    }

    func equip(
        itemID: CompositeItemID,
        to character: CharacterRecord,
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
                let beforeStatus = CharacterDerivedStatsCalculator.status(
                    for: character,
                    masterData: masterData
                )
                let updatedCharacter = try await service.equip(
                    itemID: itemID,
                    toCharacter: character.characterId,
                    masterData: masterData
                )
                let afterStatus = CharacterDerivedStatsCalculator.status(
                    for: updatedCharacter,
                    masterData: masterData
                )
                rosterStore.replaceCharacter(updatedCharacter)
                applyEquipmentChange(
                    itemID: itemID,
                    inventoryQuantityDelta: -1,
                    updatedCharacter: updatedCharacter
                )
                equipmentStatusNotificationService.publish(
                    before: beforeStatus,
                    after: afterStatus
                )
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func unequip(
        itemID: CompositeItemID,
        from character: CharacterRecord,
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
                let beforeStatus = CharacterDerivedStatsCalculator.status(
                    for: character,
                    masterData: masterData
                )
                let updatedCharacter = try await service.unequip(
                    itemID: itemID,
                    fromCharacter: character.characterId,
                    masterData: masterData
                )
                let afterStatus = CharacterDerivedStatsCalculator.status(
                    for: updatedCharacter,
                    masterData: masterData
                )
                rosterStore.replaceCharacter(updatedCharacter)
                applyEquipmentChange(
                    itemID: itemID,
                    inventoryQuantityDelta: 1,
                    updatedCharacter: updatedCharacter
                )
                equipmentStatusNotificationService.publish(
                    before: beforeStatus,
                    after: afterStatus
                )
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func enhanceWithJewel(
        baseItemID: CompositeItemID,
        baseCharacterId: Int?,
        jewelItemID: CompositeItemID,
        jewelCharacterId: Int?,
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
                try await service.enhanceWithJewel(
                    baseItemID: baseItemID,
                    baseCharacterId: baseCharacterId,
                    jewelItemID: jewelItemID,
                    jewelCharacterId: jewelCharacterId,
                    masterData: masterData
                )
                rosterStore.refreshFromPersistence()
                applyInventoryChanges(
                    [
                        baseItemID: baseCharacterId == nil ? -1 : 0,
                        jewelItemID: jewelCharacterId == nil ? -1 : 0,
                        CompositeItemID(
                            baseSuperRareId: baseItemID.baseSuperRareId,
                            baseTitleId: baseItemID.baseTitleId,
                            baseItemId: baseItemID.baseItemId,
                            jewelSuperRareId: jewelItemID.baseSuperRareId,
                            jewelTitleId: jewelItemID.baseTitleId,
                            jewelItemId: jewelItemID.baseItemId
                        ): baseCharacterId == nil ? 1 : 0
                    ],
                    masterData: masterData
                )
                for characterId in Set([baseCharacterId, jewelCharacterId].compactMap(\.self)) {
                    guard let updatedCharacter = rosterStore.charactersById[characterId] else {
                        continue
                    }
                    synchronizeCharacter(updatedCharacter, masterData: masterData)
                }
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

    private func applyEquipmentChange(
        itemID: CompositeItemID,
        inventoryQuantityDelta: Int,
        updatedCharacter: CharacterRecord
    ) {
        // Only the touched inventory section and the updated character cache are refreshed so the
        // equipment UI stays responsive without rebuilding every section for every character.
        let affectedSectionKey = updateInventory(itemID: itemID, quantityDelta: inventoryQuantityDelta)
        equippedItemsByCharacterID[updatedCharacter.characterId] = cachedItems(from: updatedCharacter.equippedItemStacks)
        refreshMergedSections(affectedSectionKey: affectedSectionKey)
    }

    private func updateInventory(
        itemID: CompositeItemID,
        quantityDelta: Int
    ) -> EquipmentSectionKey? {
        if quantityDelta > 0 {
            return incrementInventory(itemID: itemID, by: quantityDelta)
        }
        if quantityDelta < 0 {
            return decrementInventory(itemID: itemID, by: -quantityDelta)
        }
        return nil
    }

    private func decrementInventory(
        itemID: CompositeItemID,
        by amount: Int
    ) -> EquipmentSectionKey? {
        guard let sectionKey = sectionKeyByItemID[itemID],
              var items = inventoryItemsBySection[sectionKey],
              let index = items.firstIndex(where: { $0.itemID == itemID }) else {
            return nil
        }

        let newQuantity = items[index].quantity - amount
        if newQuantity > 0 {
            items[index].quantity = newQuantity
            inventoryItemsBySection[sectionKey] = items
            return sectionKey
        }

        items.remove(at: index)
        sectionKeyByItemID.removeValue(forKey: itemID)

        // Drop the whole section when its last inventory row disappears so empty headers are not
        // kept alive in the prepared merged-section cache.
        if items.isEmpty {
            inventoryItemsBySection.removeValue(forKey: sectionKey)
            orderedSectionKeys.removeAll { $0 == sectionKey }
        } else {
            inventoryItemsBySection[sectionKey] = items
        }

        return sectionKey
    }

    private func incrementInventory(
        itemID: CompositeItemID,
        by amount: Int
    ) -> EquipmentSectionKey? {
        guard amount > 0 else {
            return nil
        }

        let sectionKey = sectionKeyByItemID[itemID] ?? cachedItem(for: itemID, quantity: amount).sectionKey
        var items = inventoryItemsBySection[sectionKey] ?? []

        if let index = items.firstIndex(where: { $0.itemID == itemID }) {
            items[index].quantity += amount
        } else {
            insert(cachedItem(for: itemID, quantity: amount), into: &items)
            sectionKeyByItemID[itemID] = sectionKey
            // Newly materialized sections are inserted into the global section order once so all
            // prepared character views reuse the same category and rarity ordering.
            if orderedSectionKeys.contains(sectionKey) == false {
                orderedSectionKeys.append(sectionKey)
                orderedSectionKeys.sort(by: EquipmentSectionKey.isOrderedBefore)
            }
        }

        inventoryItemsBySection[sectionKey] = items
        return sectionKey
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

    private func cachedItem(
        for itemID: CompositeItemID,
        quantity: Int
    ) -> EquipmentCachedItem {
        let baseItem = itemsByID[itemID.baseItemId]!

        return EquipmentCachedItem(
            itemID: itemID,
            stackKey: itemID.stableKey,
            equippedRowID: itemID.stableKey + "|equipped",
            quantity: quantity,
            displayName: nameResolver?.displayName(for: itemID) ?? baseItem.name,
            category: baseItem.category,
            rarity: baseItem.rarity
        )
    }

    private func cachedItems(
        from itemStacks: [CompositeItemStack]
    ) -> [EquipmentCachedItem] {
        itemStacks
            .normalizedCompositeItemStacks()
            .map { cachedItem(for: $0.itemID, quantity: $0.count) }
            .sorted(by: EquipmentCachedItem.isOrderedBefore)
    }

    private func buildMergedSections(for characterID: Int) -> [EquipmentSectionRows] {
        let equippedItems = equippedItemsByCharacterID[characterID] ?? []
        let equippedItemsBySection = Dictionary(grouping: equippedItems, by: \.sectionKey)

        return mergedSectionKeys(for: equippedItemsBySection.keys).compactMap { sectionKey in
            let rows = buildMergedRows(
                sectionKey: sectionKey,
                equippedItems: equippedItemsBySection[sectionKey] ?? []
            )
            return rows.isEmpty ? nil : EquipmentSectionRows(key: sectionKey, rows: rows)
        }
    }

    private func refreshMergedSections(affectedSectionKey: EquipmentSectionKey?) {
        guard let affectedSectionKey else {
            return
        }

        // Only the changed section is recomputed across prepared characters; untouched sections
        // keep their cached row arrays.
        for characterID in mergedSectionsByCharacterID.keys {
            refreshMergedSection(for: characterID, sectionKey: affectedSectionKey)
        }
    }

    private func refreshMergedSection(
        for characterID: Int,
        sectionKey: EquipmentSectionKey
    ) {
        guard var sections = mergedSectionsByCharacterID[characterID] else {
            return
        }

        let equippedItemsBySection = Dictionary(
            grouping: equippedItemsByCharacterID[characterID] ?? [],
            by: \.sectionKey
        )
        let rows = buildMergedRows(
            sectionKey: sectionKey,
            equippedItems: equippedItemsBySection[sectionKey] ?? []
        )

        if let index = sections.firstIndex(where: { $0.key == sectionKey }) {
            if rows.isEmpty {
                sections.remove(at: index)
            } else {
                sections[index].rows = rows
            }
            mergedSectionsByCharacterID[characterID] = sections
            return
        }

        guard !rows.isEmpty else {
            return
        }

        let section = EquipmentSectionRows(key: sectionKey, rows: rows)
        if let index = sections.firstIndex(where: { EquipmentSectionKey.isOrderedBefore(sectionKey, $0.key) }) {
            sections.insert(section, at: index)
        } else {
            sections.append(section)
        }
        mergedSectionsByCharacterID[characterID] = sections
    }

    private func mergedSectionKeys<S: Sequence>(
        for equippedSectionKeys: S
    ) -> [EquipmentSectionKey] where S.Element == EquipmentSectionKey {
        let equippedKeys = Set(equippedSectionKeys)
        guard !equippedKeys.isEmpty else {
            return orderedSectionKeys
        }

        return Set(orderedSectionKeys).union(equippedKeys).sorted(by: EquipmentSectionKey.isOrderedBefore)
    }

    private func buildMergedRows(
        sectionKey: EquipmentSectionKey,
        equippedItems: [EquipmentCachedItem]
    ) -> [EquipmentDisplayRow] {
        let equippedItemsByID = Dictionary(uniqueKeysWithValues: equippedItems.map { ($0.itemID, $0) })
        var matchedItemIDs = Set<CompositeItemID>()
        var rows: [EquipmentDisplayRow] = []
        rows.reserveCapacity((inventoryItemsBySection[sectionKey]?.count ?? 0) + equippedItems.count)

        // Inventory rows are emitted first, then the equipped twin for the same item directly
        // after it, so the player can compare stock count and equipped usage in one place.
        for inventoryItem in inventoryItemsBySection[sectionKey] ?? [] {
            rows.append(.inventory(inventoryItem))
            if let equippedItem = equippedItemsByID[inventoryItem.itemID] {
                rows.append(.equipped(equippedItem))
                matchedItemIDs.insert(inventoryItem.itemID)
            }
        }

        for equippedItem in equippedItems where !matchedItemIDs.contains(equippedItem.itemID) {
            let row = EquipmentDisplayRow.equipped(equippedItem)
            if let index = rows.firstIndex(where: { isOrderedBefore(row, than: $0) }) {
                rows.insert(row, at: index)
            } else {
                rows.append(row)
            }
        }

        return rows
    }

    private func isOrderedBefore(
        _ lhs: EquipmentDisplayRow,
        than rhs: EquipmentDisplayRow
    ) -> Bool {
        let leftItem = lhs.cachedItem
        let rightItem = rhs.cachedItem

        if EquipmentCachedItem.isOrderedBefore(leftItem, rightItem) {
            return true
        }
        if EquipmentCachedItem.isOrderedBefore(rightItem, leftItem) {
            return false
        }

        return switch (lhs, rhs) {
        case (.inventory, .equipped):
            // For identical item identities, keep the owned-stack row before the equipped row.
            true
        case (.equipped, .inventory):
            false
        default:
            false
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

struct EquipmentSectionRows: Identifiable, Equatable {
    let key: EquipmentSectionKey
    var rows: [EquipmentDisplayRow]

    var id: EquipmentSectionKey {
        key
    }
}

struct EquipmentSectionKey: Hashable, Identifiable, Sendable {
    let category: ItemCategory
    let rarity: ItemRarity

    var id: String {
        "\(category.rawValue)|\(rarity.rawValue)"
    }

    var title: String {
        "\(category.displayName) / R\(rarity.sortOrder)"
    }

    static func isOrderedBefore(
        _ lhs: EquipmentSectionKey,
        _ rhs: EquipmentSectionKey
    ) -> Bool {
        if lhs.category.sortOrder != rhs.category.sortOrder {
            return lhs.category.sortOrder < rhs.category.sortOrder
        }
        return lhs.rarity.sortOrder < rhs.rarity.sortOrder
    }
}

struct EquipmentCachedItem: Identifiable, Equatable, Sendable {
    let itemID: CompositeItemID
    let stackKey: String
    let equippedRowID: String
    var quantity: Int
    let displayName: String
    let category: ItemCategory
    let rarity: ItemRarity

    var id: String {
        stackKey
    }

    var sectionKey: EquipmentSectionKey {
        EquipmentSectionKey(category: category, rarity: rarity)
    }

    var isSuperRare: Bool {
        itemID.baseSuperRareId > 0
    }

    static func isOrderedBefore(
        _ lhs: EquipmentCachedItem,
        _ rhs: EquipmentCachedItem
    ) -> Bool {
        lhs.itemID.isOrdered(before: rhs.itemID)
    }
}

enum EquipmentDisplayRow: Identifiable, Equatable {
    case inventory(EquipmentCachedItem)
    case equipped(EquipmentCachedItem)

    var id: String {
        switch self {
        case .inventory(let item):
            item.stackKey
        case .equipped(let item):
            item.equippedRowID
        }
    }

    var displayName: String {
        switch self {
        case .inventory(let item), .equipped(let item):
            item.displayName
        }
    }

    var cachedItem: EquipmentCachedItem {
        switch self {
        case .inventory(let item), .equipped(let item):
            item
        }
    }
}
