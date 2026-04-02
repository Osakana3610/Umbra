// Coordinates guild hiring, party management, equipment changes, and exploration-lock checks over value snapshots.

import Foundation

struct HireCharacterResult: Sendable {
    let playerState: PlayerState
    let character: CharacterRecord
    let hireCost: Int
}

enum GuildServiceError: LocalizedError {
    case invalidHireSelection
    case insufficientGold(required: Int, available: Int)
    case maxPartyCountReached
    case invalidParty(partyId: Int)
    case invalidJobChangeTarget(jobId: Int)
    case invalidPartyName
    case partyFull(partyId: Int)
    case characterNotFound(characterId: Int)
    case characterAlreadyChangedJob(characterId: Int)
    case jobChangeRequirementNotMet(jobId: Int)
    case invalidPartyMemberOrder
    case invalidItemStack
    case invalidStackCount
    case inventoryItemUnavailable
    case equipLimitReached(maximumCount: Int)
    case equippedItemNotFound
    case invalidCharacterName
    case characterNotDefeated(characterId: Int)
    case invalidCharacterState(characterId: Int)

    var errorDescription: String? {
        switch self {
        case .invalidHireSelection:
            "雇用条件が不正です。"
        case .insufficientGold(let required, let available):
            "所持金が不足しています。必要=\(required) 現在=\(available)"
        case .maxPartyCountReached:
            "これ以上パーティを解放できません。"
        case .invalidParty(let partyId):
            "パーティが見つかりません。 partyId=\(partyId)"
        case .invalidJobChangeTarget(let jobId):
            "転職先の職業が不正です。 jobId=\(jobId)"
        case .invalidPartyName:
            "パーティ名を入力してください。"
        case .partyFull(let partyId):
            "パーティ\(partyId)はすでに6人です。"
        case .characterNotFound(let characterId):
            "キャラクターが見つかりません。 characterId=\(characterId)"
        case .characterAlreadyChangedJob(let characterId):
            "キャラクター\(characterId)はすでに転職済みです。"
        case .jobChangeRequirementNotMet(let jobId):
            "転職条件を満たしていません。 jobId=\(jobId)"
        case .invalidPartyMemberOrder:
            "パーティ編成の並び順が不正です。"
        case .invalidItemStack:
            "アイテム定義が不正です。"
        case .invalidStackCount:
            "スタック数は1以上で指定してください。"
        case .inventoryItemUnavailable:
            "対象アイテムを所持していません。"
        case .equipLimitReached(let maximumCount):
            "これ以上装備できません。装備上限は\(maximumCount)件です。"
        case .equippedItemNotFound:
            "装備中のアイテムが見つかりません。"
        case .invalidCharacterName:
            "名前を入力してください。"
        case .characterNotDefeated(let characterId):
            "キャラクターは戦闘不能ではありません。 characterId=\(characterId)"
        case .invalidCharacterState(let characterId):
            "キャラクター状態が不正です。 characterId=\(characterId)"
        }
    }
}

@MainActor
final class GuildService {
    private let coreDataStore: GuildCoreDataStore
    private let explorationCoreDataStore: ExplorationCoreDataStore

    init(
        coreDataStore: GuildCoreDataStore,
        explorationCoreDataStore: ExplorationCoreDataStore
    ) {
        self.coreDataStore = coreDataStore
        self.explorationCoreDataStore = explorationCoreDataStore
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

        var roster = try coreDataStore.loadRosterSnapshot()
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
        try coreDataStore.saveRosterSnapshot(roster)

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
        var roster = try coreDataStore.loadRosterSnapshot()
        let index = try characterIndex(for: characterId, in: roster.characters)
        guard roster.characters[index].currentHP == 0 else {
            throw GuildServiceError.characterNotDefeated(characterId: characterId)
        }

        try restoreCurrentHPToMax(of: &roster.characters[index], masterData: masterData)
        try coreDataStore.saveRosterSnapshot(roster)
        return roster
    }

    func reviveAllDefeated(masterData: MasterData) throws -> GuildRosterSnapshot {
        var roster = try coreDataStore.loadRosterSnapshot()
        for index in roster.characters.indices where roster.characters[index].currentHP == 0 {
            try restoreCurrentHPToMax(of: &roster.characters[index], masterData: masterData)
        }
        try coreDataStore.saveRosterSnapshot(roster)
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

        guard var character = try coreDataStore.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        character.name = normalizedName
        try coreDataStore.saveCharacter(character)
        return character
    }

    func deleteCharacter(
        characterId: Int
    ) async throws {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)

        var roster = try coreDataStore.loadRosterSnapshot()
        let characterIndex = try characterIndex(for: characterId, in: roster.characters)
        let character = roster.characters.remove(at: characterIndex)

        var parties = try coreDataStore.loadParties()
        for index in parties.indices {
            parties[index].memberCharacterIds.removeAll { $0 == characterId }
        }

        let inventoryStacks = (try coreDataStore.loadInventoryStacks() + character.equippedItemStacks)
            .normalizedCompositeItemStacks()

        try coreDataStore.saveRosterState(
            roster,
            parties: parties,
            inventoryStacks: inventoryStacks
        )
    }

    func updateAutoBattleSettings(
        characterId: Int,
        autoBattleSettings: CharacterAutoBattleSettings
    ) async throws -> CharacterRecord {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        guard var character = try coreDataStore.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        character.autoBattleSettings = autoBattleSettings
        try coreDataStore.saveCharacter(character)
        return character
    }

    func changeJob(
        characterId: Int,
        to targetJobId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)

        guard var character = try coreDataStore.loadCharacter(characterId: characterId) else {
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

        let unequippedStacks = trimEquippedItemsToMaximum(on: &character)
        clampCurrentHP(of: &character, masterData: masterData)
        try coreDataStore.saveCharacter(character)

        if !unequippedStacks.isEmpty {
            let updatedInventoryStacks = (try coreDataStore.loadInventoryStacks() + unequippedStacks)
                .normalizedCompositeItemStacks()
            try coreDataStore.saveInventoryStacks(updatedInventoryStacks)
        }

        return character
    }

    func setAutoReviveDefeatedCharactersEnabled(_ isEnabled: Bool) throws -> GuildRosterSnapshot {
        var roster = try coreDataStore.loadRosterSnapshot()
        roster.playerState.autoReviveDefeatedCharacters = isEnabled
        try coreDataStore.saveRosterSnapshot(roster)
        return roster
    }

    func recordBackgroundedAt(_ date: Date) throws {
        var roster = try coreDataStore.loadRosterSnapshot()
        roster.playerState.lastBackgroundedAt = date
        try coreDataStore.saveRosterSnapshot(roster)
    }

    func queueAutomaticRunsForResume(
        reopenedAt: Date,
        masterData: MasterData
    ) throws {
        var roster = try coreDataStore.loadRosterSnapshot()
        guard let backgroundedAt = roster.playerState.lastBackgroundedAt else {
            return
        }

        var parties = try coreDataStore.loadParties()
        let elapsedSeconds = max(Int(reopenedAt.timeIntervalSince(backgroundedAt)), 0)
        if elapsedSeconds > 0 {
            for index in parties.indices {
                guard let labyrinthId = parties[index].selectedLabyrinthId,
                      let labyrinth = masterData.labyrinths.first(where: { $0.id == labyrinthId }) else {
                    continue
                }

                let totalBattleCount = labyrinth.floors.reduce(into: 0) { partialResult, floor in
                    partialResult += floor.battleCount
                }
                let runDurationSeconds = totalBattleCount * max(labyrinth.progressIntervalSeconds, 1)
                guard runDurationSeconds > 0 else {
                    continue
                }

                let additionalRunCount = elapsedSeconds / runDurationSeconds
                guard additionalRunCount > 0 else {
                    continue
                }

                if parties[index].pendingAutomaticRunCount == 0 {
                    parties[index].pendingAutomaticRunStartedAt = backgroundedAt
                }
                parties[index].pendingAutomaticRunCount = min(
                    parties[index].pendingAutomaticRunCount + additionalRunCount,
                    PartyRecord.maxPendingAutomaticRunCount
                )
            }
        }

        roster.playerState.lastBackgroundedAt = nil
        try coreDataStore.saveRosterSnapshot(roster)
        try coreDataStore.saveParties(parties)
    }

    func consumePendingAutomaticRun(partyId: Int) throws {
        var parties = try coreDataStore.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].pendingAutomaticRunCount = max(parties[index].pendingAutomaticRunCount - 1, 0)
        parties[index].pendingAutomaticRunStartedAt = nil
        try coreDataStore.saveParties(parties)
    }

    func unlockParty() throws -> [PartyRecord] {
        var roster = try coreDataStore.loadRosterSnapshot()
        var parties = try coreDataStore.loadParties()
        guard parties.count < PartyRecord.maxPartyCount else {
            throw GuildServiceError.maxPartyCountReached
        }
        guard roster.playerState.gold >= PartyRecord.unlockCost else {
            throw GuildServiceError.insufficientGold(
                required: PartyRecord.unlockCost,
                available: roster.playerState.gold
            )
        }

        let nextPartyId = parties.count + 1
        parties.append(
            PartyRecord(
                partyId: nextPartyId,
                name: PartyRecord.defaultName(for: nextPartyId),
                memberCharacterIds: [],
                selectedLabyrinthId: nil,
                selectedDifficultyTitleId: nil
            )
        )
        roster.playerState.gold -= PartyRecord.unlockCost
        try coreDataStore.saveRosterSnapshot(roster)
        try coreDataStore.saveParties(parties)
        return parties
    }

    func renameParty(partyId: Int, name: String) throws -> [PartyRecord] {
        let normalizedName = PartyRecord.normalizedName(name)
        guard !normalizedName.isEmpty else {
            throw GuildServiceError.invalidPartyName
        }

        var parties = try coreDataStore.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].name = normalizedName
        try coreDataStore.saveParties(parties)
        return parties
    }

    func setSelectedLabyrinth(
        partyId: Int,
        selectedLabyrinthId: Int?,
        selectedDifficultyTitleId: Int?
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataStore.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].selectedLabyrinthId = selectedLabyrinthId
        parties[index].selectedDifficultyTitleId = selectedDifficultyTitleId
        try coreDataStore.saveParties(parties)
        return parties
    }

    func addCharacter(
        characterId: Int,
        toParty partyId: Int
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)

        let roster = try coreDataStore.loadRosterSnapshot()
        guard roster.characters.contains(where: { $0.characterId == characterId }) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        var parties = try coreDataStore.loadParties()
        let targetIndex = try partyIndex(for: partyId, in: parties)
        if parties[targetIndex].memberCharacterIds.contains(characterId) {
            return parties
        }

        guard parties[targetIndex].memberCharacterIds.count < PartyRecord.memberLimit else {
            throw GuildServiceError.partyFull(partyId: partyId)
        }

        if let sourceIndex = parties.firstIndex(where: {
            $0.partyId != partyId && $0.memberCharacterIds.contains(characterId)
        }) {
            parties[sourceIndex].memberCharacterIds.removeAll { $0 == characterId }
        }

        parties[targetIndex].memberCharacterIds.append(characterId)
        try coreDataStore.saveParties(parties)
        return parties
    }

    func removeCharacter(
        characterId: Int,
        fromParty partyId: Int
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataStore.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].memberCharacterIds.removeAll { $0 == characterId }
        try coreDataStore.saveParties(parties)
        return parties
    }

    func replacePartyMembers(
        partyId: Int,
        memberCharacterIds reorderedMemberCharacterIds: [Int]
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataStore.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        let existingMembers = parties[index].memberCharacterIds

        guard reorderedMemberCharacterIds.count <= PartyRecord.memberLimit,
              Set(reorderedMemberCharacterIds) == Set(existingMembers),
              reorderedMemberCharacterIds.count == existingMembers.count else {
            throw GuildServiceError.invalidPartyMemberOrder
        }

        parties[index].memberCharacterIds = reorderedMemberCharacterIds
        try coreDataStore.saveParties(parties)
        return parties
    }

    func addInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        masterData: MasterData
    ) throws {
        guard !inventoryStacks.isEmpty else {
            return
        }

        for stack in inventoryStacks {
            guard stack.count > 0 else {
                throw GuildServiceError.invalidStackCount
            }
            guard stack.itemID.isValid(in: masterData) else {
                throw GuildServiceError.invalidItemStack
            }
        }

        let allInventoryStacks = (try coreDataStore.loadInventoryStacks() + inventoryStacks)
            .normalizedCompositeItemStacks()
        try coreDataStore.saveInventoryStacks(allInventoryStacks)
    }

    func equip(
        itemID: CompositeItemID,
        toCharacter characterId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        guard var character = try coreDataStore.loadCharacter(characterId: characterId) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }
        guard let inventoryStack = try coreDataStore.loadInventoryStack(itemID: itemID) else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        guard inventoryStack.count > 0 else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        let equippedCount = character.equippedItemStacks.reduce(into: 0) { $0 += $1.count }
        let maximumCount = 3 + Int((Double(character.level) / 20).rounded())
        guard equippedCount < maximumCount else {
            throw GuildServiceError.equipLimitReached(maximumCount: maximumCount)
        }

        character.equippedItemStacks = (
            character.equippedItemStacks +
                [CompositeItemStack(itemID: itemID, count: 1)]
        )
        .normalizedCompositeItemStacks()
        clampCurrentHP(of: &character, masterData: masterData)

        let updatedInventoryStack = inventoryStack.count == 1
            ? nil
            : CompositeItemStack(itemID: itemID, count: inventoryStack.count - 1)

        try coreDataStore.saveCharacter(
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
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        guard var character = try coreDataStore.loadCharacter(characterId: characterId) else {
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

        let inventoryStack = try coreDataStore.loadInventoryStack(itemID: itemID)
        let updatedInventoryStack = CompositeItemStack(
            itemID: itemID,
            count: (inventoryStack?.count ?? 0) + 1
        )

        clampCurrentHP(of: &character, masterData: masterData)
        try coreDataStore.saveCharacter(
            character,
            inventoryItemID: itemID,
            inventoryStack: updatedInventoryStack
        )
        return character
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

    private func partyIndex(
        for partyId: Int,
        in parties: [PartyRecord]
    ) throws -> Int {
        guard let index = parties.firstIndex(where: { $0.partyId == partyId }) else {
            throw GuildServiceError.invalidParty(partyId: partyId)
        }
        return index
    }

    private func clampCurrentHP(
        of character: inout CharacterRecord,
        masterData: MasterData
    ) {
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            return
        }

        character.currentHP = min(max(character.currentHP, 0), status.maxHP)
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
        on character: inout CharacterRecord
    ) -> [CompositeItemStack] {
        character.equippedItemStacks = character.orderedEquippedItemStacks

        var removedStacks: [CompositeItemStack] = []
        var overflowCount = character.equippedItemCount - character.maximumEquippedItemCount

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

    private static func normalizedCharacterName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
