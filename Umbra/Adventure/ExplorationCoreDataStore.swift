// Persists exploration runs on background Core Data contexts and builds value snapshots for upper layers.

import CoreData
import Foundation

actor ExplorationCoreDataStore {
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
                appliedInventoryCounts: [:]
            )
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
        partyId: Int
    ) async throws -> (nextPartyRunId: Int, partyMembers: [CharacterRecord]) {
        try await perform { context in
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

            return (
                nextPartyRunId: try ExplorationCoreDataBridge.nextPartyRunId(
                    partyId: partyId,
                    in: context
                ),
                partyMembers: partyMembers
            )
        }
    }

    func insertRun(_ session: RunSessionRecord) async throws {
        try await perform { context in
            guard try !ExplorationCoreDataBridge.hasActiveRun(
                partyId: session.partyId,
                in: context
            )
            else {
                throw ExplorationError.activeRunAlreadyExists(partyId: session.partyId)
            }

            try ExplorationCoreDataBridge.insertRunEntity(
                for: session,
                in: context
            )
        }
    }

    func loadProgressContexts() async throws -> [(session: RunSessionRecord, livePartyMembers: [CharacterRecord])] {
        try await perform { context in
            let runEntities = try ExplorationCoreDataBridge.fetchRunEntities(in: context)
            return try runEntities.map { runEntity in
                let session: RunSessionRecord
                if runEntity.completedAt == nil {
                    session = ExplorationCoreDataBridge.makeRunDetailRecord(from: runEntity)
                } else {
                    session = ExplorationCoreDataBridge.makeRunSummaryRecord(from: runEntity)
                }
                let livePartyMembers: [CharacterRecord]
                if session.completion == nil {
                    livePartyMembers = try ExplorationCoreDataBridge.fetchRunPartyMembers(
                        for: session.memberCharacterIds,
                        in: context
                    )
                } else {
                    livePartyMembers = []
                }

                return (
                    session: session,
                    livePartyMembers: livePartyMembers
                )
            }
        }
    }

    func commitProgressUpdates(
        _ updates: [(currentSession: RunSessionRecord, resolvedSession: RunSessionRecord)],
        masterData: MasterData
    ) async throws -> (didApplyRewards: Bool, appliedInventoryCounts: [CompositeItemID: Int]) {
        try await perform { context in
            guard !updates.isEmpty else {
                return (
                    didApplyRewards: false,
                    appliedInventoryCounts: [:]
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

            for update in updates {
                let currentSession = update.currentSession
                let resolvedSession = update.resolvedSession
                let identifier = resolvedSession.id

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

                let inventoryCounts = try ExplorationCoreDataBridge.applyCompletionRewards(
                    completion: completion,
                    currentPartyHPs: resolvedSession.currentPartyHPs,
                    memberCharacterIds: resolvedSession.memberCharacterIds,
                    in: context,
                    masterData: masterData
                )
                entity.rewardsApplied = true
                didApplyRewards = true
                for (itemID, count) in inventoryCounts {
                    appliedInventoryCounts[itemID, default: 0] += count
                }
            }

            return (
                didApplyRewards: didApplyRewards,
                appliedInventoryCounts: appliedInventoryCounts
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

    static func fetchRunPartyMembers(
        for characterIds: [Int],
        in context: NSManagedObjectContext
    ) throws -> [CharacterRecord] {
        let entities = try fetchCharacterEntities(characterIds: characterIds, in: context)
        let charactersById = Dictionary(uniqueKeysWithValues: entities.map { (Int($0.characterId), $0) })

        return try characterIds.map { characterId in
            guard let entity = charactersById[characterId] else {
                throw ExplorationError.invalidRunMember(characterId: characterId)
            }
            return makeCharacterRecord(from: entity)
        }
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
        entity.nextCharacterId = Int64(PlayerState.initial.nextCharacterId)
        entity.autoReviveDefeatedCharacters = PlayerState.initial.autoReviveDefeatedCharacters
        return entity
    }

    static func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        (entity.memberCharacterIdsRawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
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
        }
    }

    static func applyResolvedSession(
        _ session: RunSessionRecord,
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) throws {
        applySessionScalars(session, to: entity)
        updateMembers(of: entity, with: session)
        appendBattleLogs(
            Array(session.battleLogs.dropFirst(existingBattleLogCount(of: entity))),
            to: entity,
            in: context
        )
        upsertExperienceRewards(session.experienceRewards, to: entity, in: context)
        appendDropRewards(
            Array(session.dropRewards.dropFirst(existingDropRewardCount(of: entity))),
            to: entity,
            in: context
        )
    }

    static func applyCompletionRewards(
        completion: RunCompletionRecord,
        currentPartyHPs: [Int],
        memberCharacterIds: [Int],
        in context: NSManagedObjectContext,
        masterData: MasterData
    ) throws -> [CompositeItemID: Int] {
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
            if playerState.autoReviveDefeatedCharacters && currentHP == 0 {
                try restoreCurrentHPToMax(
                    of: characterEntity,
                    masterData: masterData
                )
            } else {
                characterEntity.currentHP = Int64(max(currentHP, 0))
            }
        }

        let inventoryCounts = Dictionary(
            completion.dropRewards.map { ($0.itemID, 1) },
            uniquingKeysWith: +
        )
        applyInventoryCounts(
            inventoryCounts,
            in: context
        )

        return inventoryCounts
    }

    static func applyInventoryCounts(
        _ itemCounts: [CompositeItemID: Int],
        in context: NSManagedObjectContext
    ) {
        guard !itemCounts.isEmpty else {
            return
        }

        let keys = itemCounts.keys.map(\.rawValue)
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.predicate = NSPredicate(format: "stackKeyRawValue IN %@", keys)
        let existingEntities = (try? context.fetch(request)) ?? []
        var entitiesByKey: [String: InventoryItemEntity] = Dictionary(uniqueKeysWithValues: existingEntities.compactMap { entity in
            guard let key = entity.stackKeyRawValue else {
                return nil
            }
            return (key, entity)
        })

        for (itemID, count) in itemCounts where count > 0 {
            let entity: InventoryItemEntity
            if let existingEntity = entitiesByKey[itemID.rawValue] {
                entity = existingEntity
            } else {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                insertedEntity.stackKeyRawValue = itemID.rawValue
                insertedEntity.count = 0
                entitiesByKey[itemID.rawValue] = insertedEntity
                entity = insertedEntity
            }

            entity.count += Int64(count)
        }
    }

    static func makeRunSummaryRecord(from entity: RunSessionEntity) -> RunSessionRecord {
        let members = orderedMembers(from: entity)
        let memberCharacterIds = members.map { Int($0.characterId) }
        let currentPartyHPs = members.map { Int($0.currentHP) }
        let memberExperienceMultipliers = members.map(\.experienceMultiplier)

        return RunSessionRecord(
            partyRunId: Int(entity.partyRunId),
            partyId: Int(entity.partyId),
            labyrinthId: Int(entity.labyrinthId),
            targetFloorNumber: Int(entity.targetFloorNumber),
            startedAt: entity.startedAt ?? .distantPast,
            rootSeed: UInt64(bitPattern: entity.rootSeedSigned),
            maximumLoopCount: Int(entity.maximumLoopCount),
            memberCharacterIds: memberCharacterIds,
            completedBattleCount: Int(entity.completedBattleCount),
            currentPartyHPs: currentPartyHPs,
            memberExperienceMultipliers: memberExperienceMultipliers,
            goldMultiplier: entity.goldMultiplier,
            rareDropMultiplier: entity.rareDropMultiplier,
            titleDropMultiplier: entity.titleDropMultiplier,
            partyAverageLuck: entity.partyAverageLuck,
            latestBattleFloorNumber: entity.latestBattleFloorNumber > 0 ? Int(entity.latestBattleFloorNumber) : nil,
            latestBattleNumber: entity.latestBattleNumber > 0 ? Int(entity.latestBattleNumber) : nil,
            latestBattleOutcome: entity.latestBattleOutcomeRawValue.flatMap(BattleOutcome.init(rawValue:)),
            battleLogs: [],
            goldBuffer: Int(entity.goldBuffer),
            experienceRewards: [],
            dropRewards: [],
            completion: makeCompletionRecord(
                from: entity,
                experienceRewards: [],
                dropRewards: []
            )
        )
    }

    static func makeRunDetailRecord(from entity: RunSessionEntity) -> RunSessionRecord {
        let experienceRewards = makeExperienceRewards(from: entity)
        let dropRewards = makeDropRewards(from: entity)
        var summary = makeRunSummaryRecord(from: entity)
        summary = RunSessionRecord(
            partyRunId: summary.partyRunId,
            partyId: summary.partyId,
            labyrinthId: summary.labyrinthId,
            targetFloorNumber: summary.targetFloorNumber,
            startedAt: summary.startedAt,
            rootSeed: summary.rootSeed,
            maximumLoopCount: summary.maximumLoopCount,
            memberCharacterIds: summary.memberCharacterIds,
            completedBattleCount: summary.completedBattleCount,
            currentPartyHPs: summary.currentPartyHPs,
            memberExperienceMultipliers: summary.memberExperienceMultipliers,
            goldMultiplier: summary.goldMultiplier,
            rareDropMultiplier: summary.rareDropMultiplier,
            titleDropMultiplier: summary.titleDropMultiplier,
            partyAverageLuck: summary.partyAverageLuck,
            latestBattleFloorNumber: summary.latestBattleFloorNumber,
            latestBattleNumber: summary.latestBattleNumber,
            latestBattleOutcome: summary.latestBattleOutcome,
            battleLogs: makeBattleLogs(from: entity),
            goldBuffer: summary.goldBuffer,
            experienceRewards: experienceRewards,
            dropRewards: dropRewards,
            completion: makeCompletionRecord(
                from: entity,
                experienceRewards: experienceRewards,
                dropRewards: dropRewards
            )
        )
        return summary
    }

    static func makeCompletionRecord(
        from entity: RunSessionEntity,
        experienceRewards: [ExplorationExperienceReward],
        dropRewards: [ExplorationDropReward]
    ) -> RunCompletionRecord? {
        guard let completedAt = entity.completedAt,
              let rawValue = entity.completionReasonRawValue,
              let reason = RunCompletionReason(rawValue: rawValue) else {
            return nil
        }

        return RunCompletionRecord(
            completedAt: completedAt,
            reason: reason,
            completedLoopCount: Int(entity.completedLoopCount),
            gold: Int(entity.goldBuffer),
            experienceRewards: experienceRewards,
            dropRewards: dropRewards
        )
    }

    static func makeBattleLogs(from entity: RunSessionEntity) -> [ExplorationBattleLog] {
        let logs = entity.battleLogs as? Set<RunSessionBattleLogEntity> ?? []
        return logs.sorted { lhs, rhs in
            Int(lhs.logIndex) < Int(rhs.logIndex)
        }.map(makeBattleLog)
    }

    static func makeBattleLog(from entity: RunSessionBattleLogEntity) -> ExplorationBattleLog {
        let combatants = (entity.combatants as? Set<RunSessionBattleCombatantEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.combatantIndex) < Int(rhs.combatantIndex)
            }
            .map { combatant in
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: combatant.combatantIDRawValue ?? ""),
                    name: combatant.name ?? "",
                    side: BattleSide(rawValue: combatant.sideRawValue ?? "") ?? .enemy,
                    level: Int(combatant.level),
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
                runId: entity.runSession.map(runIdentifier) ?? "",
                floorNumber: Int(entity.floorNumber),
                battleNumber: Int(entity.battleNumber),
                result: BattleOutcome(rawValue: entity.resultRawValue ?? "") ?? .draw,
                turns: turns
            ),
            combatants: combatants
        )
    }

    static func makeBattleTurn(from entity: RunSessionBattleTurnEntity) -> BattleTurnRecord {
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

    static func makeBattleAction(from entity: RunSessionBattleActionEntity) -> BattleActionRecord {
        let results = (entity.results as? Set<RunSessionBattleResultEntity> ?? [])
            .sorted { lhs, rhs in
                Int(lhs.actionResultIndex) < Int(rhs.actionResultIndex)
            }
            .map(makeBattleResult)

        return BattleActionRecord(
            actorId: BattleCombatantID(rawValue: entity.actorCombatantIDRawValue ?? ""),
            actionKind: BattleLogActionKind(rawValue: entity.actionKindRawValue ?? "") ?? .attack,
            actionRef: entity.hasActionRef ? Int(entity.actionRefValue) : nil,
            actionFlags: entity.isCritical ? [.critical] : [],
            targetIds: orderedTargetIds(from: results),
            results: results
        )
    }

    static func makeBattleResult(from entity: RunSessionBattleResultEntity) -> BattleTargetResult {
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
            targetId: BattleCombatantID(rawValue: entity.targetCombatantIDRawValue ?? ""),
            resultKind: BattleTargetResultKind(rawValue: entity.resultKindRawValue ?? "") ?? .miss,
            value: entity.hasValue ? Int(entity.valueValue) : nil,
            statusId: entity.hasStatusId ? Int(entity.statusIdValue) : nil,
            flags: flags
        )
    }

    static func orderedTargetIds(from results: [BattleTargetResult]) -> [BattleCombatantID] {
        var seenTargetIds = Set<BattleCombatantID>()
        var targetIds: [BattleCombatantID] = []

        for result in results where seenTargetIds.insert(result.targetId).inserted {
            targetIds.append(result.targetId)
        }

        return targetIds
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
            return (lhs.itemIDRawValue ?? "") < (rhs.itemIDRawValue ?? "")
        }.compactMap { reward in
            guard let rawValue = reward.itemIDRawValue,
                  let itemID = CompositeItemID(rawValue: rawValue) else {
                return nil
            }

            return ExplorationDropReward(
                itemID: itemID,
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
        entity.targetFloorNumber = Int64(session.targetFloorNumber)
        entity.startedAt = session.startedAt
        entity.rootSeedSigned = Int64(bitPattern: session.rootSeed)
        entity.maximumLoopCount = Int64(session.maximumLoopCount)
        entity.completedBattleCount = Int64(session.completedBattleCount)
        entity.goldBuffer = Int64(session.goldBuffer)
        entity.goldMultiplier = session.goldMultiplier
        entity.rareDropMultiplier = session.rareDropMultiplier
        entity.titleDropMultiplier = session.titleDropMultiplier
        entity.partyAverageLuck = session.partyAverageLuck
        entity.latestBattleFloorNumber = Int64(session.latestBattleFloorNumber ?? -1)
        entity.latestBattleNumber = Int64(session.latestBattleNumber ?? -1)
        entity.latestBattleOutcomeRawValue = session.latestBattleOutcome?.rawValue

        if let completion = session.completion {
            entity.completedAt = completion.completedAt
            entity.completionReasonRawValue = completion.reason.rawValue
            entity.completedLoopCount = Int64(completion.completedLoopCount)
        } else {
            entity.completedAt = nil
            entity.completionReasonRawValue = nil
            entity.completedLoopCount = 0
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

    static func existingBattleLogCount(of entity: RunSessionEntity) -> Int {
        (entity.battleLogs as? Set<RunSessionBattleLogEntity>)?.count ?? 0
    }

    static func existingDropRewardCount(of entity: RunSessionEntity) -> Int {
        (entity.dropRewards as? Set<RunSessionDropRewardEntity>)?.count ?? 0
    }

    static func appendBattleLogs(
        _ battleLogs: [ExplorationBattleLog],
        to entity: RunSessionEntity,
        in context: NSManagedObjectContext
    ) {
        guard !battleLogs.isEmpty else {
            return
        }

        let startIndex = existingBattleLogCount(of: entity)
        for (offset, battleLog) in battleLogs.enumerated() {
            guard let logEntity = NSEntityDescription.insertNewObject(
                forEntityName: "RunSessionBattleLogEntity",
                into: context
            ) as? RunSessionBattleLogEntity else {
                fatalError("RunSessionBattleLogEntity の生成に失敗しました。")
            }

            logEntity.runSession = entity
            logEntity.logIndex = Int64(startIndex + offset)
            logEntity.floorNumber = Int64(battleLog.battleRecord.floorNumber)
            logEntity.battleNumber = Int64(battleLog.battleRecord.battleNumber)
            logEntity.resultRawValue = battleLog.battleRecord.result.rawValue

            for (combatantIndex, combatant) in battleLog.combatants.enumerated() {
                guard let combatantEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "RunSessionBattleCombatantEntity",
                    into: context
                ) as? RunSessionBattleCombatantEntity else {
                    fatalError("RunSessionBattleCombatantEntity の生成に失敗しました。")
                }

                combatantEntity.battleLog = logEntity
                combatantEntity.combatantIndex = Int64(combatantIndex)
                combatantEntity.combatantIDRawValue = combatant.id.rawValue
                combatantEntity.name = combatant.name
                combatantEntity.sideRawValue = combatant.side.rawValue
                combatantEntity.level = Int64(combatant.level)
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
                    actionEntity.actorCombatantIDRawValue = action.actorId.rawValue
                    actionEntity.actionKindRawValue = action.actionKind.rawValue
                    actionEntity.hasActionRef = action.actionRef != nil
                    actionEntity.actionRefValue = Int64(action.actionRef ?? 0)
                    actionEntity.isCritical = action.actionFlags.contains(.critical)

                    for (resultIndex, result) in action.results.enumerated() {
                        guard let resultEntity = NSEntityDescription.insertNewObject(
                            forEntityName: "RunSessionBattleResultEntity",
                            into: context
                        ) as? RunSessionBattleResultEntity else {
                            fatalError("RunSessionBattleResultEntity の生成に失敗しました。")
                        }

                        resultEntity.action = actionEntity
                        resultEntity.actionResultIndex = Int64(resultIndex)
                        resultEntity.targetCombatantIDRawValue = result.targetId.rawValue
                        resultEntity.resultKindRawValue = result.resultKind.rawValue
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
            rewardEntity.itemIDRawValue = reward.itemID.rawValue
            rewardEntity.sourceFloorNumber = Int64(reward.sourceFloorNumber)
            rewardEntity.sourceBattleNumber = Int64(reward.sourceBattleNumber)
        }
    }

    static func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
        let parsedPriority = (entity.actionPriorityRawValue ?? "")
            .split(separator: ",")
            .compactMap { BattleActionKind(rawValue: String($0)) }
        let priority = parsedPriority.count == CharacterAutoBattleSettings.default.priority.count
            ? parsedPriority
            : CharacterAutoBattleSettings.default.priority

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
        (entity.equippedItemStacksRawValue ?? "")
            .split(separator: "|")
            .compactMap { component in
                let parts = component.split(separator: "#")
                guard parts.count == 2,
                      let itemID = CompositeItemID(rawValue: String(parts[0])),
                      let count = Int(parts[1]),
                      count > 0 else {
                    return nil
                }
                return CompositeItemStack(itemID: itemID, count: count)
            }
            .normalizedCompositeItemStacks()
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

    static func runIdentifier(for entity: RunSessionEntity) -> String {
        "\(Int(entity.partyId)):\(Int(entity.partyRunId))"
    }
}
