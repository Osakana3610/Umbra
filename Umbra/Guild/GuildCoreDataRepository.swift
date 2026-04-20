// Persists guild roster, party, and equipment values through Core Data and rebuilds snapshots for upper layers.

import CoreData
import Foundation

struct GuildRosterSnapshot: Sendable {
    var playerState: PlayerState
    var characters: [CharacterRecord]
    var labyrinthProgressRecords: [LabyrinthProgressRecord]
}

@MainActor
final class GuildCoreDataRepository {
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
        playerState.lastBackgroundedAt = snapshot.playerState.lastBackgroundedAt
        syncAutoSellItems(snapshot.playerState.autoSellItemIDs, on: playerState, in: context)
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
        playerState.lastBackgroundedAt = snapshot.playerState.lastBackgroundedAt
        syncAutoSellItems(snapshot.playerState.autoSellItemIDs, on: playerState, in: context)
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
            inventoryStack.itemID.apply(to: inventoryEntity)
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
        playerStateEntity.lastBackgroundedAt = playerState.lastBackgroundedAt
        syncAutoSellItems(playerState.autoSellItemIDs, on: playerStateEntity, in: context)
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
            let persistedPriority = CharacterAutoBattleSettings.persistedPriorityValues(
                for: character.autoBattleSettings.priority
            )
            entity.actionPriorityPrimaryValue = persistedPriority[0]
            entity.actionPrioritySecondaryValue = persistedPriority[1]
            entity.actionPriorityTertiaryValue = persistedPriority[2]
            entity.actionPriorityQuaternaryValue = persistedPriority[3]
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
        var existingByID: [CompositeItemID: InventoryItemEntity] = try Dictionary(
            uniqueKeysWithValues: fetchInventoryItemEntities(in: context).map { (CompositeItemID(entity: $0), $0) }
        )
        let incomingIDs = Set(normalizedStacks.map(\.itemID))

        for (itemID, entity) in existingByID where !incomingIDs.contains(itemID) {
            context.delete(entity)
        }

        for stack in normalizedStacks {
            let entity = existingByID[stack.itemID] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "InventoryItemEntity",
                    into: context
                ) as? InventoryItemEntity else {
                    fatalError("InventoryItemEntity の生成に失敗しました。")
                }
                existingByID[stack.itemID] = insertedEntity
                return insertedEntity
            }()

            stack.itemID.apply(to: entity)
            entity.count = Int64(stack.count)
        }
    }

    private func syncShopInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        in context: NSManagedObjectContext
    ) throws {
        let normalizedStacks = inventoryStacks.normalizedCompositeItemStacks()
        var existingByID: [CompositeItemID: ShopItemEntity] = try Dictionary(
            uniqueKeysWithValues: fetchShopItemEntities(in: context).map { (CompositeItemID(entity: $0), $0) }
        )
        let incomingIDs = Set(normalizedStacks.map(\.itemID))

        for (itemID, entity) in existingByID where !incomingIDs.contains(itemID) {
            context.delete(entity)
        }

        for stack in normalizedStacks {
            let entity = existingByID[stack.itemID] ?? {
                guard let insertedEntity = NSEntityDescription.insertNewObject(
                    forEntityName: "ShopItemEntity",
                    into: context
                ) as? ShopItemEntity else {
                    fatalError("ShopItemEntity の生成に失敗しました。")
                }
                existingByID[stack.itemID] = insertedEntity
                return insertedEntity
            }()

            stack.itemID.apply(to: entity)
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
        request.sortDescriptors = CompositeItemPersistence.sortDescriptors
        return try context.fetch(request)
    }

    private func fetchShopItemEntities(
        in context: NSManagedObjectContext
    ) throws -> [ShopItemEntity] {
        let request = NSFetchRequest<ShopItemEntity>(entityName: "ShopItemEntity")
        request.sortDescriptors = CompositeItemPersistence.sortDescriptors
        return try context.fetch(request)
    }

    private func fetchInventoryItemEntity(
        itemID: CompositeItemID,
        in context: NSManagedObjectContext
    ) throws -> InventoryItemEntity? {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.fetchLimit = 1
        request.predicate = CompositeItemPersistence.predicate(for: itemID)
        return try context.fetch(request).first
    }

    private func fetchShopItemEntity(
        itemID: CompositeItemID,
        in context: NSManagedObjectContext
    ) throws -> ShopItemEntity? {
        let request = NSFetchRequest<ShopItemEntity>(entityName: "ShopItemEntity")
        request.fetchLimit = 1
        request.predicate = CompositeItemPersistence.predicate(for: itemID)
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
            autoSellItemIDs: makeAutoSellItemIDs(from: entity),
            lastBackgroundedAt: entity.lastBackgroundedAt
        )
    }

    private func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
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
        let persistedPriority = CharacterAutoBattleSettings.persistedPriorityValues(
            for: character.autoBattleSettings.priority
        )
        entity.actionPriorityPrimaryValue = persistedPriority[0]
        entity.actionPrioritySecondaryValue = persistedPriority[1]
        entity.actionPriorityTertiaryValue = persistedPriority[2]
        entity.actionPriorityQuaternaryValue = persistedPriority[3]
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
        guard entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(itemID: CompositeItemID(entity: entity), count: Int(entity.count))
    }

    private func makeShopInventoryStack(from entity: ShopItemEntity) -> CompositeItemStack? {
        guard entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(itemID: CompositeItemID(entity: entity), count: Int(entity.count))
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
        let equippedItems = entity.equippedItems as? Set<CharacterEquippedItemEntity> ?? []
        return equippedItems.sorted {
            Int($0.stackIndex) < Int($1.stackIndex)
        }.compactMap { itemEntity in
            guard itemEntity.count > 0 else {
                return nil
            }

            return CompositeItemStack(
                itemID: CompositeItemID(entity: itemEntity),
                count: Int(itemEntity.count)
            )
        }
        .normalizedCompositeItemStacks()
    }

    private func setEquippedItemStacks(
        _ equippedItemStacks: [CompositeItemStack],
        on entity: CharacterEntity
    ) {
        guard let context = entity.managedObjectContext else {
            fatalError("CharacterEntity の context が見つかりません。")
        }

        let normalizedStacks = equippedItemStacks.normalizedCompositeItemStacks()
        let existingEntities = entity.equippedItems as? Set<CharacterEquippedItemEntity> ?? []
        for existingEntity in existingEntities {
            context.delete(existingEntity)
        }

        for (stackIndex, stack) in normalizedStacks.enumerated() {
            guard let itemEntity = NSEntityDescription.insertNewObject(
                forEntityName: "CharacterEquippedItemEntity",
                into: context
            ) as? CharacterEquippedItemEntity else {
                fatalError("CharacterEquippedItemEntity の生成に失敗しました。")
            }

            itemEntity.character = entity
            itemEntity.stackIndex = Int64(stackIndex)
            itemEntity.count = Int64(stack.count)
            stack.itemID.apply(to: itemEntity)
        }
    }

    private func makeAutoSellItemIDs(from entity: PlayerStateEntity) -> Set<CompositeItemID> {
        let autoSellEntities = entity.autoSellItems as? Set<PlayerStateAutoSellItemEntity> ?? []
        return Set(autoSellEntities.map(CompositeItemID.init(entity:)))
    }

    private func syncAutoSellItems(
        _ itemIDs: Set<CompositeItemID>,
        on entity: PlayerStateEntity,
        in context: NSManagedObjectContext
    ) {
        let existingEntities = entity.autoSellItems as? Set<PlayerStateAutoSellItemEntity> ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existingEntities.map { (CompositeItemID(entity: $0), $0) })

        for (itemID, existingEntity) in existingByID where !itemIDs.contains(itemID) {
            context.delete(existingEntity)
        }

        for itemID in itemIDs where existingByID[itemID] == nil {
            guard let autoSellEntity = NSEntityDescription.insertNewObject(
                forEntityName: "PlayerStateAutoSellItemEntity",
                into: context
            ) as? PlayerStateAutoSellItemEntity else {
                fatalError("PlayerStateAutoSellItemEntity の生成に失敗しました。")
            }

            autoSellEntity.playerState = entity
            itemID.apply(to: autoSellEntity)
        }
    }
}
