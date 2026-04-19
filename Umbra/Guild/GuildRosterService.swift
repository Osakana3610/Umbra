// Owns roster mutations and player-state flags that belong to guild-facing character management.

import Foundation

@MainActor
final class GuildRosterService {
    private let coreDataRepository: GuildCoreDataRepository
    private let explorationCoreDataRepository: ExplorationCoreDataRepository

    init(
        coreDataRepository: GuildCoreDataRepository,
        explorationCoreDataRepository: ExplorationCoreDataRepository
    ) {
        self.coreDataRepository = coreDataRepository
        self.explorationCoreDataRepository = explorationCoreDataRepository
    }

    func hireCharacter(
        raceId: Int,
        jobId: Int,
        aptitudeId: Int,
        masterData: MasterData
    ) throws -> HireCharacterResult {
        guard let hireCost = GuildHiring.price(
            raceId: raceId,
            jobId: jobId,
            masterData: masterData
        ) else {
            throw GuildServiceError.invalidHireSelection
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        guard roster.playerState.gold >= hireCost else {
            throw GuildServiceError.insufficientGold(
                required: hireCost,
                available: roster.playerState.gold
            )
        }

        let character = try GuildHiring.makeCharacterRecord(
            nextCharacterId: roster.playerState.nextCharacterId,
            raceId: raceId,
            jobId: jobId,
            aptitudeId: aptitudeId,
            masterData: masterData
        )
        roster.playerState.gold -= hireCost
        roster.playerState.nextCharacterId += 1
        roster.characters.append(character)
        try coreDataRepository.saveRosterSnapshot(roster)

        return HireCharacterResult(
            playerState: roster.playerState,
            character: character,
            hireCost: hireCost
        )
    }

    func reviveCharacter(
        characterId: Int,
        masterData: MasterData
    ) throws -> GuildRosterSnapshot {
        var roster = try coreDataRepository.loadRosterSnapshot()
        let index = try characterIndex(for: characterId, in: roster.characters)
        guard roster.characters[index].currentHP == 0 else {
            throw GuildServiceError.characterNotDefeated(characterId: characterId)
        }

        try restoreCurrentHPToMax(of: &roster.characters[index], masterData: masterData)
        try coreDataRepository.saveRosterSnapshot(roster)
        return roster
    }

    func reviveAllDefeated(masterData: MasterData) throws -> GuildRosterSnapshot {
        var roster = try coreDataRepository.loadRosterSnapshot()
        for index in roster.characters.indices where roster.characters[index].currentHP == 0 {
            try restoreCurrentHPToMax(of: &roster.characters[index], masterData: masterData)
        }
        try coreDataRepository.saveRosterSnapshot(roster)
        return roster
    }

    func renameCharacter(
        characterId: Int,
        name: String
    ) throws -> CharacterRecord {
        let normalizedName = Self.normalizedCharacterName(name)
        guard !normalizedName.isEmpty else {
            throw GuildServiceError.invalidCharacterName
        }

        guard var character = try coreDataRepository.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        character.name = normalizedName
        try coreDataRepository.saveCharacter(character)
        return character
    }

    func deleteCharacter(
        characterId: Int
    ) async throws {
        // Guild mutations are blocked while a character participates in an active run so stored
        // exploration snapshots never point at deleted roster members.
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)

        var roster = try coreDataRepository.loadRosterSnapshot()
        let characterIndex = try characterIndex(for: characterId, in: roster.characters)
        let character = roster.characters.remove(at: characterIndex)

        var parties = try coreDataRepository.loadParties()
        for index in parties.indices {
            parties[index].memberCharacterIds.removeAll { $0 == characterId }
        }

        // Any equipped gear returns to shared inventory before the character row disappears.
        let inventoryStacks = (try coreDataRepository.loadInventoryStacks() + character.equippedItemStacks)
            .normalizedCompositeItemStacks()

        try coreDataRepository.saveRosterState(
            roster,
            parties: parties,
            inventoryStacks: inventoryStacks
        )
    }

    func updateAutoBattleSettings(
        characterId: Int,
        autoBattleSettings: CharacterAutoBattleSettings
    ) async throws -> CharacterRecord {
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        guard var character = try coreDataRepository.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        character.autoBattleSettings = autoBattleSettings
        try coreDataRepository.saveCharacter(character)
        return character
    }

    func changeJob(
        characterId: Int,
        to targetJobId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)

        guard var character = try coreDataRepository.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }
        guard character.previousJobId == 0 else {
            throw GuildServiceError.characterAlreadyChangedJob(characterId: characterId)
        }
        guard character.currentJobId != targetJobId,
              let targetJob = masterData.jobs.first(where: { $0.id == targetJobId }) else {
            throw GuildServiceError.invalidJobChangeTarget(jobId: targetJobId)
        }
        guard targetJob.canChange(fromCurrentJobId: character.currentJobId, level: character.level) else {
            throw GuildServiceError.jobChangeRequirementNotMet(jobId: targetJobId)
        }

        character.previousJobId = character.currentJobId
        character.currentJobId = targetJobId
        character.portraitAssetID = targetJob.portraitAssetName(for: character.portraitGender)

        // A job change can invalidate max HP and equipment limits, so both are normalized before
        // the updated character is persisted back to the roster.
        let unequippedStacks = trimEquippedItemsToMaximum(on: &character, masterData: masterData)
        GuildMutationResolver.clampCurrentHP(of: &character, masterData: masterData)
        try coreDataRepository.saveCharacter(character)

        if !unequippedStacks.isEmpty {
            let updatedInventoryStacks = (try coreDataRepository.loadInventoryStacks() + unequippedStacks)
                .normalizedCompositeItemStacks()
            try coreDataRepository.saveInventoryStacks(updatedInventoryStacks)
        }

        return character
    }

    func setAutoReviveDefeatedCharactersEnabled(_ isEnabled: Bool) throws -> GuildRosterSnapshot {
        var roster = try coreDataRepository.loadRosterSnapshot()
        roster.playerState.autoReviveDefeatedCharacters = isEnabled
        try coreDataRepository.saveRosterSnapshot(roster)
        return roster
    }

    func setAutoSellEnabled(
        itemID: CompositeItemID,
        isEnabled: Bool,
        masterData: MasterData
    ) throws -> PlayerState {
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        if isEnabled {
            roster.playerState.autoSellItemIDs.insert(itemID)
        } else {
            roster.playerState.autoSellItemIDs.remove(itemID)
        }
        try coreDataRepository.saveRosterSnapshot(roster)
        return roster.playerState
    }

    private static func normalizedCharacterName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreCurrentHPToMax(
        of character: inout CharacterRecord,
        masterData: MasterData
    ) throws {
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            throw GuildServiceError.invalidCharacterState(characterId: character.characterId)
        }

        character.currentHP = status.maxHP
    }

    private func trimEquippedItemsToMaximum(
        on character: inout CharacterRecord,
        masterData: MasterData
    ) -> [CompositeItemStack] {
        character.equippedItemStacks = character.orderedEquippedItemStacks

        var removedStacks: [CompositeItemStack] = []
        var overflowCount = character.equippedItemCount - character.maximumEquippedItemCount(masterData: masterData)

        while overflowCount > 0,
              let lastIndex = character.equippedItemStacks.indices.last {
            let stack = character.equippedItemStacks[lastIndex]
            let removedCount = min(stack.count, overflowCount)

            removedStacks.append(
                CompositeItemStack(
                    itemID: stack.itemID,
                    count: removedCount
                )
            )

            if stack.count == removedCount {
                character.equippedItemStacks.remove(at: lastIndex)
            } else {
                character.equippedItemStacks[lastIndex] = CompositeItemStack(
                    itemID: stack.itemID,
                    count: stack.count - removedCount
                )
            }

            overflowCount -= removedCount
        }

        return removedStacks.normalizedCompositeItemStacks()
    }

    private func characterIndex(
        for characterId: Int,
        in characters: [CharacterRecord]
    ) throws -> Int {
        guard let index = characters.firstIndex(where: { $0.characterId == characterId }) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }
        return index
    }
}

extension CharacterRecord {
    var hasChangedJob: Bool {
        previousJobId != 0
    }
}

extension MasterData.Job {
    func canChange(
        fromCurrentJobId currentJobId: Int,
        level: Int
    ) -> Bool {
        let requiredCurrentJobId = jobChangeRequirement?.requiredCurrentJobId ?? 0
        let requiredLevel = jobChangeRequirement?.requiredLevel ?? 0
        let currentJobMatches = requiredCurrentJobId == 0 || requiredCurrentJobId == currentJobId
        return currentJobMatches && level >= requiredLevel
    }

    func jobChangeRequirementSummary(masterData: MasterData) -> String? {
        let requiredCurrentJobId = jobChangeRequirement?.requiredCurrentJobId ?? 0
        let requiredLevel = jobChangeRequirement?.requiredLevel ?? 0
        var parts: [String] = []

        if requiredCurrentJobId != 0 {
            parts.append("現職: \(masterData.jobName(for: requiredCurrentJobId))")
        }
        if requiredLevel > 0 {
            parts.append("Lv.\(requiredLevel)以上")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}
