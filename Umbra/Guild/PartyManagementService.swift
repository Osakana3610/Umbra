// Owns party configuration, background-run recovery, and party-slot unlock rules.

import Foundation

@MainActor
final class PartyManagementService {
    private let coreDataRepository: GuildCoreDataRepository
    private let explorationCoreDataRepository: ExplorationCoreDataRepository

    init(
        coreDataRepository: GuildCoreDataRepository,
        explorationCoreDataRepository: ExplorationCoreDataRepository
    ) {
        self.coreDataRepository = coreDataRepository
        self.explorationCoreDataRepository = explorationCoreDataRepository
    }

    func recordBackgroundedAt(_ date: Date) throws {
        var roster = try coreDataRepository.loadRosterSnapshot()
        if roster.playerState.lastBackgroundedAt == nil {
            roster.playerState.lastBackgroundedAt = date
        }
        try coreDataRepository.saveRosterSnapshot(roster)
    }

    func queueAutomaticRunsForResume(
        reopenedAt: Date,
        partyStatusesById: [Int: ExplorationPartyStatus],
        masterData: MasterData
    ) throws {
        var roster = try coreDataRepository.loadRosterSnapshot()
        guard let backgroundedAt = roster.playerState.lastBackgroundedAt else {
            return
        }

        var parties = try coreDataRepository.loadParties()
        let charactersById = Dictionary(
            uniqueKeysWithValues: roster.characters.map { ($0.characterId, $0) }
        )

        for index in parties.indices {
            guard let queuePlan = automaticRunQueuePlan(
                for: parties[index],
                status: partyStatusesById[parties[index].partyId],
                charactersById: charactersById,
                backgroundedAt: backgroundedAt,
                reopenedAt: reopenedAt,
                masterData: masterData
            ) else {
                continue
            }

            if parties[index].pendingAutomaticRunCount == 0 {
                parties[index].pendingAutomaticRunStartedAt = queuePlan.firstStartedAt
            }
            parties[index].pendingAutomaticRunCount = min(
                parties[index].pendingAutomaticRunCount + queuePlan.additionalRunCount,
                PartyRecord.maxPendingAutomaticRunCount
            )
        }

        roster.playerState.lastBackgroundedAt = nil
        try coreDataRepository.saveRosterSnapshot(roster)
        try coreDataRepository.saveParties(parties)
    }

    func consumePendingAutomaticRun(partyId: Int) throws {
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].pendingAutomaticRunCount = max(parties[index].pendingAutomaticRunCount - 1, 0)
        parties[index].pendingAutomaticRunStartedAt = nil
        try coreDataRepository.saveParties(parties)
    }

    func clearPendingAutomaticRuns(partyId: Int) throws {
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].pendingAutomaticRunCount = 0
        parties[index].pendingAutomaticRunStartedAt = nil
        try coreDataRepository.saveParties(parties)
    }

    func unlockParty() throws -> [PartyRecord] {
        try unlockParty(consuming: nil, masterData: nil)
    }

    func unlockParty(
        consuming requiredJewel: EconomicCapJewelSelection?,
        masterData: MasterData
    ) throws -> [PartyRecord] {
        try unlockParty(consuming: requiredJewel, masterData: Optional(masterData))
    }

    func renameParty(partyId: Int, name: String) throws -> [PartyRecord] {
        let normalizedName = PartyRecord.normalizedName(name)
        guard !normalizedName.isEmpty else {
            throw GuildServiceError.invalidPartyName
        }

        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].name = normalizedName
        try coreDataRepository.saveParties(parties)
        return parties
    }

    func setSelectedLabyrinth(
        partyId: Int,
        selectedLabyrinthId: Int?,
        selectedDifficultyTitleId: Int?
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataRepository.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].selectedLabyrinthId = selectedLabyrinthId
        parties[index].selectedDifficultyTitleId = selectedDifficultyTitleId
        try coreDataRepository.saveParties(parties)
        return parties
    }

    func setAutomaticallyUsesCatTicket(
        partyId: Int,
        isEnabled: Bool
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataRepository.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].automaticallyUsesCatTicket = isEnabled
        try coreDataRepository.saveParties(parties)
        return parties
    }

    func addCharacter(
        characterId: Int,
        toParty partyId: Int
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataRepository.validateCharacterMutationIsAllowed(characterId: characterId)
        try await explorationCoreDataRepository.validatePartyMutationIsAllowed(partyId: partyId)

        let roster = try coreDataRepository.loadRosterSnapshot()
        guard roster.characters.contains(where: { $0.characterId == characterId }) else {
            throw GuildServiceError.characterNotFound(characterId: characterId)
        }

        var parties = try coreDataRepository.loadParties()
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
        try coreDataRepository.saveParties(parties)
        return parties
    }

    func removeCharacter(
        characterId: Int,
        fromParty partyId: Int
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataRepository.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        parties[index].memberCharacterIds.removeAll { $0 == characterId }
        try coreDataRepository.saveParties(parties)
        return parties
    }

    func replacePartyMembers(
        partyId: Int,
        memberCharacterIds reorderedMemberCharacterIds: [Int]
    ) async throws -> [PartyRecord] {
        try await explorationCoreDataRepository.validatePartyMutationIsAllowed(partyId: partyId)
        var parties = try coreDataRepository.loadParties()
        let index = try partyIndex(for: partyId, in: parties)
        let existingMembers = parties[index].memberCharacterIds

        guard reorderedMemberCharacterIds.count <= PartyRecord.memberLimit,
              Set(reorderedMemberCharacterIds) == Set(existingMembers),
              reorderedMemberCharacterIds.count == existingMembers.count else {
            throw GuildServiceError.invalidPartyMemberOrder
        }

        parties[index].memberCharacterIds = reorderedMemberCharacterIds
        try coreDataRepository.saveParties(parties)
        return parties
    }

    private func unlockParty(
        consuming requiredJewel: EconomicCapJewelSelection?,
        masterData: MasterData?
    ) throws -> [PartyRecord] {
        // Party-slot unlocks are persisted in one snapshot so the new slot, spent gold, and any
        // consumed capped-price jewel stay in sync.
        var roster = try coreDataRepository.loadRosterSnapshot()
        var parties = try coreDataRepository.loadParties()
        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        guard parties.count < PartyRecord.maxPartyCount else {
            throw GuildServiceError.maxPartyCountReached
        }
        guard let unlockCost = PartyRecord.unlockCost(forExistingPartyCount: parties.count) else {
            throw GuildServiceError.maxPartyCountReached
        }
        guard roster.playerState.gold >= unlockCost else {
            throw GuildServiceError.insufficientGold(
                required: unlockCost,
                available: roster.playerState.gold
            )
        }
        // The last slot keeps the gold cost at the shared cap and turns any overflow into a
        // capped-price jewel requirement.
        if PartyRecord.unlockRequiresCappedJewel(forExistingPartyCount: parties.count) {
            guard let requiredJewel else {
                throw GuildServiceError.partyUnlockRequiresCapJewel
            }
            guard let masterData, isEconomicCapJewel(requiredJewel.itemID, masterData: masterData) else {
                throw GuildServiceError.invalidPartyUnlockJewel
            }

            try GuildMutationResolver.consumeJewelEnhancementInput(
                itemID: requiredJewel.itemID,
                characterId: requiredJewel.characterId,
                inventoryStacks: &inventoryStacks,
                roster: &roster
            )
        }

        let nextPartyId = parties.count + 1
        parties.append(
            PartyRecord(
                partyId: nextPartyId,
                name: PartyRecord.defaultName(for: nextPartyId),
                memberCharacterIds: [],
                selectedLabyrinthId: nil,
                selectedDifficultyTitleId: nil,
                automaticallyUsesCatTicket: false
            )
        )
        roster.playerState.gold -= unlockCost
        try coreDataRepository.saveRosterState(
            roster,
            parties: parties,
            inventoryStacks: inventoryStacks
        )
        return parties
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

    private func automaticRunQueuePlan(
        for party: PartyRecord,
        status: ExplorationPartyStatus?,
        charactersById: [Int: CharacterRecord],
        backgroundedAt: Date,
        reopenedAt: Date,
        masterData: MasterData
    ) -> (firstStartedAt: Date, additionalRunCount: Int)? {
        guard let labyrinthId = party.selectedLabyrinthId,
              let labyrinth = masterData.labyrinths.first(where: { $0.id == labyrinthId }),
              !party.memberCharacterIds.isEmpty,
              party.memberCharacterIds.allSatisfy({ characterId in
                  (charactersById[characterId]?.currentHP ?? 0) > 0
              }),
              status?.activeRun == nil else {
            return nil
        }

        let totalBattleCount = labyrinth.floors.reduce(into: 0) { partialResult, floor in
            partialResult += floor.battleCount
        }
        let runDurationSeconds = totalBattleCount * max(labyrinth.progressIntervalSeconds, 1)
        guard runDurationSeconds > 0 else {
            return nil
        }

        let firstStartedAt = max(
            backgroundedAt,
            status?.latestCompletedRun?.completion?.completedAt ?? backgroundedAt
        )
        let additionalRunCount = automaticRunCount(
            firstStartedAt: firstStartedAt,
            reopenedAt: reopenedAt,
            runDurationSeconds: runDurationSeconds
        )
        guard additionalRunCount > 0 else {
            return nil
        }

        return (
            firstStartedAt: firstStartedAt,
            additionalRunCount: additionalRunCount
        )
    }

    private func automaticRunCount(
        firstStartedAt: Date,
        reopenedAt: Date,
        runDurationSeconds: Int
    ) -> Int {
        let elapsedSeconds = Int(reopenedAt.timeIntervalSince(firstStartedAt))
        guard elapsedSeconds > 0 else {
            return 0
        }

        // Only queue runs that fully finished while the app was backgrounded.
        return elapsedSeconds / runDurationSeconds
    }

    private func isEconomicCapJewel(
        _ itemID: CompositeItemID,
        masterData: MasterData
    ) -> Bool {
        guard let baseItem = masterData.items.first(where: { $0.id == itemID.baseItemId }),
              baseItem.category == .jewel else {
            return false
        }

        // Match the unlock check to the same capped purchase price shown everywhere else in the
        // economy UI.
        return ShopPricingCalculator.purchasePrice(for: itemID, masterData: masterData) == EconomyPricing.maximumEconomicPrice
    }
}
