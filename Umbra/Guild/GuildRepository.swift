// Persists roster, party, and equipment state through focused repositories over one Core Data store.

import CoreData
import Foundation

struct GuildRosterSnapshot: Sendable {
    let playerState: PlayerState
    let characters: [CharacterRecord]
}

struct HireCharacterResult: Sendable {
    let playerState: PlayerState
    let character: CharacterRecord
    let hireCost: Int
}

enum GuildRepositoryError: LocalizedError {
    case invalidHireSelection
    case insufficientGold(required: Int, available: Int)
    case maxPartyCountReached
    case invalidParty(partyId: Int)
    case invalidPartyName
    case partyFull(partyId: Int)
    case characterNotFound(characterId: Int)
    case invalidPartyMemberOrder
    case invalidItemStack
    case invalidStackCount
    case inventoryItemUnavailable
    case equipLimitReached(maximumCount: Int)
    case equippedItemNotFound
    case characterNotDefeated(characterId: Int)

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
        case .invalidPartyName:
            "パーティ名を入力してください。"
        case .partyFull(let partyId):
            "パーティ\(partyId)はすでに6人です。"
        case .characterNotFound(let characterId):
            "キャラクターが見つかりません。 characterId=\(characterId)"
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
        case .characterNotDefeated(let characterId):
            "キャラクターは戦闘不能ではありません。 characterId=\(characterId)"
        }
    }
}

@MainActor
final class GuildRosterRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadSnapshot() throws -> GuildRosterSnapshot {
        let context = container.viewContext
        let playerStateEntity = try GuildPersistenceBridge.fetchOrCreatePlayerState(in: context)

        if context.hasChanges {
            try context.save()
        }

        return GuildRosterSnapshot(
            playerState: PlayerState(
                gold: Int(playerStateEntity.gold),
                nextCharacterId: Int(playerStateEntity.nextCharacterId),
                autoReviveDefeatedCharacters: playerStateEntity.autoReviveDefeatedCharacters
            ),
            characters: try GuildPersistenceBridge.fetchCharacters(in: context)
                .map(GuildPersistenceBridge.makeCharacterRecord)
        )
    }

    func loadPlayerState() throws -> PlayerState {
        try loadSnapshot().playerState
    }

    func loadCharacters() throws -> [CharacterRecord] {
        try loadSnapshot().characters
    }

    func hireCharacter(
        raceId: Int,
        jobId: Int,
        aptitudeId: Int,
        masterData: MasterData
    ) throws -> HireCharacterResult {
        let context = container.viewContext
        let playerStateEntity = try GuildPersistenceBridge.fetchOrCreatePlayerState(in: context)
        guard let hireCost = GuildHiring.price(
            raceId: raceId,
            jobId: jobId,
            masterData: masterData
        ) else {
            throw GuildRepositoryError.invalidHireSelection
        }

        let availableGold = Int(playerStateEntity.gold)
        guard availableGold >= hireCost else {
            throw GuildRepositoryError.insufficientGold(
                required: hireCost,
                available: availableGold
            )
        }

        let character = try GuildHiring.makeCharacterRecord(
            nextCharacterId: Int(playerStateEntity.nextCharacterId),
            raceId: raceId,
            jobId: jobId,
            aptitudeId: aptitudeId,
            masterData: masterData
        )

        guard let entity = NSEntityDescription.insertNewObject(
            forEntityName: "CharacterEntity",
            into: context
        ) as? CharacterEntity else {
            fatalError("CharacterEntity の生成に失敗しました。")
        }

        GuildPersistenceBridge.apply(character, to: entity)
        playerStateEntity.gold -= Int64(hireCost)
        playerStateEntity.nextCharacterId += 1
        try context.save()

        return HireCharacterResult(
            playerState: PlayerState(
                gold: Int(playerStateEntity.gold),
                nextCharacterId: Int(playerStateEntity.nextCharacterId),
                autoReviveDefeatedCharacters: playerStateEntity.autoReviveDefeatedCharacters
            ),
            character: character,
            hireCost: hireCost
        )
    }

    func reviveCharacter(
        characterId: Int,
        masterData: MasterData
    ) throws -> GuildRosterSnapshot {
        let context = container.viewContext
        let character = try GuildPersistenceBridge.fetchCharacterEntity(
            characterId: characterId,
            in: context
        )
        guard character.currentHP == 0 else {
            throw GuildRepositoryError.characterNotDefeated(characterId: characterId)
        }

        try GuildPersistenceBridge.restoreCurrentHPToMax(of: character, masterData: masterData)
        try context.save()
        return try loadSnapshot()
    }

    func reviveAllDefeated(masterData: MasterData) throws -> GuildRosterSnapshot {
        let context = container.viewContext
        let characters = try GuildPersistenceBridge.fetchCharacters(in: context)

        for character in characters where character.currentHP == 0 {
            try GuildPersistenceBridge.restoreCurrentHPToMax(of: character, masterData: masterData)
        }

        if context.hasChanges {
            try context.save()
        }
        return try loadSnapshot()
    }

    func setAutoReviveDefeatedCharactersEnabled(_ isEnabled: Bool) throws -> GuildRosterSnapshot {
        let context = container.viewContext
        let playerState = try GuildPersistenceBridge.fetchOrCreatePlayerState(in: context)
        playerState.autoReviveDefeatedCharacters = isEnabled
        try context.save()
        return try loadSnapshot()
    }
}

@MainActor
final class PartyRepository {
    private let container: NSPersistentContainer
    private let explorationCoreDataStore: ExplorationCoreDataStore

    init(container: NSPersistentContainer) {
        self.container = container
        explorationCoreDataStore = ExplorationCoreDataStore(container: container)
    }

    func loadParties() throws -> [PartyRecord] {
        let context = container.viewContext
        let parties = try GuildPersistenceBridge.fetchOrCreateInitialParties(in: context)

        if context.hasChanges {
            try context.save()
        }

        return parties.map(GuildPersistenceBridge.makePartyRecord)
    }

    func unlockParty() throws {
        let context = container.viewContext
        let playerState = try GuildPersistenceBridge.fetchOrCreatePlayerState(in: context)
        let parties = try GuildPersistenceBridge.fetchOrCreateInitialParties(in: context)

        guard parties.count < PartyRecord.maxPartyCount else {
            throw GuildRepositoryError.maxPartyCountReached
        }

        let availableGold = Int(playerState.gold)
        guard availableGold >= PartyRecord.unlockCost else {
            throw GuildRepositoryError.insufficientGold(
                required: PartyRecord.unlockCost,
                available: availableGold
            )
        }

        let nextPartyId = parties.count + 1
        _ = try GuildPersistenceBridge.insertPartyEntity(
            partyId: nextPartyId,
            name: PartyRecord.defaultName(for: nextPartyId),
            memberCharacterIds: [],
            selectedLabyrinthId: nil,
            in: context
        )

        playerState.gold -= Int64(PartyRecord.unlockCost)
        try context.save()
    }

    func renameParty(partyId: Int, name: String) throws {
        let context = container.viewContext
        let normalizedName = PartyRecord.normalizedName(name)
        guard !normalizedName.isEmpty else {
            throw GuildRepositoryError.invalidPartyName
        }

        let party = try GuildPersistenceBridge.fetchPartyEntity(partyId: partyId, in: context)
        party.name = normalizedName
        try context.save()
    }

    func setSelectedLabyrinth(partyId: Int, selectedLabyrinthId: Int?) async throws {
        let context = container.viewContext
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        let party = try GuildPersistenceBridge.fetchPartyEntity(partyId: partyId, in: context)
        party.selectedLabyrinthId = selectedLabyrinthId.map(Int64.init) ?? 0
        try context.save()
    }

    func addCharacter(characterId: Int, toParty partyId: Int) async throws {
        let context = container.viewContext
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        let parties = try GuildPersistenceBridge.fetchOrCreateInitialParties(in: context)
        guard try GuildPersistenceBridge.characterExists(characterId: characterId, in: context) else {
            throw GuildRepositoryError.characterNotFound(characterId: characterId)
        }

        guard let targetParty = parties.first(where: { Int($0.partyId) == partyId }) else {
            throw GuildRepositoryError.invalidParty(partyId: partyId)
        }

        var targetMembers = GuildPersistenceBridge.memberCharacterIds(from: targetParty)
        if targetMembers.contains(characterId) {
            return
        }

        guard targetMembers.count < PartyRecord.memberLimit else {
            throw GuildRepositoryError.partyFull(partyId: partyId)
        }

        if let sourceParty = parties.first(where: {
            Int($0.partyId) != partyId
                && GuildPersistenceBridge.memberCharacterIds(from: $0).contains(characterId)
        }) {
            var sourceMembers = GuildPersistenceBridge.memberCharacterIds(from: sourceParty)
            sourceMembers.removeAll { $0 == characterId }
            GuildPersistenceBridge.setMemberCharacterIds(sourceMembers, on: sourceParty)
        }

        targetMembers.append(characterId)
        GuildPersistenceBridge.setMemberCharacterIds(targetMembers, on: targetParty)
        try context.save()
    }

    func removeCharacter(characterId: Int, fromParty partyId: Int) async throws {
        let context = container.viewContext
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        let party = try GuildPersistenceBridge.fetchPartyEntity(partyId: partyId, in: context)
        var members = GuildPersistenceBridge.memberCharacterIds(from: party)
        members.removeAll { $0 == characterId }
        GuildPersistenceBridge.setMemberCharacterIds(members, on: party)
        try context.save()
    }

    func replacePartyMembers(partyId: Int, memberCharacterIds: [Int]) async throws {
        let context = container.viewContext
        try await explorationCoreDataStore.validatePartyMutationIsAllowed(partyId: partyId)
        let party = try GuildPersistenceBridge.fetchPartyEntity(partyId: partyId, in: context)
        let existingMembers = GuildPersistenceBridge.memberCharacterIds(from: party)

        guard memberCharacterIds.count <= PartyRecord.memberLimit,
              Set(memberCharacterIds) == Set(existingMembers),
              memberCharacterIds.count == existingMembers.count else {
            throw GuildRepositoryError.invalidPartyMemberOrder
        }

        GuildPersistenceBridge.setMemberCharacterIds(memberCharacterIds, on: party)
        try context.save()
    }
}

@MainActor
final class EquipmentRepository {
    private let container: NSPersistentContainer
    private let explorationCoreDataStore: ExplorationCoreDataStore

    init(container: NSPersistentContainer) {
        self.container = container
        explorationCoreDataStore = ExplorationCoreDataStore(container: container)
    }

    func loadInventoryStacks() throws -> [CompositeItemStack] {
        let context = container.viewContext
        return try GuildPersistenceBridge.fetchInventoryItemEntities(in: context)
            .compactMap(GuildPersistenceBridge.makeInventoryStack)
            .sorted { $0.itemID.isOrdered(before: $1.itemID) }
    }

    func addInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        masterData: MasterData
    ) throws {
        guard !inventoryStacks.isEmpty else {
            return
        }

        let context = container.viewContext
        let aggregatedCounts = try GuildPersistenceBridge.aggregatedInventoryCounts(
            from: inventoryStacks,
            masterData: masterData
        )
        var inventoryEntitiesByKey: [String: InventoryItemEntity] = try Dictionary(
            uniqueKeysWithValues: GuildPersistenceBridge.fetchInventoryItemEntities(in: context).compactMap {
                guard let rawValue = $0.stackKeyRawValue else {
                    return nil
                }
                return (rawValue, $0)
            }
        )

        for (itemID, count) in aggregatedCounts {
            let inventoryEntity: InventoryItemEntity
            if let existingEntity = inventoryEntitiesByKey[itemID.rawValue] {
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
                inventoryEntitiesByKey[itemID.rawValue] = insertedEntity
                inventoryEntity = insertedEntity
            }

            inventoryEntity.count += Int64(count)
        }

        try context.save()
    }

    func equip(
        itemID: CompositeItemID,
        toCharacter characterId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildRepositoryError.invalidItemStack
        }

        let context = container.viewContext
        let character = try GuildPersistenceBridge.fetchCharacterEntity(
            characterId: characterId,
            in: context
        )
        guard let inventoryEntity = try GuildPersistenceBridge.fetchInventoryItemEntity(
            itemID: itemID,
            in: context
        ), inventoryEntity.count > 0 else {
            throw GuildRepositoryError.inventoryItemUnavailable
        }

        var equippedItemStacks = GuildPersistenceBridge.equippedItemStacks(from: character)
        let maximumCount = GuildPersistenceBridge.maximumEquippedItemCount(level: Int(character.level))
        let equippedCount = equippedItemStacks.reduce(into: 0) { partialResult, stack in
            partialResult += stack.count
        }
        guard equippedCount < maximumCount else {
            throw GuildRepositoryError.equipLimitReached(maximumCount: maximumCount)
        }

        equippedItemStacks = (equippedItemStacks + [CompositeItemStack(itemID: itemID, count: 1)])
            .normalizedCompositeItemStacks()
        GuildPersistenceBridge.setEquippedItemStacks(equippedItemStacks, on: character)

        inventoryEntity.count -= 1
        if inventoryEntity.count == 0 {
            context.delete(inventoryEntity)
        }

        GuildPersistenceBridge.clampCurrentHP(of: character, masterData: masterData)
        try context.save()
        return GuildPersistenceBridge.makeCharacterRecord(from: character)
    }

    func unequip(
        itemID: CompositeItemID,
        fromCharacter characterId: Int,
        masterData: MasterData
    ) async throws -> CharacterRecord {
        try await explorationCoreDataStore.validateCharacterMutationIsAllowed(characterId: characterId)
        guard itemID.isValid(in: masterData) else {
            throw GuildRepositoryError.invalidItemStack
        }

        let context = container.viewContext
        let character = try GuildPersistenceBridge.fetchCharacterEntity(
            characterId: characterId,
            in: context
        )
        var equippedItemStacks = GuildPersistenceBridge.equippedItemStacks(from: character)
        guard let index = equippedItemStacks.firstIndex(where: { $0.itemID == itemID }) else {
            throw GuildRepositoryError.equippedItemNotFound
        }

        let targetStack = equippedItemStacks[index]
        if targetStack.count == 1 {
            equippedItemStacks.remove(at: index)
        } else {
            equippedItemStacks[index] = CompositeItemStack(itemID: itemID, count: targetStack.count - 1)
        }
        GuildPersistenceBridge.setEquippedItemStacks(equippedItemStacks, on: character)

        let inventoryEntity: InventoryItemEntity
        if let existingEntity = try GuildPersistenceBridge.fetchInventoryItemEntity(
            itemID: itemID,
            in: context
        ) {
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
            inventoryEntity = insertedEntity
        }
        inventoryEntity.count += 1

        GuildPersistenceBridge.clampCurrentHP(of: character, masterData: masterData)
        try context.save()
        return GuildPersistenceBridge.makeCharacterRecord(from: character)
    }
}

private enum GuildPersistenceBridge {
    static func fetchOrCreatePlayerState(
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

    static func fetchOrCreateInitialParties(
        in context: NSManagedObjectContext
    ) throws -> [PartyEntity] {
        let parties = try fetchPartyEntities(in: context)
        if !parties.isEmpty {
            return parties
        }

        _ = try insertPartyEntity(
            partyId: 1,
            name: PartyRecord.defaultName(for: 1),
            memberCharacterIds: [],
            selectedLabyrinthId: nil,
            in: context
        )
        return try fetchPartyEntities(in: context)
    }

    static func fetchCharacters(
        in context: NSManagedObjectContext
    ) throws -> [CharacterEntity] {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "characterId", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchCharacterEntity(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> CharacterEntity {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "characterId == %d", characterId)

        guard let character = try context.fetch(request).first else {
            throw GuildRepositoryError.characterNotFound(characterId: characterId)
        }

        return character
    }

    static func fetchInventoryItemEntities(
        in context: NSManagedObjectContext
    ) throws -> [InventoryItemEntity] {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "stackKeyRawValue", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchInventoryItemEntity(
        itemID: CompositeItemID,
        in context: NSManagedObjectContext
    ) throws -> InventoryItemEntity? {
        let request = NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "stackKeyRawValue == %@", itemID.rawValue)
        return try context.fetch(request).first
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
        _ = try fetchOrCreateInitialParties(in: context)
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "partyId == %d", partyId)

        guard let party = try context.fetch(request).first else {
            throw GuildRepositoryError.invalidParty(partyId: partyId)
        }

        return party
    }

    static func characterExists(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "CharacterEntity")
        request.fetchLimit = 1
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "characterId == %d", characterId)
        return try !context.fetch(request).isEmpty
    }

    static func insertPartyEntity(
        partyId: Int,
        name: String,
        memberCharacterIds: [Int],
        selectedLabyrinthId: Int?,
        in context: NSManagedObjectContext
    ) throws -> PartyEntity {
        guard let party = NSEntityDescription.insertNewObject(
            forEntityName: "PartyEntity",
            into: context
        ) as? PartyEntity else {
            fatalError("PartyEntity の生成に失敗しました。")
        }

        party.partyId = Int64(partyId)
        party.name = name
        party.selectedLabyrinthId = selectedLabyrinthId.map(Int64.init) ?? 0
        setMemberCharacterIds(memberCharacterIds, on: party)
        return party
    }

    static func apply(_ character: CharacterRecord, to entity: CharacterEntity) {
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

    static func makePartyRecord(from entity: PartyEntity) -> PartyRecord {
        PartyRecord(
            partyId: Int(entity.partyId),
            name: entity.name ?? PartyRecord.defaultName(for: Int(entity.partyId)),
            memberCharacterIds: memberCharacterIds(from: entity),
            selectedLabyrinthId: entity.selectedLabyrinthId == 0 ? nil : Int(entity.selectedLabyrinthId)
        )
    }

    static func makeInventoryStack(from entity: InventoryItemEntity) -> CompositeItemStack? {
        guard let rawValue = entity.stackKeyRawValue,
              let itemID = CompositeItemID(rawValue: rawValue),
              entity.count > 0 else {
            return nil
        }

        return CompositeItemStack(itemID: itemID, count: Int(entity.count))
    }

    static func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        (entity.memberCharacterIdsRawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    static func setMemberCharacterIds(_ memberCharacterIds: [Int], on entity: PartyEntity) {
        entity.memberCharacterIdsRawValue = memberCharacterIds.map(String.init).joined(separator: ",")
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

    static func setEquippedItemStacks(
        _ equippedItemStacks: [CompositeItemStack],
        on entity: CharacterEntity
    ) {
        entity.equippedItemStacksRawValue = equippedItemStacks
            .normalizedCompositeItemStacks()
            .map { "\($0.itemID.rawValue)#\($0.count)" }
            .joined(separator: "|")
    }

    static func maximumEquippedItemCount(level: Int) -> Int {
        3 + Int((Double(level) / 20).rounded())
    }

    static func clampCurrentHP(
        of entity: CharacterEntity,
        masterData: MasterData
    ) {
        let character = makeCharacterRecord(from: entity)
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            return
        }

        entity.currentHP = Int64(min(max(Int(entity.currentHP), 0), status.maxHP))
    }

    static func restoreCurrentHPToMax(
        of entity: CharacterEntity,
        masterData: MasterData
    ) throws {
        let character = makeCharacterRecord(from: entity)
        guard let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) else {
            throw ExplorationError.invalidRunMember(characterId: Int(entity.characterId))
        }

        entity.currentHP = Int64(status.maxHP)
    }

    static func aggregatedInventoryCounts(
        from inventoryStacks: [CompositeItemStack],
        masterData: MasterData
    ) throws -> [CompositeItemID: Int] {
        var aggregatedCounts: [CompositeItemID: Int] = [:]
        aggregatedCounts.reserveCapacity(inventoryStacks.count)

        for stack in inventoryStacks {
            guard stack.count > 0 else {
                throw GuildRepositoryError.invalidStackCount
            }
            guard stack.itemID.isValid(in: masterData) else {
                throw GuildRepositoryError.invalidItemStack
            }

            aggregatedCounts[stack.itemID, default: 0] += stack.count
        }

        return aggregatedCounts
    }
}
