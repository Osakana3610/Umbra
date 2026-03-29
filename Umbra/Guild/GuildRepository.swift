// Persists player state and characters, and performs hire transactions.

import CoreData
import Foundation

struct GuildSnapshot: Sendable {
    let playerState: PlayerState
    let characters: [CharacterRecord]
    let parties: [PartyRecord]
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

    var errorDescription: String? {
        switch self {
        case .invalidHireSelection:
            return "雇用条件が不正です。"
        case let .insufficientGold(required, available):
            return "所持金が不足しています。必要=\(required) 現在=\(available)"
        case .maxPartyCountReached:
            return "これ以上パーティを解放できません。"
        case let .invalidParty(partyId):
            return "パーティが見つかりません。 partyId=\(partyId)"
        case .invalidPartyName:
            return "パーティ名を入力してください。"
        case let .partyFull(partyId):
            return "パーティ\(partyId)はすでに6人です。"
        case let .characterNotFound(characterId):
            return "キャラクターが見つかりません。 characterId=\(characterId)"
        case .invalidPartyMemberOrder:
            return "パーティ編成の並び順が不正です。"
        }
    }
}

@MainActor
final class GuildRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadSnapshot() throws -> GuildSnapshot {
        let context = container.viewContext
        let playerState = try Self.fetchOrCreatePlayerState(in: context)
        let partyEntities = try Self.fetchOrCreateInitialParties(in: context)

        if context.hasChanges {
            try context.save()
        }

        return GuildSnapshot(
            playerState: PlayerState(
                gold: Int(playerState.gold),
                nextCharacterId: Int(playerState.nextCharacterId)
            ),
            characters: try Self.fetchCharacters(in: context).map(Self.makeCharacterRecord),
            parties: partyEntities.map(Self.makePartyRecord)
        )
    }

    func loadPlayerState() throws -> PlayerState {
        try loadSnapshot().playerState
    }

    func loadCharacters() throws -> [CharacterRecord] {
        try loadSnapshot().characters
    }

    func loadParties() throws -> [PartyRecord] {
        try loadSnapshot().parties
    }

    func hireCharacter(
        raceId: Int,
        jobId: Int,
        aptitudeId: Int,
        masterData: MasterData
    ) throws -> HireCharacterResult {
        let context = container.viewContext
        let playerState = try Self.fetchOrCreatePlayerState(in: context)
        guard let hireCost = GuildHiring.price(
            raceId: raceId,
            jobId: jobId,
            masterData: masterData
        ) else {
            throw GuildRepositoryError.invalidHireSelection
        }

        let availableGold = Int(playerState.gold)
        guard availableGold >= hireCost else {
            throw GuildRepositoryError.insufficientGold(
                required: hireCost,
                available: availableGold
            )
        }

        let character = try GuildHiring.makeCharacterRecord(
            nextCharacterId: Int(playerState.nextCharacterId),
            raceId: raceId,
            jobId: jobId,
            aptitudeId: aptitudeId,
            masterData: masterData
        )

        guard let storedCharacter = NSEntityDescription.insertNewObject(
            forEntityName: "CharacterEntity",
            into: context
        ) as? CharacterEntity else {
            fatalError("CharacterEntity の生成に失敗しました。")
        }
        storedCharacter.characterId = Int64(character.characterId)
        storedCharacter.name = character.name
        storedCharacter.raceId = Int64(character.raceId)
        storedCharacter.previousJobId = Int64(character.previousJobId)
        storedCharacter.currentJobId = Int64(character.currentJobId)
        storedCharacter.aptitudeId = Int64(character.aptitudeId)
        storedCharacter.portraitVariant = Int64(character.portraitGender.rawValue)
        storedCharacter.experience = Int64(character.experience)
        storedCharacter.level = Int64(character.level)
        storedCharacter.currentHP = Int64(character.currentHP)
        storedCharacter.breathRate = Int64(character.autoBattleSettings.rates.breath)
        storedCharacter.attackRate = Int64(character.autoBattleSettings.rates.attack)
        storedCharacter.recoverySpellRate = Int64(character.autoBattleSettings.rates.recoverySpell)
        storedCharacter.attackSpellRate = Int64(character.autoBattleSettings.rates.attackSpell)
        storedCharacter.actionPriorityRawValue = character.autoBattleSettings.priority
            .map(\.rawValue)
            .joined(separator: ",")

        playerState.gold -= Int64(hireCost)
        playerState.nextCharacterId += 1

        try context.save()

        let updatedPlayerState = PlayerState(
            gold: Int(playerState.gold),
            nextCharacterId: Int(playerState.nextCharacterId)
        )

        return HireCharacterResult(
            playerState: updatedPlayerState,
            character: character,
            hireCost: hireCost
        )
    }

    func unlockParty() throws {
        let context = container.viewContext
        let playerState = try Self.fetchOrCreatePlayerState(in: context)
        let partyEntities = try Self.fetchOrCreateInitialParties(in: context)

        guard partyEntities.count < PartyRecord.maxPartyCount else {
            throw GuildRepositoryError.maxPartyCountReached
        }

        let availableGold = Int(playerState.gold)
        guard availableGold >= PartyRecord.unlockCost else {
            throw GuildRepositoryError.insufficientGold(
                required: PartyRecord.unlockCost,
                available: availableGold
            )
        }

        let nextPartyId = partyEntities.count + 1
        let newParty = try Self.insertPartyEntity(
            partyId: nextPartyId,
            name: PartyRecord.defaultName(for: nextPartyId),
            memberCharacterIds: [],
            in: context
        )
        _ = newParty

        playerState.gold -= Int64(PartyRecord.unlockCost)
        try context.save()
    }

    func renameParty(partyId: Int, name: String) throws {
        let context = container.viewContext
        let normalizedName = PartyRecord.normalizedName(name)
        guard !normalizedName.isEmpty else {
            throw GuildRepositoryError.invalidPartyName
        }

        let party = try Self.fetchPartyEntity(partyId: partyId, in: context)
        party.name = normalizedName
        try context.save()
    }

    func addCharacter(characterId: Int, toParty partyId: Int) throws {
        let context = container.viewContext
        let partyEntities = try Self.fetchOrCreateInitialParties(in: context)
        guard try Self.characterExists(characterId: characterId, in: context) else {
            throw GuildRepositoryError.characterNotFound(characterId: characterId)
        }

        guard let targetParty = partyEntities.first(where: { Int($0.partyId) == partyId }) else {
            throw GuildRepositoryError.invalidParty(partyId: partyId)
        }

        var targetMembers = Self.memberCharacterIds(from: targetParty)
        if targetMembers.contains(characterId) {
            return
        }

        guard targetMembers.count < PartyRecord.memberLimit else {
            throw GuildRepositoryError.partyFull(partyId: partyId)
        }

        if let sourceParty = partyEntities.first(where: {
            Int($0.partyId) != partyId && Self.memberCharacterIds(from: $0).contains(characterId)
        }) {
            var sourceMembers = Self.memberCharacterIds(from: sourceParty)
            sourceMembers.removeAll { $0 == characterId }
            Self.setMemberCharacterIds(sourceMembers, on: sourceParty)
        }

        targetMembers.append(characterId)
        Self.setMemberCharacterIds(targetMembers, on: targetParty)
        try context.save()
    }

    func removeCharacter(characterId: Int, fromParty partyId: Int) throws {
        let context = container.viewContext
        let party = try Self.fetchPartyEntity(partyId: partyId, in: context)
        var members = Self.memberCharacterIds(from: party)
        members.removeAll { $0 == characterId }
        Self.setMemberCharacterIds(members, on: party)
        try context.save()
    }

    func replacePartyMembers(partyId: Int, memberCharacterIds: [Int]) throws {
        let context = container.viewContext
        let party = try Self.fetchPartyEntity(partyId: partyId, in: context)
        let existingMembers = Self.memberCharacterIds(from: party)

        guard memberCharacterIds.count <= PartyRecord.memberLimit,
              Set(memberCharacterIds) == Set(existingMembers),
              memberCharacterIds.count == existingMembers.count else {
            throw GuildRepositoryError.invalidPartyMemberOrder
        }

        Self.setMemberCharacterIds(memberCharacterIds, on: party)
        try context.save()
    }

    private static func fetchOrCreatePlayerState(
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
        return playerState
    }

    private static func fetchOrCreateInitialParties(
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
            in: context
        )
        return try fetchPartyEntities(in: context)
    }

    private static func fetchCharacters(
        in context: NSManagedObjectContext
    ) throws -> [CharacterEntity] {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "characterId", ascending: true)
        ]
        return try context.fetch(request)
    }

    private static func fetchPartyEntities(
        in context: NSManagedObjectContext
    ) throws -> [PartyEntity] {
        let request = NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "partyId", ascending: true)
        ]
        return try context.fetch(request)
    }

    private static func fetchPartyEntity(
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

    private static func characterExists(
        characterId: Int,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "CharacterEntity")
        request.fetchLimit = 1
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "characterId == %d", characterId)
        return try !context.fetch(request).isEmpty
    }

    private static func insertPartyEntity(
        partyId: Int,
        name: String,
        memberCharacterIds: [Int],
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
        setMemberCharacterIds(memberCharacterIds, on: party)
        return party
    }

    private static func makeCharacterRecord(from entity: CharacterEntity) -> CharacterRecord {
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

    private static func makePartyRecord(from entity: PartyEntity) -> PartyRecord {
        PartyRecord(
            partyId: Int(entity.partyId),
            name: entity.name ?? PartyRecord.defaultName(for: Int(entity.partyId)),
            memberCharacterIds: memberCharacterIds(from: entity)
        )
    }

    private static func memberCharacterIds(from entity: PartyEntity) -> [Int] {
        (entity.memberCharacterIdsRawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    private static func setMemberCharacterIds(_ memberCharacterIds: [Int], on entity: PartyEntity) {
        entity.memberCharacterIdsRawValue = memberCharacterIds.map(String.init).joined(separator: ",")
    }
}
