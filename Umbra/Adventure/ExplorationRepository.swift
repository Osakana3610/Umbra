// Persists exploration sessions and applies deterministic progression results back into player state.

import CoreData
import Foundation

@MainActor
final class ExplorationRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadSnapshot() throws -> ExplorationRunSnapshot {
        let context = container.viewContext
        let runs = try ExplorationPersistenceBridge.fetchRunEntities(in: context)
            .map(ExplorationPersistenceBridge.makeRunSessionRecord)
            .sorted(by: ExplorationPersistenceBridge.isOrderedBefore)
        return ExplorationRunSnapshot(runs: runs, didApplyRewards: false)
    }

    func startRun(
        partyId: Int,
        labyrinthId: Int,
        startedAt: Date,
        maximumLoopCount: Int,
        masterData: MasterData
    ) throws -> ExplorationRunSnapshot {
        let context = container.viewContext
        guard masterData.labyrinths.contains(where: { $0.id == labyrinthId }) else {
            throw ExplorationRepositoryError.invalidLabyrinth(labyrinthId: labyrinthId)
        }
        guard maximumLoopCount > 0 else {
            throw ExplorationRepositoryError.invalidLabyrinth(labyrinthId: labyrinthId)
        }
        guard try ExplorationPersistenceBridge.fetchActiveRunEntity(
            partyId: partyId,
            in: context
        ) == nil else {
            throw ExplorationRepositoryError.activeRunAlreadyExists(partyId: partyId)
        }

        let party = try ExplorationPersistenceBridge.fetchPartyEntity(partyId: partyId, in: context)
        let memberCharacterIds = ExplorationPersistenceBridge.memberCharacterIds(from: party)
        guard !memberCharacterIds.isEmpty else {
            throw ExplorationRepositoryError.partyHasNoMembers(partyId: partyId)
        }

        let partyMembers = try memberCharacterIds.map { characterId in
            ExplorationPersistenceBridge.makeCharacterRecord(
                from: try ExplorationPersistenceBridge.fetchCharacterEntity(
                    characterId: characterId,
                    in: context
                )
            )
        }
        guard partyMembers.allSatisfy({ $0.currentHP > 0 }) else {
            throw ExplorationRepositoryError.partyHasDefeatedMember(partyId: partyId)
        }

        let currentPartyHPs = try partyMembers.map { member in
            guard let status = CharacterDerivedStatsCalculator.status(for: member, masterData: masterData) else {
                throw ExplorationRepositoryError.invalidRunMember(characterId: member.characterId)
            }
            return status.maxHP
        }
        let nextRunId = try ExplorationPersistenceBridge.nextRunId(
            for: partyId,
            in: context
        )
        let targetFloorNumber = masterData.labyrinths.first(where: { $0.id == labyrinthId })?
            .floors
            .map(\.floorNumber)
            .max() ?? 0

        guard let entity = NSEntityDescription.insertNewObject(
            forEntityName: "RunSessionEntity",
            into: context
        ) as? RunSessionEntity else {
            fatalError("RunSessionEntity の生成に失敗しました。")
        }

        ExplorationPersistenceBridge.apply(
            RunSessionRecord(
                partyRunId: nextRunId,
                partyId: partyId,
                labyrinthId: labyrinthId,
                targetFloorNumber: targetFloorNumber,
                startedAt: startedAt,
                rootSeed: ExplorationPersistenceBridge.rootSeed(
                    partyId: partyId,
                    partyRunId: nextRunId,
                    startedAt: startedAt
                ),
                maximumLoopCount: maximumLoopCount,
                memberCharacterIds: memberCharacterIds,
                completedBattleCount: 0,
                currentPartyHPs: currentPartyHPs,
                battleLogs: [],
                goldBuffer: 0,
                experienceRewards: [],
                dropRewards: [],
                completion: nil
            ),
            rewardsApplied: false,
            to: entity
        )
        try context.save()
        return try loadSnapshot()
    }

    func refreshRuns(
        at currentDate: Date,
        masterData: MasterData
    ) throws -> ExplorationRunSnapshot {
        let context = container.viewContext
        let runEntities = try ExplorationPersistenceBridge.fetchRunEntities(in: context)
        var didApplyRewards = false

        for entity in runEntities {
            let storedRun = ExplorationPersistenceBridge.makeRunSessionRecord(from: entity)
            let livePartyMembers = try storedRun.memberCharacterIds.map { characterId in
                ExplorationPersistenceBridge.makeCharacterRecord(
                    from: try ExplorationPersistenceBridge.fetchCharacterEntity(
                        characterId: characterId,
                        in: context
                    )
                )
            }
            let resolvedRun = try ExplorationResolver.resolve(
                session: storedRun,
                upTo: currentDate,
                partyMembers: livePartyMembers,
                masterData: masterData
            )

            if resolvedRun != storedRun {
                ExplorationPersistenceBridge.apply(
                    resolvedRun,
                    rewardsApplied: entity.rewardsApplied,
                    to: entity
                )
            }

            if let completion = resolvedRun.completion,
               entity.rewardsApplied == false {
                try ExplorationPersistenceBridge.applyCompletionRewards(
                    completion,
                    finalPartyHPs: resolvedRun.currentPartyHPs,
                    memberCharacterIds: resolvedRun.memberCharacterIds,
                    masterData: masterData,
                    in: context
                )
                entity.rewardsApplied = true
                didApplyRewards = true
            }
        }

        if context.hasChanges {
            try context.save()
        }

        let runs = try ExplorationPersistenceBridge.fetchRunEntities(in: context)
            .map(ExplorationPersistenceBridge.makeRunSessionRecord)
            .sorted(by: ExplorationPersistenceBridge.isOrderedBefore)
        return ExplorationRunSnapshot(runs: runs, didApplyRewards: didApplyRewards)
    }

    func hasActiveRun(partyId: Int) throws -> Bool {
        try ExplorationPersistenceBridge.fetchActiveRunEntity(
            partyId: partyId,
            in: container.viewContext
        ) != nil
    }

    func validatePartyMutationIsAllowed(partyId: Int) throws {
        if try hasActiveRun(partyId: partyId) {
            throw ExplorationRepositoryError.partyLockedByActiveRun(partyId: partyId)
        }
    }

    func validateCharacterMutationIsAllowed(characterId: Int) throws {
        let context = container.viewContext
        let parties = try ExplorationPersistenceBridge.fetchPartyEntities(in: context)
        for party in parties {
            let memberCharacterIds = ExplorationPersistenceBridge.memberCharacterIds(from: party)
            guard memberCharacterIds.contains(characterId) else {
                continue
            }

            if try ExplorationPersistenceBridge.fetchActiveRunEntity(
                partyId: Int(party.partyId),
                in: context
            ) != nil {
                throw ExplorationRepositoryError.characterLockedByActiveRun(characterId: characterId)
            }
        }
    }
}

private enum ExplorationPersistenceBridge {
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    static func fetchRunEntities(
        in context: NSManagedObjectContext
    ) throws -> [RunSessionEntity] {
        let request = NSFetchRequest<RunSessionEntity>(entityName: "RunSessionEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "startedAt", ascending: false),
            NSSortDescriptor(key: "partyId", ascending: true),
            NSSortDescriptor(key: "partyRunId", ascending: false)
        ]
        return try context.fetch(request)
    }

    static func fetchActiveRunEntity(
        partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> RunSessionEntity? {
        let request = NSFetchRequest<RunSessionEntity>(entityName: "RunSessionEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "partyId == %d AND completedAt == nil",
            partyId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "partyRunId", ascending: false)]
        return try context.fetch(request).first
    }

    static func nextRunId(
        for partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "RunSessionEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["partyRunId"]
        request.predicate = NSPredicate(format: "partyId == %d", partyId)
        request.sortDescriptors = [NSSortDescriptor(key: "partyRunId", ascending: false)]
        request.fetchLimit = 1
        let latestRunId = (try context.fetch(request).first?["partyRunId"] as? Int) ?? 0
        return latestRunId + 1
    }

    static func fetchPartyEntities(
        in context: NSManagedObjectContext
    ) throws -> [PartyEntity] {
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "partyId", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchPartyEntity(
        partyId: Int,
        in context: NSManagedObjectContext
    ) throws -> PartyEntity {
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "partyId == %d", partyId)

        guard let party = try context.fetch(request).first else {
            throw ExplorationRepositoryError.invalidParty(partyId: partyId)
        }
        return party
    }

    static func fetchCharacterEntity(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> CharacterEntity {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "characterId == %d", characterId)

        guard let character = try context.fetch(request).first else {
            throw ExplorationRepositoryError.invalidRunMember(characterId: characterId)
        }
        return character
    }

    static func fetchPlayerStateEntity(
        in context: NSManagedObjectContext
    ) throws -> PlayerStateEntity {
        let request = NSFetchRequest<PlayerStateEntity>(entityName: "PlayerStateEntity")
        request.fetchLimit = 1
        if let playerState = try context.fetch(request).first {
            return playerState
        }

        guard let playerState = NSEntityDescription.insertNewObject(
            forEntityName: "PlayerStateEntity",
            into: context
        ) as? PlayerStateEntity else {
            fatalError("PlayerStateEntity の生成に失敗しました。")
        }
        playerState.gold = Int64(PlayerState.initial.gold)
        playerState.nextCharacterId = Int64(PlayerState.initial.nextCharacterId)
        playerState.autoReviveDefeatedCharacters = PlayerState.initial.autoReviveDefeatedCharacters
        return playerState
    }

    static func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        (entity.memberCharacterIdsRawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
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

    static func makeRunSessionRecord(from entity: RunSessionEntity) -> RunSessionRecord {
        RunSessionRecord(
            partyRunId: Int(entity.partyRunId),
            partyId: Int(entity.partyId),
            labyrinthId: Int(entity.labyrinthId),
            targetFloorNumber: Int(entity.targetFloorNumber),
            startedAt: entity.startedAt ?? .distantPast,
            rootSeed: UInt64(bitPattern: Int64(entity.rootSeedSigned)),
            maximumLoopCount: Int(entity.maximumLoopCount),
            memberCharacterIds: decode([Int].self, from: entity.memberCharacterIdsRawValue),
            completedBattleCount: Int(entity.completedBattleCount),
            currentPartyHPs: decode([Int].self, from: entity.currentPartyHPsRawValue),
            battleLogs: decode([ExplorationBattleLog].self, from: entity.battleLogsRawValue),
            goldBuffer: Int(entity.goldBuffer),
            experienceRewards: decode([ExplorationExperienceReward].self, from: entity.experienceRewardsRawValue),
            dropRewards: decode([ExplorationDropReward].self, from: entity.dropRewardsRawValue),
            completion: makeCompletionRecord(from: entity)
        )
    }

    static func makeCompletionRecord(
        from entity: RunSessionEntity
    ) -> RunCompletionRecord? {
        guard let completedAt = entity.completedAt,
              let reasonRawValue = entity.completionReasonRawValue,
              let reason = RunCompletionReason(rawValue: reasonRawValue) else {
            return nil
        }

        return RunCompletionRecord(
            completedAt: completedAt,
            reason: reason,
            completedLoopCount: Int(entity.completedLoopCount),
            gold: Int(entity.goldBuffer),
            experienceRewards: decode([ExplorationExperienceReward].self, from: entity.experienceRewardsRawValue),
            dropRewards: decode([ExplorationDropReward].self, from: entity.dropRewardsRawValue)
        )
    }

    static func apply(
        _ record: RunSessionRecord,
        rewardsApplied: Bool,
        to entity: RunSessionEntity
    ) {
        entity.partyRunId = Int64(record.partyRunId)
        entity.partyId = Int64(record.partyId)
        entity.labyrinthId = Int64(record.labyrinthId)
        entity.targetFloorNumber = Int64(record.targetFloorNumber)
        entity.startedAt = record.startedAt
        entity.rootSeedSigned = Int64(bitPattern: record.rootSeed)
        entity.maximumLoopCount = Int64(record.maximumLoopCount)
        entity.memberCharacterIdsRawValue = encode(record.memberCharacterIds)
        entity.completedBattleCount = Int64(record.completedBattleCount)
        entity.currentPartyHPsRawValue = encode(record.currentPartyHPs)
        entity.battleLogsRawValue = encode(record.battleLogs)
        entity.goldBuffer = Int64(record.goldBuffer)
        entity.experienceRewardsRawValue = encode(record.experienceRewards)
        entity.dropRewardsRawValue = encode(record.dropRewards)
        entity.completedAt = record.completion?.completedAt
        entity.completionReasonRawValue = record.completion?.reason.rawValue
        entity.completedLoopCount = Int64(record.completion?.completedLoopCount ?? 0)
        entity.rewardsApplied = rewardsApplied
    }

    static func applyCompletionRewards(
        _ completion: RunCompletionRecord,
        finalPartyHPs: [Int],
        memberCharacterIds: [Int],
        masterData: MasterData,
        in context: NSManagedObjectContext
    ) throws {
        let playerState = try fetchPlayerStateEntity(in: context)
        playerState.gold += Int64(completion.gold)

        let itemCounts = completion.dropRewards.reduce(into: [CompositeItemID: Int]()) { partial, reward in
            partial[reward.itemID, default: 0] += 1
        }
        if !itemCounts.isEmpty {
            try applyInventoryCounts(itemCounts, in: context)
        }

        let experienceRewardsByCharacterId = Dictionary(
            uniqueKeysWithValues: completion.experienceRewards.map { ($0.characterId, $0.experience) }
        )
        for (offset, characterId) in memberCharacterIds.enumerated() {
            let character = try fetchCharacterEntity(characterId: characterId, in: context)
            let gainedExperience = experienceRewardsByCharacterId[characterId] ?? 0
            let totalExperience = Int(character.experience) + gainedExperience
            character.experience = Int64(totalExperience)

            if let race = masterData.races.first(where: { $0.id == Int(character.raceId) }) {
                character.level = Int64(
                    CharacterLevelProgression.level(
                        for: totalExperience,
                        levelCap: race.levelCap
                    )
                )
            }

            if finalPartyHPs.indices.contains(offset) {
                character.currentHP = Int64(max(finalPartyHPs[offset], 0))
            }

            if playerState.autoReviveDefeatedCharacters,
               character.currentHP == 0 {
                try restoreCurrentHPToMax(of: character, masterData: masterData)
            }
        }
    }

    static func applyInventoryCounts(
        _ itemCounts: [CompositeItemID: Int],
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "stackKeyRawValue", ascending: true)]
        let existingEntities = try context.fetch(request)
        var inventoryByKey: [String: InventoryItemEntity] = Dictionary(
            uniqueKeysWithValues: existingEntities.compactMap { entity in
                guard let rawValue = entity.stackKeyRawValue else {
                    return nil
                }
                return (rawValue, entity)
            }
        )

        for (itemID, count) in itemCounts where count > 0 {
            let inventoryEntity: InventoryItemEntity
            if let existingEntity = inventoryByKey[itemID.rawValue] {
                inventoryEntity = existingEntity
            } else {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                insertedEntity.stackKeyRawValue = itemID.rawValue
                insertedEntity.count = 0
                inventoryByKey[itemID.rawValue] = insertedEntity
                inventoryEntity = insertedEntity
            }

            inventoryEntity.count += Int64(count)
        }
    }

    static func restoreCurrentHPToMax(
        of entity: CharacterEntity,
        masterData: MasterData
    ) throws {
        let character = makeCharacterRecord(from: entity)
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            throw ExplorationRepositoryError.invalidRunMember(characterId: Int(entity.characterId))
        }

        entity.currentHP = Int64(status.maxHP)
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let rawValue = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return rawValue
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from rawValue: String?
    ) -> T {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? jsonDecoder.decode(type, from: data) else {
            if let fallback = [] as? T {
                return fallback
            }
            fatalError("探索データのデコードに失敗しました。")
        }
        return decoded
    }

    static func rootSeed(
        partyId: Int,
        partyRunId: Int,
        startedAt: Date
    ) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let payload = "\(partyId):\(partyRunId):\(startedAt.timeIntervalSinceReferenceDate)"
        for byte in payload.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    static func isOrderedBefore(
        _ lhs: RunSessionRecord,
        _ rhs: RunSessionRecord
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        if lhs.partyId != rhs.partyId {
            return lhs.partyId < rhs.partyId
        }
        return lhs.partyRunId > rhs.partyRunId
    }
}
