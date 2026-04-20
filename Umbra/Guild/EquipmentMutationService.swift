// Executes equipment mutations that move item stacks between characters and shared inventory.
// The service keeps mutation rules close to persistence updates so equip limits, HP clamping, and
// exploration safety checks are enforced consistently for every entry point.

import Foundation

@MainActor
final class EquipmentMutationService {
    private let coreDataRepository: GuildCoreDataRepository
    private let explorationCoreDataRepository: ExplorationCoreDataRepository

    init(
        coreDataRepository: GuildCoreDataRepository,
        explorationCoreDataRepository: ExplorationCoreDataRepository
    ) {
        self.coreDataRepository = coreDataRepository
        self.explorationCoreDataRepository = explorationCoreDataRepository
    }

    func enhanceWithJewel(
        baseItemID: CompositeItemID,
        baseCharacterId: Int?,
        jewelItemID: CompositeItemID,
        jewelCharacterId: Int?,
        masterData: MasterData
    ) async throws {
        guard baseItemID.isValid(in: masterData),
              jewelItemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }
        guard baseItemID.jewelItemId == 0,
              jewelItemID.jewelItemId == 0,
              let jewelItem = masterData.items.first(where: { $0.id == jewelItemID.baseItemId }),
              jewelItem.category == .jewel else {
            throw GuildServiceError.invalidJewelEnhancement
        }

        // Exploration runs hold snapshots of participating characters, so any equipment mutation on
        // an active participant must be rejected before inventory state is touched.
        for characterId in Set([baseCharacterId, jewelCharacterId].compactMap(\.self)) {
            try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        try GuildMutationResolver.consumeJewelEnhancementInput(
            itemID: baseItemID,
            characterId: baseCharacterId,
            inventoryStacks: &inventoryStacks,
            roster: &roster
        )
        try GuildMutationResolver.consumeJewelEnhancementInput(
            itemID: jewelItemID,
            characterId: jewelCharacterId,
            inventoryStacks: &inventoryStacks,
            roster: &roster
        )

        let resultItemID = CompositeItemID(
            baseSuperRareId: baseItemID.baseSuperRareId,
            baseTitleId: baseItemID.baseTitleId,
            baseItemId: baseItemID.baseItemId,
            jewelSuperRareId: jewelItemID.baseSuperRareId,
            jewelTitleId: jewelItemID.baseTitleId,
            jewelItemId: jewelItemID.baseItemId
        )

        if let baseCharacterId {
            // When the base item started equipped, the enhanced result returns directly to that same
            // character instead of bouncing through shared inventory.
            try addJewelEnhancementResult(
                itemID: resultItemID,
                toCharacterId: baseCharacterId,
                roster: &roster
            )
        } else {
            GuildMutationResolver.incrementStack(itemID: resultItemID, in: &inventoryStacks)
        }

        try coreDataRepository.saveRosterState(
            roster,
            parties: try coreDataRepository.loadParties(),
            inventoryStacks: inventoryStacks
        )
    }

    func extractJewel(
        itemID: CompositeItemID,
        characterId: Int?,
        masterData: MasterData
    ) async throws {
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }
        guard itemID.jewelItemId > 0,
              itemID.baseItemId > 0,
              let jewelItem = masterData.items.first(where: { $0.id == itemID.jewelItemId }),
              jewelItem.category == .jewel else {
            throw GuildServiceError.invalidJewelExtraction
        }

        if let characterId {
            try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        try GuildMutationResolver.consumeJewelEnhancementInput(
            itemID: itemID,
            characterId: characterId,
            inventoryStacks: &inventoryStacks,
            roster: &roster
        )

        let baseItemID = CompositeItemID(
            baseSuperRareId: itemID.baseSuperRareId,
            baseTitleId: itemID.baseTitleId,
            baseItemId: itemID.baseItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
        let jewelItemID = CompositeItemID(
            baseSuperRareId: itemID.jewelSuperRareId,
            baseTitleId: itemID.jewelTitleId,
            baseItemId: itemID.jewelItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )

        if let characterId {
            try addJewelEnhancementResult(
                itemID: baseItemID,
                toCharacterId: characterId,
                roster: &roster
            )
        } else {
            GuildMutationResolver.incrementStack(itemID: baseItemID, in: &inventoryStacks)
        }
        GuildMutationResolver.incrementStack(itemID: jewelItemID, in: &inventoryStacks)

        try coreDataRepository.saveRosterState(
            roster,
            parties: try coreDataRepository.loadParties(),
            inventoryStacks: inventoryStacks
        )
    }

    func equip(
        itemID: CompositeItemID,
        toCharacter characterId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        guard var character = try coreDataRepository.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }
        guard let inventoryStack = try coreDataRepository.loadInventoryStack(itemID: itemID) else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        guard inventoryStack.count > 0 else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        let equippedCount = character.equippedItemStacks.reduce(into: 0) { $0 += $1.count }
        let maximumCount = character.maximumEquippedItemCount(masterData: masterData)
        guard equippedCount < maximumCount else {
            throw GuildServiceError.equipLimitReached(maximumCount: maximumCount)
        }

        // Normalize after appending so duplicate identities collapse into one stack before the record
        // is persisted.
        character.equippedItemStacks = (
            character.equippedItemStacks +
                [CompositeItemStack(itemID: itemID, count: 1)]
        )
        .normalizedCompositeItemStacks()
        GuildMutationResolver.clampCurrentHP(of: &character, masterData: masterData)

        let updatedInventoryStack = inventoryStack.count == 1
            ? nil
            : CompositeItemStack(itemID: itemID, count: inventoryStack.count - 1)

        try coreDataRepository.saveCharacter(
            character,
            inventoryItemID: itemID,
            inventoryStack: updatedInventoryStack
        )
        return character
    }

    func unequip(
        itemID: CompositeItemID,
        fromCharacter characterId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        guard var character = try coreDataRepository.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }
        guard let equippedIndex = character.equippedItemStacks.firstIndex(where: { $0.itemID == itemID }) else {
            throw GuildServiceError.equippedItemNotFound
        }

        let equippedStack = character.equippedItemStacks[equippedIndex]
        if equippedStack.count == 1 {
            character.equippedItemStacks.remove(at: equippedIndex)
        } else {
            character.equippedItemStacks[equippedIndex] = CompositeItemStack(
                itemID: itemID,
                count: equippedStack.count - 1
            )
        }

        let inventoryStack = try coreDataRepository.loadInventoryStack(itemID: itemID)
        let updatedInventoryStack = CompositeItemStack(
            itemID: itemID,
            count: (inventoryStack?.count ?? 0) + 1
        )

        GuildMutationResolver.clampCurrentHP(of: &character, masterData: masterData)
        try coreDataRepository.saveCharacter(
            character,
            inventoryItemID: itemID,
            inventoryStack: updatedInventoryStack
        )
        return character
    }

    private func addJewelEnhancementResult(
        itemID: CompositeItemID,
        toCharacterId characterId: Int,
        roster: inout GuildRosterSnapshot
    ) throws {
        guard let characterIndex = roster.characters.firstIndex(where: { $0.characterId == characterId }) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        GuildMutationResolver.incrementStack(itemID: itemID, in: &roster.characters[characterIndex].equippedItemStacks)
        roster.characters[characterIndex].equippedItemStacks = roster.characters[characterIndex]
            .orderedEquippedItemStacks
    }
}
