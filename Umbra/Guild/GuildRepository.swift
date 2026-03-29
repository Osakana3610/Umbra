// Persists player state and characters, and performs hire transactions.

import CoreData
import Foundation

struct HireCharacterResult: Sendable {
    let playerState: PlayerState
    let character: CharacterRecord
    let hireCost: Int
}

enum GuildRepositoryError: LocalizedError {
    case invalidHireSelection
    case insufficientGold(required: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .invalidHireSelection:
            return "雇用条件が不正です。"
        case let .insufficientGold(required, available):
            return "所持金が不足しています。必要=\(required) 現在=\(available)"
        }
    }
}

@MainActor
final class GuildRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func loadPlayerState() throws -> PlayerState {
        let context = container.viewContext
        let playerState = try Self.fetchOrCreatePlayerState(in: context)

        if context.hasChanges {
            try context.save()
        }

        return PlayerState(
            gold: Int(playerState.gold),
            nextCharacterId: Int(playerState.nextCharacterId)
        )
    }

    func loadCharacters() throws -> [CharacterRecord] {
        let context = container.viewContext
        return try Self.fetchCharacters(in: context).map(Self.makeCharacterRecord)
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

    private static func fetchCharacters(
        in context: NSManagedObjectContext
    ) throws -> [CharacterEntity] {
        let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "characterId", ascending: true)
        ]
        return try context.fetch(request)
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
}
