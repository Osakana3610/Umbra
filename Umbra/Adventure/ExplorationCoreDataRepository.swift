// Persists exploration runs on background Core Data contexts and builds value snapshots for upper layers.

import CoreData
import Foundation

actor ExplorationCoreDataRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadSnapshot() async throws -> ExplorationRunSnapshot {
        try await perform { context in
            let runs = try ExplorationCoreDataBridge.fetchRunEntities(in: context)
                .map(ExplorationCoreDataBridge.makeRunSummaryRecord)
            return ExplorationRunSnapshot(
                runs: runs,
                didApplyRewards: false,
                appliedInventoryCounts: [:],
                appliedShopInventoryCounts: [:],
                dropNotificationBatches: []
            )
        }
    }

    func loadBattleLogIndexEntries(
        partyId: Int,
        partyRunId: Int,
        battleIndex: Int,
        count: Int
    ) async throws -> [ExplorationBattleLog.IndexEntry] {
        try await perform { context in
            guard count > 0 else {
                return []
            }

            let logEntities = try ExplorationCoreDataBridge.fetchBattleLogEntities(
                partyId: partyId,
                partyRunId: partyRunId,
                range: battleIndex..<(battleIndex + count),
                in: context
            )
            return logEntities.reversed().map(ExplorationCoreDataBridge.makeBattleLogIndexEntry)
        }
    }

    func loadBattleLog(
        partyId: Int,
        partyRunId: Int,
        battleIndex: Int
    ) async throws -> ExplorationBattleLog? {
        try await perform { context in
            guard let entity = try ExplorationCoreDataBridge.fetchBattleLogEntity(
                partyId: partyId,
                partyRunId: partyRunId,
                battleIndex: battleIndex,
                in: context
            ) else {
                return nil
            }

            return ExplorationCoreDataBridge.makeBattleLog(from: entity)
        }
    }

    func loadRunDetail(
        partyId: Int,
        partyRunId: Int
    ) async throws -> RunSessionRecord? {
        try await perform { context in
            guard let entity = try ExplorationCoreDataBridge.fetchRunEntity(
                partyId: partyId,
                partyRunId: partyRunId,
                in: context
            ) else {
                return nil
            }

            return ExplorationCoreDataBridge.makeRunDetailRecord(from: entity)
        }
    }

    func loadStartContext(
        partyId: Int,
        labyrinthId: Int,
        requestedDifficultyTitleId: Int?,
        masterData: MasterData
    ) async throws -> (nextPartyRunId: Int, partyMembers: [CharacterRecord], selectedDifficultyTitleId: Int) {
        try await perform { context in
            guard try ExplorationCoreDataBridge.isLabyrinthUnlocked(
                labyrinthId: labyrinthId,
                masterData: masterData,
                in: context
            ) else {
                throw ExplorationError.labyrinthLocked(labyrinthId: labyrinthId)
            }

            guard try !ExplorationCoreDataBridge.hasActiveRun(
                partyId: partyId,
                in: context
            ) else {
                throw ExplorationError.activeRunAlreadyExists(partyId: partyId)
            }

            let party = try ExplorationCoreDataBridge.fetchPartyEntity(
                partyId: partyId,
                in: context
            )
            let memberCharacterIds = ExplorationCoreDataBridge.memberCharacterIds(from: party)
            guard !memberCharacterIds.isEmpty else {
                throw ExplorationError.partyHasNoMembers(partyId: partyId)
            }

            let memberEntities = try ExplorationCoreDataBridge.fetchCharacterEntities(
                characterIds: memberCharacterIds,
                in: context
            )
            let membersById = Dictionary(uniqueKeysWithValues: memberEntities.map { (Int($0.characterId), $0) })
            let partyMembers = try memberCharacterIds.map { characterId in
                guard let entity = membersById[characterId] else {
                    throw ExplorationError.invalidRunMember(characterId: characterId)
                }
                return ExplorationCoreDataBridge.makeCharacterRecord(from: entity)
            }

            if partyMembers.contains(where: { $0.currentHP <= 0 }) {
                throw ExplorationError.partyHasDefeatedMember(partyId: partyId)
            }

            for memberEntity in memberEntities {
                try ExplorationCoreDataBridge.restoreCurrentHPToMax(
                    of: memberEntity,
                    masterData: masterData
                )
            }

            let healedPartyMembers = try memberCharacterIds.map { characterId in
                guard let entity = membersById[characterId] else {
                    throw ExplorationError.invalidRunMember(characterId: characterId)
                }
                return ExplorationCoreDataBridge.makeCharacterRecord(from: entity)
            }
            let defaultDifficultyTitleId = masterData.defaultExplorationDifficultyTitle?.id ?? 1
            let highestUnlockedDifficultyTitleId = try ExplorationCoreDataBridge.highestUnlockedDifficultyTitleId(
                labyrinthId: labyrinthId,
                defaultTitleId: defaultDifficultyTitleId,
                in: context
            )

            return (
                nextPartyRunId: try ExplorationCoreDataBridge.nextPartyRunId(
                    partyId: partyId,
                    in: context
                ),
                partyMembers: healedPartyMembers,
                selectedDifficultyTitleId: masterData.resolvedExplorationDifficultyTitleId(
                    requestedTitleId: requestedDifficultyTitleId,
                    highestUnlockedTitleId: highestUnlockedDifficultyTitleId
                )
            )
        }
    }

    func insertRun(_ session: RunSessionRecord) async throws {
        try await insertRun(
            session,
            battleLogs: [],
            consumesCatTicket: false
        )
    }

    func insertRun(
        _ session: RunSessionRecord,
        battleLogs: [ExplorationBattleLog]
    ) async throws {
        try await insertRun(
            session,
            battleLogs: battleLogs,
            consumesCatTicket: false
        )
    }

    func loadCatTicketCount() async throws -> Int {
        try await perform { context in
            let playerState = try ExplorationCoreDataBridge.fetchOrCreatePlayerState(in: context)
            return Int(playerState.catTicketCount)
        }
    }

    func insertRun(
        _ session: RunSessionRecord,
        battleLogs: [ExplorationBattleLog],
        consumesCatTicket: Bool
    ) async throws {
        try await perform { context in
            guard try !ExplorationCoreDataBridge.hasActiveRun(
                partyId: session.partyId,
                in: context
            )
            else {
                throw ExplorationError.activeRunAlreadyExists(partyId: session.partyId)
            }

            if consumesCatTicket {
                let playerState = try ExplorationCoreDataBridge.fetchOrCreatePlayerState(in: context)
                guard playerState.catTicketCount > 0 else {
                    throw ExplorationError.insufficientCatTickets
                }
                playerState.catTicketCount -= 1
            }

            try ExplorationCoreDataBridge.insertRunEntity(
                for: session,
                battleLogs: battleLogs,
                in: context
            )
        }
    }

    func pruneCompletedRunsExceedingRetentionLimit() async throws -> Bool {
        try await perform { context in
            try ExplorationCoreDataBridge.pruneCompletedRunsExceedingRetentionLimit(in: context)
        }
    }

    func commitProgressUpdates(
        _ updates: [(currentSession: RunSessionRecord, resolvedSession: RunSessionRecord)],
        masterData: MasterData
    ) async throws -> (
        didApplyRewards: Bool,
        appliedInventoryCounts: [CompositeItemID: Int],
        appliedShopInventoryCounts: [CompositeItemID: Int]
    ) {
        try await perform { context in
            guard !updates.isEmpty else {
                return (
                    didApplyRewards: false,
                    appliedInventoryCounts: [:],
                    appliedShopInventoryCounts: [:]
                )
            }

            let runEntities = try ExplorationCoreDataBridge.fetchRunEntities(in: context)
            let entitiesByIdentifier = Dictionary(
                uniqueKeysWithValues: runEntities.map { entity in
                    (ExplorationCoreDataBridge.runIdentifier(for: entity), entity)
                }
            )

            var didApplyRewards = false
            var appliedInventoryCounts: [CompositeItemID: Int] = [:]
            var appliedShopInventoryCounts: [CompositeItemID: Int] = [:]

            for update in updates {
                let currentSession = update.currentSession
                let resolvedSession = update.resolvedSession
                let identifier = resolvedSession.runSessionID

                guard let entity = entitiesByIdentifier[identifier] else {
                    throw ExplorationError.runNotFound(
                        partyId: resolvedSession.partyId,
                        partyRunId: resolvedSession.partyRunId
                    )
                }

                if resolvedSession != currentSession {
                    try ExplorationCoreDataBridge.applyResolvedSession(
                        resolvedSession,
                        to: entity,
                        in: context
                    )
                }

                guard let completion = resolvedSession.completion,
                      !entity.rewardsApplied else {
                    continue
                }

                let rewardCounts = try ExplorationCoreDataBridge.applyCompletionRewards(
                    completion: completion,
                    labyrinthId: resolvedSession.labyrinthId,
                    selectedDifficultyTitleId: resolvedSession.selectedDifficultyTitleId,
                    currentPartyHPs: resolvedSession.currentPartyHPs,
                    memberCharacterIds: resolvedSession.memberCharacterIds,
                    in: context,
                    masterData: masterData
                )
                entity.rewardsApplied = true
                didApplyRewards = true
                for (itemID, count) in rewardCounts.inventoryCounts {
                    appliedInventoryCounts[itemID, default: 0] += count
                }
                for (itemID, count) in rewardCounts.shopInventoryCounts {
                    appliedShopInventoryCounts[itemID, default: 0] += count
                }
            }

            return (
                didApplyRewards: didApplyRewards,
                appliedInventoryCounts: appliedInventoryCounts,
                appliedShopInventoryCounts: appliedShopInventoryCounts
            )
        }
    }

    func hasActiveRun(partyId: Int) async throws -> Bool {
        try await perform { context in
            try ExplorationCoreDataBridge.hasActiveRun(
                partyId: partyId,
                in: context
            )
        }
    }

    func validatePartyMutationIsAllowed(partyId: Int) async throws {
        try await perform { context in
            guard try !ExplorationCoreDataBridge.hasActiveRun(
                partyId: partyId,
                in: context
            ) else {
                throw ExplorationError.partyLockedByActiveRun(partyId: partyId)
            }
        }
    }

    func validateCharacterMutationIsAllowed(characterId: Int) async throws {
        try await perform { context in
            guard try !ExplorationCoreDataBridge.hasActiveRun(
                characterId: characterId,
                in: context
            ) else {
                throw ExplorationError.characterLockedByActiveRun(characterId: characterId)
            }
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        context.undoManager = nil

        return try await context.perform {
            let result = try operation(context)
            if context.hasChanges {
                try context.save()
            }
            return result
        }
    }
}

nonisolated private enum ExplorationCoreDataBridge {
    static func fetchRunEntities(
        in context: NSManagedObjectContext
    ) throws -> [RunSessionEntity] {
        let request = NSFetchRequest<RunSessionEntity>(entityName: "RunSessionEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "partyId", ascending: true),
            NSSortDescriptor(key: "partyRunId", ascending: false),
        ]
        return try context.fetch(request)
    }

    static func fetchRunEntity(
        partyId: Int,
        partyRunId: Int,
        in context: NSManagedObjectContext
    ) throws -> RunSessionEntity? {
        let request = NSFetchRequest<RunSessionEntity>(entityName: "RunSessionEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "partyId == %d AND partyRunId == %d",
            partyId,
            partyRunId
        )
        return try context.fetch(request).first
    }

    static func fetchBattleLogEntities(
        partyId: Int,
        partyRunId: Int,
        range: Range<Int>,
        in context: NSManagedObjectContext
    ) throws -> [RunSessionBattleLogEntity] {
        let request = NSFetchRequest<RunSessionBattleLogEntity>(entityName: "RunSessionBattleLogEntity")
        request.predicate = NSPredicate(
            format: "runSession.partyId == %d AND runSession.partyRunId == %d AND logIndex >= %d AND logIndex < %d",
            partyId,
            partyRunId,
            range.lowerBound,
            range.upperBound
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "logIndex", ascending: true)
        ]
        return try context.fetch(request)
    }

    static func fetchBattleLogEntity(
        partyId: Int,
        partyRunId: Int,
        battleIndex: Int,
        in context: NSManagedObjectContext
    ) throws -> RunSessionBattleLogEntity? {
        let request = NSFetchRequest<RunSessionBattleLogEntity>(entityName: "RunSessionBattleLogEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "runSession.partyId == %d AND runSession.partyRunId == %d AND logIndex == %d",
            partyId,
            partyRunId,
            battleIndex
        )
        return try context.fetch(request).first
    }

    static func pruneCompletedRunsExceedingRetentionLimit(
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let retentionCount = ExplorationLogRetentionRepository.configuredCount()
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "RunSessionEntity")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "completedAt != nil")
        request.sortDescriptors = [
            NSSortDescriptor(key: "completedAt", ascending: false),
            NSSortDescriptor(key: "partyId", ascending: false),
            NSSortDescriptor(key: "partyRunId", ascending: false),
        ]

        let objectIDs = try context.fetch(request)
        guard objectIDs.count > retentionCount else {
            return false
        }

        for objectID in objectIDs.dropFirst(retentionCount) {
            context.delete(try context.existingObject(with: objectID))
        }

        return true
    }

    static func hasActiveRun(
        partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "RunSessionEntity")
        request.fetchLimit = 1
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(
            format: "partyId == %d AND completedAt == nil",
            partyId
        )
        return try !context.fetch(request).isEmpty
    }

    static func hasActiveRun(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "RunSessionMemberEntity")
        request.fetchLimit = 1
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(
            format: "characterId == %d AND runSession.completedAt == nil",
            characterId
        )
        return try !context.fetch(request).isEmpty
    }

    static func nextPartyRunId(
        partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "RunSessionEntity")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "partyId == %d", partyId)

        let expression = NSExpressionDescription()
        expression.name = "maxPartyRunId"
        expression.expression = NSExpression(forFunction: "max:", arguments: [NSExpression(forKeyPath: "partyRunId")])
        expression.expressionResultType = .integer64AttributeType
        request.propertiesToFetch = [expression]

        let maximum = (try context.fetch(request).first?["maxPartyRunId"] as? Int64) ?? 0
        return Int(maximum) + 1
    }

    static func fetchPartyEntity(
        partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> PartyEntity {
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "partyId == %d", partyId)

        guard let party = try context.fetch(request).first else {
            throw ExplorationError.invalidParty(partyId: partyId)
        }

        return party
    }

    static func fetchCharacterEntities(
        characterIds: [Int],
        in context: NSManagedObjectContext
    ) throws -> [CharacterEntity] {
        guard !characterIds.isEmpty else {
            return []
        }

        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.predicate = NSPredicate(format: "characterId IN %@", characterIds)
        return try context.fetch(request)
    }

    static func fetchLabyrinthProgressEntity(
        labyrinthId: Int,
        in context: NSManagedObjectContext
    ) throws -> LabyrinthProgressEntity? {
        let request = NSFetchRequest<LabyrinthProgressEntity>(entityName: "LabyrinthProgressEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "labyrinthId == %d", labyrinthId)
        return try context.fetch(request).first
    }

    static func highestUnlockedDifficultyTitleId(
        labyrinthId: Int,
        defaultTitleId: Int,
        in context: NSManagedObjectContext
    ) throws -> Int {
        guard let progressEntity = try fetchLabyrinthProgressEntity(
            labyrinthId: labyrinthId,
            in: context
        ) else {
            return defaultTitleId
        }

        let storedTitleId = Int(progressEntity.highestUnlockedDifficultyTitleId)
        return storedTitleId > 0 ? storedTitleId : defaultTitleId
    }

    static func isLabyrinthUnlocked(
        labyrinthId: Int,
        masterData: MasterData,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        // The first labyrinth is always available; later labyrinths become playable once a
        // progress row exists for them.
        if masterData.defaultUnlockedLabyrinthId == labyrinthId {
            return true
        }

        return try fetchLabyrinthProgressEntity(
            labyrinthId: labyrinthId,
            in: context
        ) != nil
    }

    static func fetchOrCreatePlayerState(
        in context: NSManagedObjectContext
    ) throws -> PlayerStateEntity {
        let request = NSFetchRequest<PlayerStateEntity>(entityName: "PlayerStateEntity")
        request.fetchLimit = 1

        if let entity = try context.fetch(request).first {
            return entity
        }

        guard let entity = NSEntityDescription.insertNewObject(
            forEntityName: "PlayerStateEntity",
            into: context
        ) as? PlayerStateEntity else {
            fatalError("PlayerStateEntity の生成に失敗しました。")
        }

        entity.gold = Int64(PlayerState.initial.gold)
        entity.catTicketCount = Int64(PlayerState.initial.catTicketCount)
        entity.nextCharacterId = Int64(PlayerState.initial.nextCharacterId)
        entity.autoReviveDefeatedCharacters = PlayerState.initial.autoReviveDefeatedCharacters
        return entity
    }

    static func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        let members = entity.members as? Set<PartyMemberEntity> ?? []
        return members.sorted { lhs, rhs in
            Int(lhs.formationIndex) < Int(rhs.formationIndex)
        }
        .map { Int($0.characterId) }
    }

    static func memberCharacterIds(from entity: RunSessionEntity) -> [Int] {
        orderedMembers(from: entity).map { Int($0.characterId) }
    }

    static func currentPartyHPs(from entity: RunSessionEntity) -> [Int] {
        orderedMembers(from: entity).map { Int($0.currentHP) }
    }

    static func orderedMembers(
        from entity: RunSessionEntity
    ) -> [RunSessionMemberEntity] {
        let members = entity.members as? Set<RunSessionMemberEntity> ?? []
        return members.sorted { lhs, rhs in
            Int(lhs.formationIndex) < Int(rhs.formationIndex)
        }
    }

    static func insertRunEntity(
        for session: RunSessionRecord,
        battleLogs: [ExplorationBattleLog],
        in context: NSManagedObjectContext
    ) throws {
        guard let runEntity = NSEntityDescription.insertNewObject(
            forEntityName: "RunSessionEntity",
            into: context
        ) as? RunSessionEntity else {
            fatalError("RunSessionEntity の生成に失敗しました。")
        }

        applySessionScalars(session, to: runEntity)
        for (formationIndex, characterId) in session.memberCharacterIds.enumerated() {
            guard let memberEntity = NSEntityDescription.insertNewObject(
                forEntityName: "RunSessionMemberEntity",
                into: context
            ) as? RunSessionMemberEntity else {
                fatalError("RunSessionMemberEntity の生成に失敗しました。")
            }

            memberEntity.runSession = runEntity
            memberEntity.formationIndex = Int64(formationIndex)
            memberEntity.characterId = Int64(characterId)
            memberEntity.currentHP = Int64(session.currentPartyHPs[formationIndex])
            memberEntity.experienceMultiplier = session.memberExperienceMultipliers[formationIndex]
            // A run keeps its own frozen member snapshot so later guild edits do not rewrite
            // historical battle logs or invalidate continuation state.
            if session.memberSnapshots.indices.contains(formationIndex) {
                applyMemberSnapshot(session.memberSnapshots[formationIndex], to: memberEntity)
            }
        }
        appendBattleLogs(
            battleLogs,
            to: runEntity,
            in: context
        )
        upsertExperienceRewards(
            session.experienceRewards,
            to: runEntity,
            in: context
        )
        appendDropRewards(
            session.dropRewards,
            to: runEntity,
            in: context
        )
    }

    static func applyResolvedSession(
        _ session: RunSessionRecord,
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) throws {
        applySessionScalars(session, to: entity)
        updateMembers(of: entity, with: session)
    }

    static func applyCompletionRewards(
        completion: RunCompletionRecord,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        currentPartyHPs: [Int],
        memberCharacterIds: [Int],
        in context: NSManagedObjectContext,
        masterData: MasterData
    ) throws -> (
        inventoryCounts: [CompositeItemID: Int],
        shopInventoryCounts: [CompositeItemID: Int]
    ) {
        let playerState = try fetchOrCreatePlayerState(in: context)
        playerState.gold += Int64(completion.gold)

        let characterEntities = try fetchCharacterEntities(
            characterIds: memberCharacterIds,
            in: context
        )
        let charactersById = Dictionary(uniqueKeysWithValues: characterEntities.map { (Int($0.characterId), $0) })
        let racesById = Dictionary(uniqueKeysWithValues: masterData.races.map { ($0.id, $0) })
        let experienceByCharacterId = Dictionary(
            uniqueKeysWithValues: completion.experienceRewards.map { ($0.characterId, $0.experience) }
        )

        // Completion rewards are applied against current guild entities instead of the run member
        // snapshots so the latest roster state remains authoritative after the sortie ends.
        for (formationIndex, characterId) in memberCharacterIds.enumerated() {
            guard let characterEntity = charactersById[characterId] else {
                throw ExplorationError.invalidRunMember(characterId: characterId)
            }

            let additionalExperience = experienceByCharacterId[characterId] ?? 0
            if additionalExperience > 0 {
                characterEntity.experience += Int64(additionalExperience)
                if let race = racesById[Int(characterEntity.raceId)] {
                    characterEntity.level = Int64(
                        CharacterLevelProgression.level(
                            for: Int(characterEntity.experience),
                            levelCap: race.levelCap
                        )
                    )
                }
            }

            let currentHP = currentPartyHPs.indices.contains(formationIndex)
                ? currentPartyHPs[formationIndex]
                : 0
            // Defeated members can auto-revive on return, otherwise the run writes back the
            // persisted HP exactly as it ended.
            if playerState.autoReviveDefeatedCharacters && currentHP == 0 {
                try restoreCurrentHPToMax(
                    of: characterEntity,
                    masterData: masterData
                )
            } else {
                characterEntity.currentHP = Int64(max(currentHP, 0))
            }
        }

        let autoSellItemIDs = autoSellItemIDs(from: playerState)
        let dropCounts = Dictionary(
            completion.dropRewards.map { ($0.itemID, 1) },
            uniquingKeysWith: +
        )
        let inventoryCounts = dropCounts.filter { autoSellItemIDs.contains($0.key) == false }
        let shopInventoryCounts = dropCounts.filter { autoSellItemIDs.contains($0.key) }
        // Drop rewards are merged in one pass per destination so reward application keeps one
        // deterministic result while respecting auto-sell routing by full composite item ID.
        applyInventoryCounts(inventoryCounts, in: context)
        applyShopInventoryCounts(shopInventoryCounts, in: context)

        try unlockNextDifficultyIfNeeded(
            completion: completion,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: selectedDifficultyTitleId,
            in: context,
            masterData: masterData
        )
        try unlockNextLabyrinthIfNeeded(
            completion: completion,
            labyrinthId: labyrinthId,
            in: context,
            masterData: masterData
        )

        return (
            inventoryCounts: inventoryCounts,
            shopInventoryCounts: shopInventoryCounts
        )
    }

    static func unlockNextDifficultyIfNeeded(
        completion: RunCompletionRecord,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        in context: NSManagedObjectContext,
        masterData: MasterData
    ) throws {
        guard completion.reason == .cleared,
              let defaultTitleId = masterData.defaultExplorationDifficultyTitle?.id,
              let nextTitleId = masterData.nextExplorationDifficultyTitleId(after: selectedDifficultyTitleId) else {
            return
        }

        let entity = try fetchLabyrinthProgressEntity(
            labyrinthId: labyrinthId,
            in: context
        ) ?? {
            guard let insertedEntity = NSEntityDescription.insertNewObject(
                forEntityName: "LabyrinthProgressEntity",
                into: context
            ) as? LabyrinthProgressEntity else {
                fatalError("LabyrinthProgressEntity の生成に失敗しました。")
            }
            insertedEntity.labyrinthId = Int64(labyrinthId)
            insertedEntity.highestUnlockedDifficultyTitleId = Int64(defaultTitleId)
            return insertedEntity
        }()

        let titles = masterData.explorationDifficultyTitles
        let currentHighestTitleId = Int(entity.highestUnlockedDifficultyTitleId) > 0
            ? Int(entity.highestUnlockedDifficultyTitleId)
            : defaultTitleId
        let currentHighestIndex = titles.firstIndex(where: { $0.id == currentHighestTitleId }) ?? 0
        let nextTitleIndex = titles.firstIndex(where: { $0.id == nextTitleId }) ?? currentHighestIndex
        // Unlock progress only moves forward; replaying a lower difficulty never overwrites the
        // highest unlocked tier already recorded for the labyrinth.
        guard nextTitleIndex > currentHighestIndex else {
            return
        }

        entity.highestUnlockedDifficultyTitleId = Int64(nextTitleId)
    }

    static func unlockNextLabyrinthIfNeeded(
        completion: RunCompletionRecord,
        labyrinthId: Int,
        in context: NSManagedObjectContext,
        masterData: MasterData
    ) throws {
        // Clearing a labyrinth materializes the next labyrinth's progress row so UI filtering and
        // sortie validation can both treat it as unlocked immediately.
        guard completion.reason == .cleared,
              let nextLabyrinthId = masterData.nextLabyrinthId(after: labyrinthId),
              let defaultTitleId = masterData.defaultExplorationDifficultyTitle?.id,
              try fetchLabyrinthProgressEntity(labyrinthId: nextLabyrinthId, in: context) == nil else {
            return
        }

        guard let entity = NSEntityDescription.insertNewObject(
            forEntityName: "LabyrinthProgressEntity",
            into: context
        ) as? LabyrinthProgressEntity else {
            fatalError("LabyrinthProgressEntity の生成に失敗しました。")
        }

        entity.labyrinthId = Int64(nextLabyrinthId)
        entity.highestUnlockedDifficultyTitleId = Int64(defaultTitleId)
    }

    static func applyInventoryCounts(
        _ itemCounts: [CompositeItemID: Int],
        in context: NSManagedObjectContext
    ) {
        guard !itemCounts.isEmpty else {
            return
        }

        // Fetch all touched stacks up front, then upsert in memory so one completion pass does
        // not issue a per-item fetch for every reward.
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.predicate = CompositeItemPersistence.predicate(for: itemCounts.keys)
        let existingEntities = (try? context.fetch(request)) ?? []
        var entitiesByID = Dictionary(uniqueKeysWithValues: existingEntities.map { (CompositeItemID(entity: $0), $0) })

        for (itemID, count) in itemCounts where count > 0 {
            let entity: InventoryItemEntity
            if let existingEntity = entitiesByID[itemID] {
                entity = existingEntity
            } else {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                itemID.apply(to: insertedEntity)
                insertedEntity.count = 0
                entitiesByID[itemID] = insertedEntity
                entity = insertedEntity
            }

            entity.count += Int64(count)
        }
    }

    static func applyShopInventoryCounts(
        _ itemCounts: [CompositeItemID: Int],
        in context: NSManagedObjectContext
    ) {
        guard !itemCounts.isEmpty else {
            return
        }

        let request = NSFetchRequest<ShopItemEntity>(entityName: "ShopItemEntity")
        request.predicate = CompositeItemPersistence.predicate(for: itemCounts.keys)
        let existingEntities = (try? context.fetch(request)) ?? []
        var entitiesByID = Dictionary(uniqueKeysWithValues: existingEntities.map { (CompositeItemID(entity: $0), $0) })

        for (itemID, count) in itemCounts where count > 0 {
            let entity: ShopItemEntity
            if let existingEntity = entitiesByID[itemID] {
                entity = existingEntity
            } else {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "ShopItemEntity",
                    into: context
                ) as? ShopItemEntity else {
                    fatalError("ShopItemEntity の生成に失敗しました。")
                }
                itemID.apply(to: insertedEntity)
                insertedEntity.count = 0
                entitiesByID[itemID] = insertedEntity
                entity = insertedEntity
            }

            entity.count += Int64(count)
        }
    }

    static func makeRunSummaryRecord(from entity: RunSessionEntity) -> RunSessionRecord {
        let shouldLoadDeferredRewards = entity.completedAt == nil
        let members = orderedMembers(from: entity)
        let memberSnapshots = members.map(makeCharacterRecord)
        let memberCharacterIds = members.map { Int($0.characterId) }
        let currentPartyHPs = members.map { Int($0.currentHP) }
        let memberExperienceMultipliers = members.map(\.experienceMultiplier)
        let experienceRewards = shouldLoadDeferredRewards ? makeExperienceRewards(from: entity) : []
        let dropRewards = shouldLoadDeferredRewards ? makeDropRewards(from: entity) : []

        return RunSessionRecord(
            partyRunId: Int(entity.partyRunId),
            partyId: Int(entity.partyId),
            labyrinthId: Int(entity.labyrinthId),
            selectedDifficultyTitleId: Int(entity.selectedDifficultyTitleId),
            targetFloorNumber: Int(entity.targetFloorNumber),
            startedAt: entity.startedAt ?? .distantPast,
            rootSeed: UInt64(bitPattern: entity.rootSeedSigned),
            memberSnapshots: memberSnapshots,
            memberCharacterIds: memberCharacterIds,
            totalBattleCount: Int(entity.totalBattleCount),
            completedBattleCount: Int(entity.completedBattleCount),
            currentPartyHPs: currentPartyHPs,
            memberExperienceMultipliers: memberExperienceMultipliers,
            progressIntervalMultiplier: entity.progressIntervalMultiplier,
            goldMultiplier: entity.goldMultiplier,
            rareDropMultiplier: entity.rareDropMultiplier,
            partyAverageLuck: entity.partyAverageLuck,
            latestBattleFloorNumber: entity.latestBattleFloorNumber > 0 ? Int(entity.latestBattleFloorNumber) : nil,
            latestBattleNumber: entity.latestBattleNumber > 0 ? Int(entity.latestBattleNumber) : nil,
            latestBattleOutcome: decodedOptionalPersistenceOrder(
                BattleOutcome.self,
                from: entity.latestBattleOutcomeValue
            ),
            goldBuffer: Int(entity.goldBuffer),
            experienceRewards: experienceRewards,
            dropRewards: dropRewards,
            completion: makeCompletionRecord(
                from: entity,
                experienceRewards: experienceRewards,
                dropRewards: dropRewards
            )
        )
    }

    static func makeRunDetailRecord(from entity: RunSessionEntity) -> RunSessionRecord {
        let experienceRewards = makeExperienceRewards(from: entity)
        let dropRewards = makeDropRewards(from: entity)
        let summary = makeRunSummaryRecord(from: entity)

        return RunSessionRecord(
            partyRunId: summary.partyRunId,
            partyId: summary.partyId,
            labyrinthId: summary.labyrinthId,
            selectedDifficultyTitleId: summary.selectedDifficultyTitleId,
            targetFloorNumber: summary.targetFloorNumber,
            startedAt: summary.startedAt,
            rootSeed: summary.rootSeed,
            memberSnapshots: summary.memberSnapshots,
            memberCharacterIds: summary.memberCharacterIds,
            totalBattleCount: summary.totalBattleCount,
            completedBattleCount: summary.completedBattleCount,
            currentPartyHPs: summary.currentPartyHPs,
            memberExperienceMultipliers: summary.memberExperienceMultipliers,
            progressIntervalMultiplier: summary.progressIntervalMultiplier,
            goldMultiplier: summary.goldMultiplier,
            rareDropMultiplier: summary.rareDropMultiplier,
            partyAverageLuck: summary.partyAverageLuck,
            latestBattleFloorNumber: summary.latestBattleFloorNumber,
            latestBattleNumber: summary.latestBattleNumber,
            latestBattleOutcome: summary.latestBattleOutcome,
            goldBuffer: summary.goldBuffer,
            experienceRewards: experienceRewards,
            dropRewards: dropRewards,
            completion: makeCompletionRecord(
                from: entity,
                experienceRewards: experienceRewards,
                dropRewards: dropRewards
            )
        )
    }

    static func makeCompletionRecord(
        from entity: RunSessionEntity,
        experienceRewards: [ExplorationExperienceReward],
        dropRewards: [ExplorationDropReward]
    ) -> RunCompletionRecord? {
        guard let completedAt = entity.completedAt,
              let reason = decodedOptionalPersistenceOrder(RunCompletionReason.self, from: entity.completionReasonValue) else {
            return nil
        }

        return RunCompletionRecord(
            completedAt: completedAt,
            reason: reason,
            gold: Int(entity.goldBuffer),
            experienceRewards: experienceRewards,
            dropRewards: dropRewards
        )
    }

    static func makeBattleLogIndexEntry(from entity: RunSessionBattleLogEntity) -> ExplorationBattleLog.IndexEntry {
        let defeatedTargetIndices = Set(
            (entity.turns as? Set<RunSessionBattleTurnEntity> ?? [])
                .flatMap { $0.actions as? Set<RunSessionBattleActionEntity> ?? [] }
                .flatMap { $0.results as? Set<RunSessionBattleResultEntity> ?? [] }
                .filter(\.isDefeated)
                .map { Int($0.targetCombatantIndex) }
        )
        let defeatedPartyMemberNames = (entity.combatants as? Set<RunSessionBattleCombatantEntity> ?? [])
            .filter { combatant in
                let side = decodedPersistenceOrder(BattleSide.self, from: combatant.sideValue) ?? .enemy
                return side == .ally && defeatedTargetIndices.contains(Int(combatant.combatantIndex))
            }
            .sorted { lhs, rhs in
                Int(lhs.formationIndex) < Int(rhs.formationIndex)
            }
            .map { $0.name ?? "" }

        return ExplorationBattleLog.IndexEntry(
            partyId: Int(entity.runSession?.partyId ?? 0),
            partyRunId: Int(entity.runSession?.partyRunId ?? 0),
            battleIndex: Int(entity.logIndex),
            floorNumber: Int(entity.floorNumber),
            battleNumber: Int(entity.battleNumber),
            result: decodedPersistenceOrder(BattleOutcome.self, from: entity.resultValue) ?? .draw,
            turnCount: (entity.turns as? Set<RunSessionBattleTurnEntity> ?? []).count,
            defeatedPartyMemberNames: defeatedPartyMemberNames,
            currentPartyHPs: (entity.combatants as? Set<RunSessionBattleCombatantEntity> ?? [])
            .filter { combatant in
                (decodedPersistenceOrder(BattleSide.self, from: combatant.sideValue) ?? .enemy) == .ally
            }
            .sorted { lhs, rhs in
                Int(lhs.formationIndex) < Int(rhs.formationIndex)
            }
            .map { Int($0.remainingHP) }
        )
    }

    static func makeBattleLog(from entity: RunSessionBattleLogEntity) -> ExplorationBattleLog {
        let combatants = (entity.combatants as? Set<RunSessionBattleCombatantEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.combatantIndex) < Int(rhs.combatantIndex)
            }
            .map { combatant in
                let side = decodedPersistenceOrder(BattleSide.self, from: combatant.sideValue) ?? .enemy
                let combatantID = BattleCombatantID(rawValue: Int(combatant.combatantIndex))
                return BattleCombatantSnapshot(
                    id: combatantID,
                    name: combatant.name ?? "",
                    side: side,
                    imageReference: BattleCombatantImageReference(
                        persistenceKind: combatant.imageSourceKindValue,
                        primaryID: combatant.imageSourcePrimaryIDValue,
                        secondaryID: combatant.imageSourceSecondaryIDValue
                    ),
                    level: Int(combatant.level),
                    initialHP: Int(combatant.initialHP),
                    maxHP: Int(combatant.maxHP),
                    remainingHP: Int(combatant.remainingHP),
                    formationIndex: Int(combatant.formationIndex)
                )
            }
        let turns = (entity.turns as? Set<RunSessionBattleTurnEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.turnIndex) < Int(rhs.turnIndex)
            }
            .map(makeBattleTurn)

        return ExplorationBattleLog(
            battleRecord: BattleRecord(
                runId: entity.runSession.map(runIdentifier) ?? RunSessionID(partyId: 0, partyRunId: 0),
                floorNumber: Int(entity.floorNumber),
                battleNumber: Int(entity.battleNumber),
                result: decodedPersistenceOrder(BattleOutcome.self, from: entity.resultValue) ?? .draw,
                turns: turns
            ),
            combatants: combatants
        )
    }

    static func makeBattleTurn(
        from entity: RunSessionBattleTurnEntity
    ) -> BattleTurnRecord {
        let actions = (entity.actions as? Set<RunSessionBattleActionEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.actionIndex) < Int(rhs.actionIndex)
            }
            .map(makeBattleAction)

        return BattleTurnRecord(
            turnNumber: Int(entity.turnNumber),
            actions: actions
        )
    }

    static func makeBattleAction(
        from entity: RunSessionBattleActionEntity
    ) -> BattleActionRecord {
        let targetIDs = (entity.targets as? Set<RunSessionBattleActionTargetEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.actionTargetIndex) < Int(rhs.actionTargetIndex)
            }
            .map { BattleCombatantID(rawValue: Int($0.targetCombatantIndex)) }
        let results = (entity.results as? Set<RunSessionBattleResultEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.actionResultIndex) < Int(rhs.actionResultIndex)
            }
            .map(makeBattleResult)

        return BattleActionRecord(
            actorId: BattleCombatantID(rawValue: Int(entity.actorCombatantIndex)),
            actionKind: decodedPersistenceOrder(BattleLogActionKind.self, from: entity.actionKindValue) ?? .attack,
            actionRef: entity.hasActionRef ? Int(entity.actionRefValue) : nil,
            actionFlags: entity.isCritical ? [.critical] : [],
            targetIds: targetIDs,
            results: results
        )
    }

    static func makeBattleResult(
        from entity: RunSessionBattleResultEntity
    ) -> BattleTargetResult {
        var flags: [BattleTargetResultFlag] = []
        if entity.isDefeated {
            flags.append(.defeated)
        }
        if entity.isRevived {
            flags.append(.revived)
        }
        if entity.isGuarded {
            flags.append(.guarded)
        }

        return BattleTargetResult(
            targetId: BattleCombatantID(rawValue: Int(entity.targetCombatantIndex)),
            resultKind: decodedPersistenceOrder(BattleTargetResultKind.self, from: entity.resultKindValue) ?? .miss,
            value: entity.hasValue ? Int(entity.valueValue) : nil,
            statusId: entity.hasStatusId ? Int(entity.statusIdValue) : nil,
            flags: flags
        )
    }

    static func decodedPersistenceOrder<T: PersistenceOrderRepresentable>(
        _ type: T.Type,
        from persistedValue: Int64
    ) -> T? {
        T(persistenceOrder: Int(persistedValue))
    }

    static func decodedOptionalPersistenceOrder<T: PersistenceOrderRepresentable>(
        _ type: T.Type,
        from persistedValue: Int64
    ) -> T? {
        guard persistedValue >= 0 else {
            return nil
        }

        return decodedPersistenceOrder(type, from: persistedValue)
    }

    static func encodedPersistenceOrder<T: PersistenceOrderRepresentable>(_ value: T) -> Int64 {
        Int64(value.persistenceOrder)
    }

    static func makeExperienceRewards(from entity: RunSessionEntity) -> [ExplorationExperienceReward] {
        let rewards = entity.experienceRewards as? Set<RunSessionExperienceRewardEntity> ?? []
        return rewards.sorted { lhs, rhs in
            Int(lhs.characterId) < Int(rhs.characterId)
        }.map { reward in
            ExplorationExperienceReward(
                characterId: Int(reward.characterId),
                experience: Int(reward.experience)
            )
        }
    }

    static func makeDropRewards(from entity: RunSessionEntity) -> [ExplorationDropReward] {
        let rewards = entity.dropRewards as? Set<RunSessionDropRewardEntity> ?? []
        return rewards.sorted { lhs, rhs in
            if lhs.sourceFloorNumber != rhs.sourceFloorNumber {
                return Int(lhs.sourceFloorNumber) < Int(rhs.sourceFloorNumber)
            }
            if lhs.sourceBattleNumber != rhs.sourceBattleNumber {
                return Int(lhs.sourceBattleNumber) < Int(rhs.sourceBattleNumber)
            }
            return CompositeItemID(entity: lhs).isOrdered(before: CompositeItemID(entity: rhs))
        }.map { reward in
            return ExplorationDropReward(
                itemID: CompositeItemID(entity: reward),
                sourceFloorNumber: Int(reward.sourceFloorNumber),
                sourceBattleNumber: Int(reward.sourceBattleNumber)
            )
        }
    }

    static func applySessionScalars(
        _ session: RunSessionRecord,
        to entity: RunSessionEntity
    ) {
        entity.partyRunId = Int64(session.partyRunId)
        entity.partyId = Int64(session.partyId)
        entity.labyrinthId = Int64(session.labyrinthId)
        entity.selectedDifficultyTitleId = Int64(session.selectedDifficultyTitleId)
        entity.targetFloorNumber = Int64(session.targetFloorNumber)
        entity.startedAt = session.startedAt
        entity.rootSeedSigned = Int64(bitPattern: session.rootSeed)
        entity.totalBattleCount = Int64(session.totalBattleCount)
        entity.completedBattleCount = Int64(session.completedBattleCount)
        entity.goldBuffer = Int64(session.goldBuffer)
        entity.progressIntervalMultiplier = session.progressIntervalMultiplier
        entity.goldMultiplier = session.goldMultiplier
        entity.rareDropMultiplier = session.rareDropMultiplier
        entity.partyAverageLuck = session.partyAverageLuck
        entity.latestBattleFloorNumber = Int64(session.latestBattleFloorNumber ?? -1)
        entity.latestBattleNumber = Int64(session.latestBattleNumber ?? -1)
        entity.latestBattleOutcomeValue = session.latestBattleOutcome.map(encodedPersistenceOrder) ?? -1

        if let completion = session.completion {
            entity.completedAt = completion.completedAt
            entity.completionReasonValue = encodedPersistenceOrder(completion.reason)
        } else {
            entity.completedAt = nil
            entity.completionReasonValue = -1
        }
    }

    static func updateMembers(
        of entity: RunSessionEntity,
        with session: RunSessionRecord
    ) {
        let members = orderedMembers(from: entity)
        for (formationIndex, memberEntity) in members.enumerated() {
            guard session.currentPartyHPs.indices.contains(formationIndex),
                  session.memberExperienceMultipliers.indices.contains(formationIndex) else {
                continue
            }

            memberEntity.characterId = Int64(session.memberCharacterIds[formationIndex])
            memberEntity.currentHP = Int64(session.currentPartyHPs[formationIndex])
            memberEntity.experienceMultiplier = session.memberExperienceMultipliers[formationIndex]
        }
    }

    static func appendBattleLogs(
        _ battleLogs: [ExplorationBattleLog],
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) {
        guard !battleLogs.isEmpty else {
            return
        }

        // Log, turn, action, and result indices are persisted explicitly because Core Data set
        // ordering is undefined and the renderer must reconstruct the original battle timeline.
        for (logIndex, battleLog) in battleLogs.enumerated() {
            guard let logEntity = NSEntityDescription.insertNewObject(
                forEntityName: "RunSessionBattleLogEntity",
                into: context
            ) as? RunSessionBattleLogEntity else {
                fatalError("RunSessionBattleLogEntity の生成に失敗しました。")
            }

            logEntity.runSession = entity
            logEntity.logIndex = Int64(logIndex)
            logEntity.floorNumber = Int64(battleLog.battleRecord.floorNumber)
            logEntity.battleNumber = Int64(battleLog.battleRecord.battleNumber)
            logEntity.resultValue = encodedPersistenceOrder(battleLog.battleRecord.result)
            let combatantIndicesByID = Dictionary(
                uniqueKeysWithValues: battleLog.combatants.enumerated().map { ($0.element.id, $0.offset) }
            )

            for (combatantIndex, combatant) in battleLog.combatants.enumerated() {
                guard let combatantEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "RunSessionBattleCombatantEntity",
                    into: context
                ) as? RunSessionBattleCombatantEntity else {
                    fatalError("RunSessionBattleCombatantEntity の生成に失敗しました。")
                }

                combatantEntity.battleLog = logEntity
                combatantEntity.combatantIndex = Int64(combatantIndex)
                combatantEntity.name = combatant.name
                combatantEntity.sideValue = encodedPersistenceOrder(combatant.side)
                let imageReference = combatant.imageReference
                combatantEntity.imageSourceKindValue = imageReference?.persistenceKind ?? 0
                combatantEntity.imageSourcePrimaryIDValue = imageReference?.persistencePrimaryID ?? 0
                combatantEntity.imageSourceSecondaryIDValue = imageReference?.persistenceSecondaryID ?? 0
                combatantEntity.level = Int64(combatant.level)
                combatantEntity.initialHP = Int64(combatant.initialHP)
                combatantEntity.maxHP = Int64(combatant.maxHP)
                combatantEntity.remainingHP = Int64(combatant.remainingHP)
                combatantEntity.formationIndex = Int64(combatant.formationIndex)
            }

            for (turnIndex, turn) in battleLog.battleRecord.turns.enumerated() {
                guard let turnEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "RunSessionBattleTurnEntity",
                    into: context
                ) as? RunSessionBattleTurnEntity else {
                    fatalError("RunSessionBattleTurnEntity の生成に失敗しました。")
                }

                turnEntity.battleLog = logEntity
                turnEntity.turnIndex = Int64(turnIndex)
                turnEntity.turnNumber = Int64(turn.turnNumber)

                for (actionIndex, action) in turn.actions.enumerated() {
                    guard let actionEntity = NSEntityDescription.insertNewObject(
                        forEntityName: "RunSessionBattleActionEntity",
                        into: context
                    ) as? RunSessionBattleActionEntity else {
                        fatalError("RunSessionBattleActionEntity の生成に失敗しました。")
                    }

                    actionEntity.turn = turnEntity
                    actionEntity.actionIndex = Int64(actionIndex)
                    guard let actorCombatantIndex = combatantIndicesByID[action.actorId] else {
                        fatalError("行動者の戦闘参加者が見つかりません。 id=\(action.actorId.rawValue)")
                    }
                    actionEntity.actorCombatantIndex = Int64(actorCombatantIndex)
                    actionEntity.actionKindValue = encodedPersistenceOrder(action.actionKind)
                    actionEntity.hasActionRef = action.actionRef != nil
                    actionEntity.actionRefValue = Int64(action.actionRef ?? 0)
                    actionEntity.isCritical = action.actionFlags.contains(.critical)

                    for (targetIndex, targetID) in action.targetIds.enumerated() {
                        guard let targetCombatantIndex = combatantIndicesByID[targetID] else {
                            fatalError("行動対象の戦闘参加者が見つかりません。 id=\(targetID.rawValue)")
                        }
                        guard let targetEntity = NSEntityDescription.insertNewObject(
                            forEntityName: "RunSessionBattleActionTargetEntity",
                            into: context
                        ) as? RunSessionBattleActionTargetEntity else {
                            fatalError("RunSessionBattleActionTargetEntity の生成に失敗しました。")
                        }

                        targetEntity.action = actionEntity
                        targetEntity.actionTargetIndex = Int64(targetIndex)
                        targetEntity.targetCombatantIndex = Int64(targetCombatantIndex)
                    }

                    for (resultIndex, result) in action.results.enumerated() {
                        guard let resultEntity = NSEntityDescription.insertNewObject(
                            forEntityName: "RunSessionBattleResultEntity",
                            into: context
                        ) as? RunSessionBattleResultEntity else {
                            fatalError("RunSessionBattleResultEntity の生成に失敗しました。")
                        }

                        resultEntity.action = actionEntity
                        resultEntity.actionResultIndex = Int64(resultIndex)
                        guard let targetCombatantIndex = combatantIndicesByID[result.targetId] else {
                            fatalError("対象の戦闘参加者が見つかりません。 id=\(result.targetId.rawValue)")
                        }
                        resultEntity.targetCombatantIndex = Int64(targetCombatantIndex)
                        resultEntity.resultKindValue = encodedPersistenceOrder(result.resultKind)
                        resultEntity.hasValue = result.value != nil
                        resultEntity.valueValue = Int64(result.value ?? 0)
                        resultEntity.hasStatusId = result.statusId != nil
                        resultEntity.statusIdValue = Int64(result.statusId ?? 0)
                        resultEntity.isDefeated = result.flags.contains(.defeated)
                        resultEntity.isRevived = result.flags.contains(.revived)
                        resultEntity.isGuarded = result.flags.contains(.guarded)
                    }
                }
            }
        }
    }

    static func upsertExperienceRewards(
        _ rewards: [ExplorationExperienceReward],
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) {
        let existingRewards = entity.experienceRewards as? Set<RunSessionExperienceRewardEntity> ?? []
        var rewardsByCharacterId = Dictionary(uniqueKeysWithValues: existingRewards.map {
            (Int($0.characterId), $0)
        })

        for reward in rewards {
            let rewardEntity: RunSessionExperienceRewardEntity
            if let existingEntity = rewardsByCharacterId[reward.characterId] {
                rewardEntity = existingEntity
            } else {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "RunSessionExperienceRewardEntity",
                    into: context
                ) as? RunSessionExperienceRewardEntity else {
                    fatalError("RunSessionExperienceRewardEntity の生成に失敗しました。")
                }
                insertedEntity.runSession = entity
                insertedEntity.characterId = Int64(reward.characterId)
                rewardsByCharacterId[reward.characterId] = insertedEntity
                rewardEntity = insertedEntity
            }

            rewardEntity.experience = Int64(reward.experience)
        }
    }

    static func appendDropRewards(
        _ rewards: [ExplorationDropReward],
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) {
        guard !rewards.isEmpty else {
            return
        }

        for reward in rewards {
            guard let rewardEntity = NSEntityDescription.insertNewObject(
                forEntityName: "RunSessionDropRewardEntity",
                into: context
            ) as? RunSessionDropRewardEntity else {
                fatalError("RunSessionDropRewardEntity の生成に失敗しました。")
            }

            rewardEntity.runSession = entity
            reward.itemID.apply(to: rewardEntity)
            rewardEntity.sourceFloorNumber = Int64(reward.sourceFloorNumber)
            rewardEntity.sourceBattleNumber = Int64(reward.sourceBattleNumber)
        }
    }

    static func applyMemberSnapshot(
        _ character: CharacterRecord,
        to entity: RunSessionMemberEntity
    ) {
        // Run members keep their own frozen equipment rows so resumed runs do not depend on live
        // roster mutations.
        entity.name = character.name
        entity.raceId = Int64(character.raceId)
        entity.previousJobId = Int64(character.previousJobId)
        entity.currentJobId = Int64(character.currentJobId)
        entity.aptitudeId = Int64(character.aptitudeId)
        entity.portraitVariant = Int64(character.portraitGender.rawValue)
        entity.experience = Int64(character.experience)
        entity.level = Int64(character.level)
        setEquippedItemStacks(character.equippedItemStacks, on: entity, in: entity.managedObjectContext)
        entity.breathRate = Int64(character.autoBattleSettings.rates.breath)
        entity.attackRate = Int64(character.autoBattleSettings.rates.attack)
        entity.recoverySpellRate = Int64(character.autoBattleSettings.rates.recoverySpell)
        entity.attackSpellRate = Int64(character.autoBattleSettings.rates.attackSpell)
        let persistedPriority = CharacterAutoBattleSettings.persistedPriorityValues(
            for: character.autoBattleSettings.priority
        )
        entity.actionPriorityPrimaryValue = persistedPriority[0]
        entity.actionPrioritySecondaryValue = persistedPriority[1]
        entity.actionPriorityTertiaryValue = persistedPriority[2]
        entity.actionPriorityQuaternaryValue = persistedPriority[3]
    }

    static func makeCharacterRecord(from entity: RunSessionMemberEntity) -> CharacterRecord {
        let priority = CharacterAutoBattleSettings.decodedPriority(
            from: [
                entity.actionPriorityPrimaryValue,
                entity.actionPrioritySecondaryValue,
                entity.actionPriorityTertiaryValue,
                entity.actionPriorityQuaternaryValue
            ]
        )

        return CharacterRecord(
            characterId: Int(entity.characterId),
            name: entity.name ?? "",
            raceId: Int(entity.raceId),
            previousJobId: Int(entity.previousJobId),
            currentJobId: Int(entity.currentJobId),
            aptitudeId: Int(entity.aptitudeId),
            portraitGender: PortraitGender(rawValue: Int(entity.portraitVariant)) ?? .unisex,
            experience: Int(entity.experience),
            level: Int(entity.level),
            currentHP: Int(entity.currentHP),
            equippedItemStacks: equippedItemStacks(from: entity),
            autoBattleSettings: CharacterAutoBattleSettings(
                rates: CharacterActionRates(
                    breath: Int(entity.breathRate),
                    attack: Int(entity.attackRate),
                    recoverySpell: Int(entity.recoverySpellRate),
                    attackSpell: Int(entity.attackSpellRate)
                ),
                priority: priority
            )
        )
    }

    static func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
        let priority = CharacterAutoBattleSettings.decodedPriority(
            from: [
                entity.actionPriorityPrimaryValue,
                entity.actionPrioritySecondaryValue,
                entity.actionPriorityTertiaryValue,
                entity.actionPriorityQuaternaryValue
            ]
        )

        return CharacterRecord(
            characterId: Int(entity.characterId),
            name: entity.name ?? "",
            raceId: Int(entity.raceId),
            previousJobId: Int(entity.previousJobId),
            currentJobId: Int(entity.currentJobId),
            aptitudeId: Int(entity.aptitudeId),
            portraitGender: PortraitGender(rawValue: Int(entity.portraitVariant)) ?? .unisex,
            experience: Int(entity.experience),
            level: Int(entity.level),
            currentHP: Int(entity.currentHP),
            equippedItemStacks: equippedItemStacks(from: entity),
            autoBattleSettings: CharacterAutoBattleSettings(
                rates: CharacterActionRates(
                    breath: Int(entity.breathRate),
                    attack: Int(entity.attackRate),
                    recoverySpell: Int(entity.recoverySpellRate),
                    attackSpell: Int(entity.attackSpellRate)
                ),
                priority: priority
            )
        )
    }

    static func equippedItemStacks(from entity: CharacterEntity) -> [CompositeItemStack] {
        let equippedItems = entity.equippedItems as? Set<CharacterEquippedItemEntity> ?? []
        return equippedItems.sorted { Int($0.stackIndex) < Int($1.stackIndex) }
            .compactMap(makeEquippedItemStack)
            .normalizedCompositeItemStacks()
    }

    static func equippedItemStacks(from entity: RunSessionMemberEntity) -> [CompositeItemStack] {
        let equippedItems = entity.equippedItems as? Set<RunSessionMemberEquippedItemEntity> ?? []
        return equippedItems.sorted { Int($0.stackIndex) < Int($1.stackIndex) }
            .compactMap(makeEquippedItemStack)
            .normalizedCompositeItemStacks()
    }

    static func autoSellItemIDs(from entity: PlayerStateEntity) -> Set<CompositeItemID> {
        let autoSellEntities = entity.autoSellItems as? Set<PlayerStateAutoSellItemEntity> ?? []
        return Set(autoSellEntities.map(CompositeItemID.init(entity:)))
    }

    static func makeEquippedItemStack(from entity: CharacterEquippedItemEntity) -> CompositeItemStack? {
        guard entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(
            itemID: CompositeItemID(entity: entity),
            count: Int(entity.count)
        )
    }

    static func makeEquippedItemStack(from entity: RunSessionMemberEquippedItemEntity) -> CompositeItemStack? {
        guard entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(
            itemID: CompositeItemID(entity: entity),
            count: Int(entity.count)
        )
    }

    static func setEquippedItemStacks(
        _ equippedItemStacks: [CompositeItemStack],
        on entity: RunSessionMemberEntity,
        in context: NSManagedObjectContext?
    ) {
        guard let context else {
            fatalError("RunSessionMemberEntity の context が見つかりません。")
        }

        let existingItems = entity.equippedItems as? Set<RunSessionMemberEquippedItemEntity> ?? []
        for existingItem in existingItems {
            context.delete(existingItem)
        }

        for (stackIndex, stack) in equippedItemStacks.normalizedCompositeItemStacks().enumerated() {
            guard let itemEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "RunSessionMemberEquippedItemEntity",
                    into: context
                  ) as? RunSessionMemberEquippedItemEntity else {
                fatalError("RunSessionMemberEquippedItemEntity の生成に失敗しました。")
            }

            itemEntity.runSessionMember = entity
            itemEntity.stackIndex = Int64(stackIndex)
            itemEntity.count = Int64(stack.count)
            stack.itemID.apply(to: itemEntity)
        }
    }

    static func restoreCurrentHPToMax(
        of entity: CharacterEntity,
        masterData: MasterData
    ) throws {
        let character = makeCharacterRecord(from: entity)
        guard let status = CharacterDerivedStatsCalculator.status(
            for: character,
            masterData: masterData
        ) else {
            throw ExplorationError.invalidRunMember(characterId: Int(entity.characterId))
        }

        entity.currentHP = Int64(status.maxHP)
    }

    static func runIdentifier(for entity: RunSessionEntity) -> RunSessionID {
        RunSessionID(
            partyId: Int(entity.partyId),
            partyRunId: Int(entity.partyRunId)
        )
    }
}
