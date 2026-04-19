// Resolves shared roster and inventory mutations used by guild-domain services.

import Foundation

nonisolated enum GuildMutationResolver {
    static func consumeJewelEnhancementInput(
        itemID: CompositeItemID,
        characterId: Int?,
        inventoryStacks: inout [CompositeItemStack],
        roster: inout GuildRosterSnapshot
    ) throws {
        // Jewel enhancement can consume either a shared-inventory stack or one equipped copy on a
        // specific character, so both storage locations are normalized through the same helper.
        if let characterId {
            guard let characterIndex = roster.characters.firstIndex(where: { $0.characterId == characterId }) else {
                throw GuildServiceError.characterNotFound(characterId: characterId)
            }
            guard roster.characters[characterIndex].equippedItemStacks.contains(where: { $0.itemID == itemID }) else {
                throw GuildServiceError.equippedItemNotFound
            }

            decrementStack(itemID: itemID, in: &roster.characters[characterIndex].equippedItemStacks)
            roster.characters[characterIndex].equippedItemStacks = roster.characters[characterIndex]
                .equippedItemStacks
                .normalizedCompositeItemStacks()
            return
        }

        guard inventoryStacks.contains(where: { $0.itemID == itemID }) else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        decrementStack(itemID: itemID, in: &inventoryStacks)
    }

    static func decrementStack(
        itemID: CompositeItemID,
        count: Int = 1,
        in stacks: inout [CompositeItemStack]
    ) {
        guard let index = stacks.firstIndex(where: { $0.itemID == itemID }) else {
            return
        }

        let currentCount = stacks[index].count
        if currentCount <= count {
            stacks.remove(at: index)
            return
        }

        stacks[index] = CompositeItemStack(itemID: itemID, count: currentCount - count)
    }

    static func incrementStack(
        itemID: CompositeItemID,
        count: Int = 1,
        in stacks: inout [CompositeItemStack]
    ) {
        if let index = stacks.firstIndex(where: { $0.itemID == itemID }) {
            stacks[index] = CompositeItemStack(
                itemID: itemID,
                count: stacks[index].count + count
            )
            return
        }

        stacks.append(CompositeItemStack(itemID: itemID, count: count))
        stacks.sort { $0.itemID.isOrdered(before: $1.itemID) }
    }

    static func clampCurrentHP(
        of character: inout CharacterRecord,
        masterData: MasterData
    ) {
        // Equipment changes and job changes both need the same derived max-HP clamp after stats
        // are recalculated, so the shared helper keeps the rule in one place.
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            return
        }

        character.currentHP = min(max(character.currentHP, 0), status.maxHP)
    }
}
