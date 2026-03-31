// Persists guild roster, party, and equipment values through Core Data and rebuilds snapshots for upper layers.

import CoreData
import Foundation

struct GuildRosterSnapshot: Sendable {
    var playerState: PlayerState
    var characters: [CharacterRecord]
    var labyrinthProgressRecords: [LabyrinthProgressRecord]
}

@MainActor
final class GuildCoreDataStore {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadRosterSnapshot() throws -> GuildRosterSnapshot {
        let context = container.viewContext
        let playerState = try fetchOrCreatePlayerState(in: context)
        try saveIfNeeded(context)
        return try GuildRosterSnapshot(
            playerState: makePlayerState(from: playerState),
            characters: fetchCharacters(in: context).map(makeCharacterRecord),
            labyrinthProgressRecords: fetchLabyrinthProgressEntities(in: context).map(makeLabyrinthProgressRecord)
        )
    }

    func loadFreshRosterSnapshot() throws -> GuildRosterSnapshot {
        let context = container.viewContext
        context.reset()
        let playerState = try fetchOrCreatePlayerState(in: context)
        try saveIfNeeded(context)
        return try GuildRosterSnapshot(
            playerState: makePlayerState(from: playerState),
            characters: fetchCharacters(in: context).map(makeCharacterRecord),
            labyrinthProgressRecords: fetchLabyrinthProgressEntities(in: context).map(makeLabyrinthProgressRecord)
        )
    }

    func loadParties() throws -> [PartyRecord] {
        let context = container.viewContext
        _ = try fetchOrCreateInitialParties(in: context)
        try saveIfNeeded(context)
        return try fetchPartyEntities(in: context).map(makePartyRecord)
    }

    func loadInventoryStacks() throws -> [CompositeItemStack] {
        try fetchInventoryItemEntities(in: container.viewContext)
            .compactMap(makeInventoryStack)
            .sorted { $0.itemID.isOrdered(before: $1.itemID) }
    }

    func loadCharacter(characterId: Int) throws -> CharacterRecord? {
        let context = container.viewContext
        return try fetchCharacterEntity(characterId: characterId, in: context)
            .map(makeCharacterRecord)
    }

    func loadInventoryStack(itemID: CompositeItemID) throws -> CompositeItemStack? {
        let context = container.viewContext
        return try fetchInventoryItemEntity(itemID: itemID, in: context)
            .flatMap(makeInventoryStack)
    }

    func saveRosterSnapshot(_ snapshot: GuildRosterSnapshot) throws {
        let context = container.viewContext
        let playerState = try fetchOrCreatePlayerState(in: context)
        playerState.gold = Int64(snapshot.playerState.gold)
        playerState.nextCharacterId = Int64(snapshot.playerState.nextCharacterId)
        playerState.autoReviveDefeatedCharacters = snapshot.playerState.autoReviveDefeatedCharacters
        try syncCharacters(snapshot.characters, in: context)
        try syncLabyrinthProgressRecords(snapshot.labyrinthProgressRecords, in: context)
        try saveIfNeeded(context)
    }

    func saveParties(_ parties: [PartyRecord]) throws {
        let context = container.viewContext
        try syncParties(parties, in: context)
        try saveIfNeeded(context)
    }

    func saveInventoryStacks(_ inventoryStacks: [CompositeItemStack]) throws {
        let context = container.viewContext
        try syncInventoryStacks(inventoryStacks, in: context)
        try saveIfNeeded(context)
    }

    func saveCharacter(
        _ character: CharacterRecord
    ) throws {
        let context = container.viewContext
        guard let entity = try fetchCharacterEntity(characterId: character.characterId, in: context) else {
            fatalError("CharacterEntity が見つかりません。 characterId=\(character.characterId)")
        }

        apply(character: character, to: entity)
        try saveIfNeeded(context)
    }

    func saveCharacter(
        _ character: CharacterRecord,
        inventoryItemID: CompositeItemID,
        inventoryStack: CompositeItemStack?
    ) throws {
        let context = container.viewContext
        guard let entity = try fetchCharacterEntity(characterId: character.characterId, in: context) else {
            fatalError("CharacterEntity が見つかりません。 characterId=\(character.characterId)")
        }

        apply(character: character, to: entity)

        if let inventoryStack {
            let inventoryEntity = try fetchInventoryItemEntity(itemID: inventoryStack.itemID, in: context) ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                return insertedEntity
            }()
            inventoryEntity.stackKeyRawValue = inventoryStack.itemID.rawValue
            inventoryEntity.count = Int64(inventoryStack.count)
        } else if let inventoryEntity = try fetchInventoryItemEntity(itemID: inventoryItemID, in: context) {
            context.delete(inventoryEntity)
        }

        try saveIfNeeded(context)
    }

    private func syncCharacters(
        _ characters: [CharacterRecord],
        in context: NSManagedObjectContext
    ) throws {
        var existingByID = Dictionary(
            uniqueKeysWithValues: try fetchCharacters(in: context).map { (Int($0.characterId), $0) }
        )
        let incomingIDs = Set(characters.map(\.characterId))

        for (characterID, entity) in existingByID where !incomingIDs.contains(characterID) {
            context.delete(entity)
        }

        for character in characters {
            let entity = existingByID[character.characterId] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "CharacterEntity",
                    into: context
                ) as? CharacterEntity else {
                    fatalError("CharacterEntity の生成に失敗しました。")
                }
                existingByID[character.characterId] = insertedEntity
                return insertedEntity
            }()

            entity.characterId = Int64(character.characterId)
            entity.name = character.name
            entity.raceId = Int64(character.raceId)
            entity.previousJobId = Int64(character.previousJobId)
            entity.currentJobId = Int64(character.currentJobId)
            entity.aptitudeId = Int64(character.aptitudeId)
            entity.portraitVariant = Int64(character.portraitGender.rawValue)
            entity.experience = Int64(character.experience)
            entity.level = Int64(character.level)
            entity.currentHP = Int64(character.currentHP)
            entity.breathRate = Int64(character.autoBattleSettings.rates.breath)
            entity.attackRate = Int64(character.autoBattleSettings.rates.attack)
            entity.recoverySpellRate = Int64(character.autoBattleSettings.rates.recoverySpell)
            entity.attackSpellRate = Int64(character.autoBattleSettings.rates.attackSpell)
            entity.actionPriorityRawValue = character.autoBattleSettings.priority
                .map(\.rawValue)
                .joined(separator: ",")
            setEquippedItemStacks(character.equippedItemStacks, on: entity)
        }
    }

    private func syncParties(
        _ parties: [PartyRecord],
        in context: NSManagedObjectContext
    ) throws {
        var existingByID = Dictionary(
            uniqueKeysWithValues: try fetchPartyEntities(in: context).map { (Int($0.partyId), $0) }
        )
        let incomingIDs = Set(parties.map(\.partyId))

        for (partyID, entity) in existingByID where !incomingIDs.contains(partyID) {
            context.delete(entity)
        }

        for partyRecord in parties {
            let entity = existingByID[partyRecord.partyId] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "PartyEntity",
                    into: context
                ) as? PartyEntity else {
                    fatalError("PartyEntity の生成に失敗しました。")
                }
                existingByID[partyRecord.partyId] = insertedEntity
                return insertedEntity
            }()

            entity.partyId = Int64(partyRecord.partyId)
            entity.name = partyRecord.name
            entity.selectedLabyrinthId = partyRecord.selectedLabyrinthId.map(Int64.init) ?? 0
            entity.selectedDifficultyTitleId = partyRecord.selectedDifficultyTitleId.map(Int64.init) ?? 0
            setMemberCharacterIds(partyRecord.memberCharacterIds, on: entity)
        }
    }

    private func syncLabyrinthProgressRecords(
        _ records: [LabyrinthProgressRecord],
        in context: NSManagedObjectContext
    ) throws {
        var existingByLabyrinthId = Dictionary(
            uniqueKeysWithValues: try fetchLabyrinthProgressEntities(in: context).map { (Int($0.labyrinthId), $0) }
        )
        let incomingLabyrinthIds = Set(records.map(\.labyrinthId))

        for (labyrinthId, entity) in existingByLabyrinthId where !incomingLabyrinthIds.contains(labyrinthId) {
            context.delete(entity)
        }

        for record in records {
            let entity = existingByLabyrinthId[record.labyrinthId] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "LabyrinthProgressEntity",
                    into: context
                ) as? LabyrinthProgressEntity else {
                    fatalError("LabyrinthProgressEntity の生成に失敗しました。")
                }
                existingByLabyrinthId[record.labyrinthId] = insertedEntity
                return insertedEntity
            }()

            entity.labyrinthId = Int64(record.labyrinthId)
            entity.highestUnlockedDifficultyTitleId = Int64(record.highestUnlockedDifficultyTitleId)
        }
    }

    private func syncInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        in context: NSManagedObjectContext
    ) throws {
        let normalizedStacks = inventoryStacks.normalizedCompositeItemStacks()
        var existingByKey: [String: InventoryItemEntity] = try Dictionary(
            uniqueKeysWithValues: fetchInventoryItemEntities(in: context).compactMap { entity in
                guard let rawValue = entity.stackKeyRawValue else {
                    return nil
                }
                return (rawValue, entity)
            }
        )
        let incomingKeys = Set(normalizedStacks.map(\.itemID.rawValue))

        for (rawValue, entity) in existingByKey where !incomingKeys.contains(rawValue) {
            context.delete(entity)
        }

        for stack in normalizedStacks {
            let rawValue = stack.itemID.rawValue
            let entity = existingByKey[rawValue] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                existingByKey[rawValue] = insertedEntity
                return insertedEntity
            }()

            entity.stackKeyRawValue = rawValue
            entity.count = Int64(stack.count)
        }
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func fetchOrCreatePlayerState(
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

    private func fetchOrCreateInitialParties(
        in context: NSManagedObjectContext
    ) throws -> [PartyEntity] {
        let parties = try fetchPartyEntities(in: context)
        if !parties.isEmpty {
            return parties
        }

        guard let party = NSEntityDescription.insertNewObject(
            forEntityName: "PartyEntity",
            into: context
        ) as? PartyEntity else {
            fatalError("PartyEntity の生成に失敗しました。")
        }

        party.partyId = 1
        party.name = PartyRecord.defaultName(for: 1)
        party.selectedLabyrinthId = 0
        party.selectedDifficultyTitleId = 0
        setMemberCharacterIds([], on: party)
        return try fetchPartyEntities(in: context)
    }

    private func fetchCharacters(
        in context: NSManagedObjectContext
    ) throws -> [CharacterEntity] {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "characterId", ascending: true)]
        return try context.fetch(request)
    }

    private func fetchCharacterEntity(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> CharacterEntity? {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "characterId == %d", characterId)
        return try context.fetch(request).first
    }

    private func fetchInventoryItemEntities(
        in context: NSManagedObjectContext
    ) throws -> [InventoryItemEntity] {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "stackKeyRawValue", ascending: true)]
        return try context.fetch(request)
    }

    private func fetchInventoryItemEntity(
        itemID: CompositeItemID,
        in context: NSManagedObjectContext
    ) throws -> InventoryItemEntity? {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "stackKeyRawValue == %@", itemID.rawValue)
        return try context.fetch(request).first
    }

    private func fetchPartyEntities(
        in context: NSManagedObjectContext
    ) throws -> [PartyEntity] {
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "partyId", ascending: true)]
        return try context.fetch(request)
    }

    private func fetchLabyrinthProgressEntities(
        in context: NSManagedObjectContext
    ) throws -> [LabyrinthProgressEntity] {
        let request = NSFetchRequest<LabyrinthProgressEntity>(entityName: "LabyrinthProgressEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "labyrinthId", ascending: true)]
        return try context.fetch(request)
    }

    private func makePlayerState(from entity: PlayerStateEntity) -> PlayerState {
        PlayerState(
            gold: Int(entity.gold),
            nextCharacterId: Int(entity.nextCharacterId),
            autoReviveDefeatedCharacters: entity.autoReviveDefeatedCharacters
        )
    }

    private func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
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

    private func apply(
        character: CharacterRecord,
        to entity: CharacterEntity
    ) {
        entity.characterId = Int64(character.characterId)
        entity.name = character.name
        entity.raceId = Int64(character.raceId)
        entity.previousJobId = Int64(character.previousJobId)
        entity.currentJobId = Int64(character.currentJobId)
        entity.aptitudeId = Int64(character.aptitudeId)
        entity.portraitVariant = Int64(character.portraitGender.rawValue)
        entity.experience = Int64(character.experience)
        entity.level = Int64(character.level)
        entity.currentHP = Int64(character.currentHP)
        entity.breathRate = Int64(character.autoBattleSettings.rates.breath)
        entity.attackRate = Int64(character.autoBattleSettings.rates.attack)
        entity.recoverySpellRate = Int64(character.autoBattleSettings.rates.recoverySpell)
        entity.attackSpellRate = Int64(character.autoBattleSettings.rates.attackSpell)
        entity.actionPriorityRawValue = character.autoBattleSettings.priority
            .map(\.rawValue)
            .joined(separator: ",")
        setEquippedItemStacks(character.equippedItemStacks, on: entity)
    }

    private func makePartyRecord(from entity: PartyEntity) -> PartyRecord {
        PartyRecord(
            partyId: Int(entity.partyId),
            name: entity.name ?? PartyRecord.defaultName(for: Int(entity.partyId)),
            memberCharacterIds: memberCharacterIds(from: entity),
            selectedLabyrinthId: entity.selectedLabyrinthId == 0 ? nil : Int(entity.selectedLabyrinthId),
            selectedDifficultyTitleId: entity.selectedDifficultyTitleId == 0 ? nil : Int(entity.selectedDifficultyTitleId)
        )
    }

    private func makeLabyrinthProgressRecord(from entity: LabyrinthProgressEntity) -> LabyrinthProgressRecord {
        LabyrinthProgressRecord(
            labyrinthId: Int(entity.labyrinthId),
            highestUnlockedDifficultyTitleId: Int(entity.highestUnlockedDifficultyTitleId)
        )
    }

    private func makeInventoryStack(from entity: InventoryItemEntity) -> CompositeItemStack? {
        guard let rawValue = entity.stackKeyRawValue,
              let itemID = CompositeItemID(rawValue: rawValue),
              entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(itemID: itemID, count: Int(entity.count))
    }

    private func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        (entity.memberCharacterIdsRawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    private func setMemberCharacterIds(_ memberCharacterIds: [Int], on entity: PartyEntity) {
        entity.memberCharacterIdsRawValue = memberCharacterIds.map(String.init).joined(separator: ",")
    }

    private func equippedItemStacks(from entity: CharacterEntity) -> [CompositeItemStack] {
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

    private func setEquippedItemStacks(
        _ equippedItemStacks: [CompositeItemStack],
        on entity: CharacterEntity
    ) {
        entity.equippedItemStacksRawValue = equippedItemStacks
            .normalizedCompositeItemStacks()
            .map { "\($0.itemID.rawValue)#\($0.count)" }
            .joined(separator: "|")
    }
}
