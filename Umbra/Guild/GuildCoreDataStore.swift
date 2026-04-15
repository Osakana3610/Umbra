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

    func loadShopInventoryStacks() throws -> [CompositeItemStack] {
        try fetchShopItemEntities(in: container.viewContext)
            .compactMap(makeShopInventoryStack)
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

    func loadShopInventoryStack(itemID: CompositeItemID) throws -> CompositeItemStack? {
        let context = container.viewContext
        return try fetchShopItemEntity(itemID: itemID, in: context)
            .flatMap(makeShopInventoryStack)
    }

    func saveRosterSnapshot(_ snapshot: GuildRosterSnapshot) throws {
        let context = container.viewContext
        let playerState = try fetchOrCreatePlayerState(in: context)
        playerState.gold = Int64(snapshot.playerState.gold)
        playerState.catTicketCount = Int64(snapshot.playerState.catTicketCount)
        playerState.nextCharacterId = Int64(snapshot.playerState.nextCharacterId)
        playerState.autoReviveDefeatedCharacters = snapshot.playerState.autoReviveDefeatedCharacters
        playerState.shopInventoryInitialized = snapshot.playerState.shopInventoryInitialized
        playerState.autoSellItemIDsRawValue = encodedAutoSellItemIDs(snapshot.playerState.autoSellItemIDs)
        playerState.lastBackgroundedAt = snapshot.playerState.lastBackgroundedAt
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

    func saveShopInventoryStacks(_ inventoryStacks: [CompositeItemStack]) throws {
        let context = container.viewContext
        try syncShopInventoryStacks(inventoryStacks, in: context)
        try saveIfNeeded(context)
    }

    func saveRosterState(
        _ snapshot: GuildRosterSnapshot,
        parties: [PartyRecord],
        inventoryStacks: [CompositeItemStack]
    ) throws {
        let context = container.viewContext
        let playerState = try fetchOrCreatePlayerState(in: context)
        playerState.gold = Int64(snapshot.playerState.gold)
        playerState.catTicketCount = Int64(snapshot.playerState.catTicketCount)
        playerState.nextCharacterId = Int64(snapshot.playerState.nextCharacterId)
        playerState.autoReviveDefeatedCharacters = snapshot.playerState.autoReviveDefeatedCharacters
        playerState.shopInventoryInitialized = snapshot.playerState.shopInventoryInitialized
        playerState.autoSellItemIDsRawValue = encodedAutoSellItemIDs(snapshot.playerState.autoSellItemIDs)
        playerState.lastBackgroundedAt = snapshot.playerState.lastBackgroundedAt
        try syncCharacters(snapshot.characters, in: context)
        try syncParties(parties, in: context)
        try syncInventoryStacks(inventoryStacks, in: context)
        try syncLabyrinthProgressRecords(snapshot.labyrinthProgressRecords, in: context)
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

    func saveTradeState(
        playerState: PlayerState,
        inventoryStacks: [CompositeItemStack],
        shopInventoryStacks: [CompositeItemStack]
    ) throws {
        let context = container.viewContext
        let playerStateEntity = try fetchOrCreatePlayerState(in: context)
        playerStateEntity.gold = Int64(playerState.gold)
        playerStateEntity.catTicketCount = Int64(playerState.catTicketCount)
        playerStateEntity.nextCharacterId = Int64(playerState.nextCharacterId)
        playerStateEntity.autoReviveDefeatedCharacters = playerState.autoReviveDefeatedCharacters
        playerStateEntity.shopInventoryInitialized = playerState.shopInventoryInitialized
        playerStateEntity.autoSellItemIDsRawValue = encodedAutoSellItemIDs(playerState.autoSellItemIDs)
        playerStateEntity.lastBackgroundedAt = playerState.lastBackgroundedAt
        try syncInventoryStacks(inventoryStacks, in: context)
        try syncShopInventoryStacks(shopInventoryStacks, in: context)
        try saveIfNeeded(context)
    }

    private func syncCharacters(
        _ characters: [CharacterRecord],
        in context: NSManagedObjectContext
    ) throws {
        // Roster saves are full-snapshot writes: anything missing from the incoming value set is
        // removed so Core Data cannot retain stale character rows.
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
            entity.portraitAssetID = character.portraitAssetID
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
        // Parties follow the same snapshot-sync rule as characters to keep roster, parties, and
        // pending automatic-run state aligned after one logical save.
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
            entity.automaticallyUsesCatTicket = partyRecord.automaticallyUsesCatTicket
            entity.pendingAutomaticRunCount = Int64(partyRecord.pendingAutomaticRunCount)
            entity.pendingAutomaticRunStartedAt = partyRecord.pendingAutomaticRunStartedAt
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
        // Inventory is normalized before persistence so duplicated stack keys from multiple
        // upstream mutations collapse into one stored row.
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

    private func syncShopInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        in context: NSManagedObjectContext
    ) throws {
        let normalizedStacks = inventoryStacks.normalizedCompositeItemStacks()
        var existingByKey: [String: ShopItemEntity] = try Dictionary(
            uniqueKeysWithValues: fetchShopItemEntities(in: context).compactMap { entity in
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
                    forEntityName: "ShopItemEntity",
                    into: context
                ) as? ShopItemEntity else {
                    fatalError("ShopItemEntity の生成に失敗しました。")
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
        playerState.catTicketCount = Int64(PlayerState.initial.catTicketCount)
        playerState.nextCharacterId = Int64(PlayerState.initial.nextCharacterId)
        playerState.autoReviveDefeatedCharacters = PlayerState.initial.autoReviveDefeatedCharacters
        playerState.shopInventoryInitialized = PlayerState.initial.shopInventoryInitialized
        playerState.autoSellItemIDsRawValue = encodedAutoSellItemIDs(PlayerState.initial.autoSellItemIDs)
        playerState.lastBackgroundedAt = PlayerState.initial.lastBackgroundedAt
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
        party.pendingAutomaticRunCount = 0
        party.pendingAutomaticRunStartedAt = nil
        party.automaticallyUsesCatTicket = false
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

    private func fetchShopItemEntities(
        in context: NSManagedObjectContext
    ) throws -> [ShopItemEntity] {
        let request = NSFetchRequest<ShopItemEntity>(entityName: "ShopItemEntity")
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

    private func fetchShopItemEntity(
        itemID: CompositeItemID,
        in context: NSManagedObjectContext
    ) throws -> ShopItemEntity? {
        let request = NSFetchRequest<ShopItemEntity>(entityName: "ShopItemEntity")
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
            catTicketCount: Int(entity.catTicketCount),
            nextCharacterId: Int(entity.nextCharacterId),
            autoReviveDefeatedCharacters: entity.autoReviveDefeatedCharacters,
            shopInventoryInitialized: entity.shopInventoryInitialized,
            autoSellItemIDs: decodedAutoSellItemIDs(entity.autoSellItemIDsRawValue),
            lastBackgroundedAt: entity.lastBackgroundedAt
        )
    }

    private func encodedAutoSellItemIDs(_ itemIDs: Set<CompositeItemID>) -> String {
        itemIDs
            .sorted { $0.isOrdered(before: $1) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private func decodedAutoSellItemIDs(_ rawValue: String?) -> Set<CompositeItemID> {
        guard let rawValue, !rawValue.isEmpty else {
            return []
        }

        return Set(
            rawValue
                .split(separator: ",")
                .compactMap { CompositeItemID(rawValue: String($0)) }
        )
    }

    private func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
        let parsedPriority = (entity.actionPriorityRawValue ?? "")
            .split(separator: ",")
            .compactMap { BattleActionKind(rawValue: String($0)) }
        // If persisted priority data drifts from the current enum set, fall back to the default
        // shape instead of constructing a partially invalid auto-battle configuration.
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
            portraitAssetID: entity.portraitAssetID ?? "",
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
        entity.portraitAssetID = character.portraitAssetID
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
            selectedDifficultyTitleId: entity.selectedDifficultyTitleId == 0 ? nil : Int(entity.selectedDifficultyTitleId),
            automaticallyUsesCatTicket: entity.automaticallyUsesCatTicket,
            pendingAutomaticRunCount: Int(entity.pendingAutomaticRunCount),
            pendingAutomaticRunStartedAt: entity.pendingAutomaticRunStartedAt
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

    private func makeShopInventoryStack(from entity: ShopItemEntity) -> CompositeItemStack? {
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
        // Equipped items are serialized as `itemRawValue#count` components joined by `|` so the
        // roster store can round-trip value types without extra Core Data child entities.
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
