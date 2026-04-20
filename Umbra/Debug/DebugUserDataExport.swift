// Encodes the current persisted user state into a shareable JSON document for debugging.

import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct DebugUserDataExporter {
    let container: NSPersistentContainer
    let masterData: MasterData

    func makeDocument() async throws -> DebugUserDataDocument {
        // Export on a background context so a full snapshot does not block the debug menu while
        // Core Data resolves relationships.
        let context = container.newBackgroundContext()
        let lookup = DebugUserDataLookup(masterData: masterData)
        let snapshot = try await context.perform {
            try makeSnapshot(in: context, lookup: lookup)
        }
        return try DebugUserDataDocument(snapshot: snapshot)
    }

    private func makeSnapshot(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> DebugUserDataSnapshot {
        let playerState = try fetchPlayerState(in: context, lookup: lookup)
        let characters = try fetchCharacters(in: context, lookup: lookup)
        let inventory = try fetchInventory(in: context, lookup: lookup)
        let parties = try fetchParties(in: context, lookup: lookup)
        let labyrinthProgress = try fetchLabyrinthProgress(in: context, lookup: lookup)
        let runSessions = try fetchRunSessions(in: context, lookup: lookup)

        return DebugUserDataSnapshot(
            exportedAt: Date(),
            playerState: playerState,
            characters: characters,
            inventory: inventory,
            parties: parties,
            labyrinthProgress: labyrinthProgress,
            runSessions: runSessions
        )
    }

    private func fetchPlayerState(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> DebugUserDataSnapshot.PlayerStatePayload? {
        let request = PlayerStateEntity.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first.map { entity in
            DebugUserDataSnapshot.PlayerStatePayload(
                gold: Int(entity.gold),
                catTicketCount: Int(entity.catTicketCount),
                nextCharacterId: Int(entity.nextCharacterId),
                autoReviveDefeatedCharacters: entity.autoReviveDefeatedCharacters,
                autoSellItems: (entity.autoSellItems as? Set<PlayerStateAutoSellItemEntity> ?? [])
                    .map { CompositeItemID(entity: $0) }
                    .sorted { $0.isOrdered(before: $1) }
                    .map { makeCompositeItemPayload(itemID: $0, lookup: lookup) },
                lastBackgroundedAt: entity.lastBackgroundedAt
            )
        }
    }

    private func fetchCharacters(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> [DebugUserDataSnapshot.CharacterPayload] {
        let request = CharacterEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "characterId", ascending: true)]
        return try context.fetch(request).map { entity in
            DebugUserDataSnapshot.CharacterPayload(
                characterId: Int(entity.characterId),
                name: entity.name ?? "",
                raceId: Int(entity.raceId),
                raceName: lookup.raceName(for: Int(entity.raceId)),
                previousJobId: Int(entity.previousJobId),
                previousJobName: lookup.jobName(optional: Int(entity.previousJobId)),
                currentJobId: Int(entity.currentJobId),
                currentJobName: lookup.jobName(for: Int(entity.currentJobId)),
                aptitudeId: Int(entity.aptitudeId),
                aptitudeName: lookup.aptitudeName(for: Int(entity.aptitudeId)),
                level: Int(entity.level),
                experience: Int(entity.experience),
                currentHP: Int(entity.currentHP),
                portraitVariant: Int(entity.portraitVariant),
                equippedItems: makeCharacterEquippedItems(from: entity, lookup: lookup),
                autoBattleSettings: .init(
                    breath: Int(entity.breathRate),
                    attack: Int(entity.attackRate),
                    recoverySpell: Int(entity.recoverySpellRate),
                    attackSpell: Int(entity.attackSpellRate),
                    priority: actionPriorityLabels(
                        from: [
                            entity.actionPriorityPrimaryValue,
                            entity.actionPrioritySecondaryValue,
                            entity.actionPriorityTertiaryValue,
                            entity.actionPriorityQuaternaryValue
                        ]
                    )
                )
            )
        }
    }

    private func fetchInventory(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> [DebugUserDataSnapshot.InventoryPayload] {
        let request = InventoryItemEntity.fetchRequest()
        request.sortDescriptors = CompositeItemPersistence.sortDescriptors
        return try context.fetch(request).map { entity in
            let itemID = CompositeItemID(entity: entity)
            return DebugUserDataSnapshot.InventoryPayload(
                count: Int(entity.count),
                item: makeCompositeItemStackPayload(itemID: itemID, count: Int(entity.count), lookup: lookup)
            )
        }
    }

    private func fetchParties(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> [DebugUserDataSnapshot.PartyPayload] {
        let request = PartyEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "partyId", ascending: true)]
        return try context.fetch(request).map { entity in
            let selectedLabyrinthId = Int(entity.selectedLabyrinthId)
            let selectedDifficultyTitleId = Int(entity.selectedDifficultyTitleId)
            return DebugUserDataSnapshot.PartyPayload(
                partyId: Int(entity.partyId),
                name: entity.name ?? "",
                memberCharacterIdsRawValue: entity.memberCharacterIdsRawValue ?? "",
                memberCharacterIds: parseIntegerList(rawValue: entity.memberCharacterIdsRawValue),
                selectedLabyrinthId: selectedLabyrinthId,
                selectedLabyrinthName: lookup.labyrinthName(optional: selectedLabyrinthId),
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                selectedDifficultyTitleName: lookup.titleName(optional: selectedDifficultyTitleId),
                automaticallyUsesCatTicket: entity.automaticallyUsesCatTicket,
                pendingAutomaticRunCount: Int(entity.pendingAutomaticRunCount),
                pendingAutomaticRunStartedAt: entity.pendingAutomaticRunStartedAt
            )
        }
    }

    private func fetchLabyrinthProgress(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> [DebugUserDataSnapshot.LabyrinthProgressPayload] {
        let request = LabyrinthProgressEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "labyrinthId", ascending: true)]
        return try context.fetch(request).map { entity in
            let labyrinthId = Int(entity.labyrinthId)
            let highestUnlockedDifficultyTitleId = Int(entity.highestUnlockedDifficultyTitleId)
            return DebugUserDataSnapshot.LabyrinthProgressPayload(
                labyrinthId: labyrinthId,
                labyrinthName: lookup.labyrinthName(optional: labyrinthId),
                highestUnlockedDifficultyTitleId: highestUnlockedDifficultyTitleId,
                highestUnlockedDifficultyTitleName: lookup.titleName(optional: highestUnlockedDifficultyTitleId)
            )
        }
    }

    private func fetchRunSessions(
        in context: NSManagedObjectContext,
        lookup: DebugUserDataLookup
    ) throws -> [DebugUserDataSnapshot.RunSessionPayload] {
        let request = RunSessionEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "partyId", ascending: true),
            NSSortDescriptor(key: "partyRunId", ascending: true)
        ]
        return try context.fetch(request).map { entity in
            let labyrinthId = Int(entity.labyrinthId)
            let selectedDifficultyTitleId = Int(entity.selectedDifficultyTitleId)
            let members = (entity.members as? Set<RunSessionMemberEntity> ?? [])
                .sorted { lhs, rhs in
                    lhs.formationIndex < rhs.formationIndex
                }
                .map { member in
                    DebugUserDataSnapshot.RunSessionMemberPayload(
                        formationIndex: Int(member.formationIndex),
                        characterId: Int(member.characterId),
                        name: member.name ?? "",
                        raceId: Int(member.raceId),
                        raceName: lookup.raceName(for: Int(member.raceId)),
                        previousJobId: Int(member.previousJobId),
                        previousJobName: lookup.jobName(optional: Int(member.previousJobId)),
                        currentJobId: Int(member.currentJobId),
                        currentJobName: lookup.jobName(for: Int(member.currentJobId)),
                        aptitudeId: Int(member.aptitudeId),
                        aptitudeName: lookup.aptitudeName(for: Int(member.aptitudeId)),
                        level: Int(member.level),
                        experience: Int(member.experience),
                        currentHP: Int(member.currentHP),
                        experienceMultiplier: member.experienceMultiplier,
                        equippedItems: makeRunSessionMemberEquippedItems(from: member, lookup: lookup),
                        autoBattleSettings: .init(
                            breath: Int(member.breathRate),
                            attack: Int(member.attackRate),
                            recoverySpell: Int(member.recoverySpellRate),
                            attackSpell: Int(member.attackSpellRate),
                            priority: actionPriorityLabels(
                                from: [
                                    member.actionPriorityPrimaryValue,
                                    member.actionPrioritySecondaryValue,
                                    member.actionPriorityTertiaryValue,
                                    member.actionPriorityQuaternaryValue
                                ]
                            )
                        )
                    )
                }

            return DebugUserDataSnapshot.RunSessionPayload(
                partyId: Int(entity.partyId),
                partyRunId: Int(entity.partyRunId),
                labyrinthId: labyrinthId,
                labyrinthName: lookup.labyrinthName(optional: labyrinthId),
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                selectedDifficultyTitleName: lookup.explorationDifficultyName(for: selectedDifficultyTitleId),
                targetFloorNumber: Int(entity.targetFloorNumber),
                startedAt: entity.startedAt,
                completedAt: entity.completedAt,
                completedBattleCount: Int(entity.completedBattleCount),
                latestBattleFloorNumber: Int(entity.latestBattleFloorNumber),
                latestBattleNumber: Int(entity.latestBattleNumber),
                latestBattleOutcomeValue: Int(entity.latestBattleOutcomeValue),
                completionReasonValue: Int(entity.completionReasonValue),
                goldBuffer: Int(entity.goldBuffer),
                progressIntervalMultiplier: entity.progressIntervalMultiplier,
                goldMultiplier: entity.goldMultiplier,
                rareDropMultiplier: entity.rareDropMultiplier,
                partyAverageLuck: entity.partyAverageLuck,
                rewardsApplied: entity.rewardsApplied,
                rootSeedSigned: entity.rootSeedSigned,
                members: members
            )
        }
    }

    private func makeCharacterEquippedItems(
        from entity: CharacterEntity,
        lookup: DebugUserDataLookup
    ) -> [DebugUserDataSnapshot.CompositeItemStackPayload] {
        let equippedItems = (entity.equippedItems as? Set<CharacterEquippedItemEntity> ?? [])
            .sorted { Int($0.stackIndex) < Int($1.stackIndex) }
        return equippedItems.compactMap { itemEntity in
            guard itemEntity.count > 0 else {
                return nil
            }

            return makeCompositeItemStackPayload(
                itemID: CompositeItemID(entity: itemEntity),
                count: Int(itemEntity.count),
                lookup: lookup
            )
        }
    }

    private func makeRunSessionMemberEquippedItems(
        from entity: RunSessionMemberEntity,
        lookup: DebugUserDataLookup
    ) -> [DebugUserDataSnapshot.CompositeItemStackPayload] {
        let equippedItems = (entity.equippedItems as? Set<RunSessionMemberEquippedItemEntity> ?? [])
            .sorted { Int($0.stackIndex) < Int($1.stackIndex) }
        return equippedItems.compactMap { itemEntity in
            guard itemEntity.count > 0 else {
                return nil
            }

            return makeCompositeItemStackPayload(
                itemID: CompositeItemID(entity: itemEntity),
                count: Int(itemEntity.count),
                lookup: lookup
            )
        }
    }

    private func makeCompositeItemStackPayload(
        itemID: CompositeItemID,
        count: Int,
        lookup: DebugUserDataLookup
    ) -> DebugUserDataSnapshot.CompositeItemStackPayload {
        DebugUserDataSnapshot.CompositeItemStackPayload(
            count: count,
            item: makeCompositeItemPayload(itemID: itemID, lookup: lookup)
        )
    }

    private func makeCompositeItemPayload(
        itemID: CompositeItemID,
        lookup: DebugUserDataLookup
    ) -> DebugUserDataSnapshot.CompositeItemPayload {
        DebugUserDataSnapshot.CompositeItemPayload(
            rawValue: itemID.rawValue,
            displayName: lookup.displayName(for: itemID),
            baseItemId: itemID.baseItemId,
            baseItemName: lookup.itemName(optional: itemID.baseItemId),
            baseTitleId: itemID.baseTitleId,
            baseTitleName: lookup.titleName(optional: itemID.baseTitleId),
            baseSuperRareId: itemID.baseSuperRareId,
            baseSuperRareName: lookup.superRareName(optional: itemID.baseSuperRareId),
            jewelItemId: itemID.jewelItemId,
            jewelItemName: lookup.itemName(optional: itemID.jewelItemId),
            jewelTitleId: itemID.jewelTitleId,
            jewelTitleName: lookup.titleName(optional: itemID.jewelTitleId),
            jewelSuperRareId: itemID.jewelSuperRareId,
            jewelSuperRareName: lookup.superRareName(optional: itemID.jewelSuperRareId)
        )
    }

    private func parseIntegerList(rawValue: String?) -> [Int] {
        (rawValue ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    private func actionPriorityLabels(from persistedValues: [Int64]) -> [String] {
        CharacterAutoBattleSettings.decodedPriority(from: persistedValues)
            .map { String(describing: $0) }
    }
}

nonisolated struct DebugUserDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(snapshot: DebugUserDataSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        data = try encoder.encode(snapshot)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct DebugUserDataSnapshot: Codable, Sendable {
    let exportedAt: Date
    let playerState: PlayerStatePayload?
    let characters: [CharacterPayload]
    let inventory: [InventoryPayload]
    let parties: [PartyPayload]
    let labyrinthProgress: [LabyrinthProgressPayload]
    let runSessions: [RunSessionPayload]

    nonisolated struct PlayerStatePayload: Codable, Sendable {
        let gold: Int
        let catTicketCount: Int
        let nextCharacterId: Int
        let autoReviveDefeatedCharacters: Bool
        let autoSellItems: [CompositeItemPayload]
        let lastBackgroundedAt: Date?
    }

    nonisolated struct CharacterPayload: Codable, Sendable {
        let characterId: Int
        let name: String
        let raceId: Int
        let raceName: String
        let previousJobId: Int
        let previousJobName: String?
        let currentJobId: Int
        let currentJobName: String
        let aptitudeId: Int
        let aptitudeName: String
        let level: Int
        let experience: Int
        let currentHP: Int
        let portraitVariant: Int
        let equippedItems: [CompositeItemStackPayload]
        let autoBattleSettings: AutoBattleSettingsPayload
    }

    nonisolated struct InventoryPayload: Codable, Sendable {
        let count: Int
        let item: CompositeItemStackPayload
    }

    nonisolated struct PartyPayload: Codable, Sendable {
        let partyId: Int
        let name: String
        let memberCharacterIdsRawValue: String
        let memberCharacterIds: [Int]
        let selectedLabyrinthId: Int
        let selectedLabyrinthName: String?
        let selectedDifficultyTitleId: Int
        let selectedDifficultyTitleName: String?
        let automaticallyUsesCatTicket: Bool
        let pendingAutomaticRunCount: Int
        let pendingAutomaticRunStartedAt: Date?
    }

    nonisolated struct LabyrinthProgressPayload: Codable, Sendable {
        let labyrinthId: Int
        let labyrinthName: String?
        let highestUnlockedDifficultyTitleId: Int
        let highestUnlockedDifficultyTitleName: String?
    }

    nonisolated struct RunSessionPayload: Codable, Sendable {
        let partyId: Int
        let partyRunId: Int
        let labyrinthId: Int
        let labyrinthName: String?
        let selectedDifficultyTitleId: Int
        let selectedDifficultyTitleName: String
        let targetFloorNumber: Int
        let startedAt: Date?
        let completedAt: Date?
        let completedBattleCount: Int
        let latestBattleFloorNumber: Int
        let latestBattleNumber: Int
        let latestBattleOutcomeValue: Int
        let completionReasonValue: Int
        let goldBuffer: Int
        let progressIntervalMultiplier: Double
        let goldMultiplier: Double
        let rareDropMultiplier: Double
        let partyAverageLuck: Double
        let rewardsApplied: Bool
        let rootSeedSigned: Int64
        let members: [RunSessionMemberPayload]
    }

    nonisolated struct RunSessionMemberPayload: Codable, Sendable {
        let formationIndex: Int
        let characterId: Int
        let name: String
        let raceId: Int
        let raceName: String
        let previousJobId: Int
        let previousJobName: String?
        let currentJobId: Int
        let currentJobName: String
        let aptitudeId: Int
        let aptitudeName: String
        let level: Int
        let experience: Int
        let currentHP: Int
        let experienceMultiplier: Double
        let equippedItems: [CompositeItemStackPayload]
        let autoBattleSettings: AutoBattleSettingsPayload
    }

    nonisolated struct AutoBattleSettingsPayload: Codable, Sendable {
        let breath: Int
        let attack: Int
        let recoverySpell: Int
        let attackSpell: Int
        let priority: [String]
    }

    nonisolated struct CompositeItemStackPayload: Codable, Sendable {
        let count: Int
        let item: CompositeItemPayload
    }

    nonisolated struct CompositeItemPayload: Codable, Sendable {
        let rawValue: String
        let displayName: String
        let baseItemId: Int
        let baseItemName: String?
        let baseTitleId: Int
        let baseTitleName: String?
        let baseSuperRareId: Int
        let baseSuperRareName: String?
        let jewelItemId: Int
        let jewelItemName: String?
        let jewelTitleId: Int
        let jewelTitleName: String?
        let jewelSuperRareId: Int
        let jewelSuperRareName: String?
    }
}

nonisolated private struct DebugUserDataLookup {
    let raceNamesByID: [Int: String]
    let jobNamesByID: [Int: String]
    let aptitudeNamesByID: [Int: String]
    let itemNamesByID: [Int: String]
    let titleNamesByID: [Int: String]
    let superRareNamesByID: [Int: String]
    let labyrinthNamesByID: [Int: String]

    init(masterData: MasterData) {
        raceNamesByID = Dictionary(uniqueKeysWithValues: masterData.races.map { ($0.id, $0.name) })
        jobNamesByID = Dictionary(uniqueKeysWithValues: masterData.jobs.map { ($0.id, $0.name) })
        aptitudeNamesByID = Dictionary(uniqueKeysWithValues: masterData.aptitudes.map { ($0.id, $0.name) })
        itemNamesByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0.name) })
        titleNamesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0.name) })
        superRareNamesByID = Dictionary(uniqueKeysWithValues: masterData.superRares.map { ($0.id, $0.name) })
        labyrinthNamesByID = Dictionary(uniqueKeysWithValues: masterData.labyrinths.map { ($0.id, $0.name) })
    }

    func raceName(for id: Int) -> String {
        raceNamesByID[id] ?? "不明"
    }

    func jobName(for id: Int) -> String {
        jobNamesByID[id] ?? "不明"
    }

    func jobName(optional id: Int) -> String? {
        id > 0 ? jobName(for: id) : nil
    }

    func aptitudeName(for id: Int) -> String {
        aptitudeNamesByID[id] ?? "不明"
    }

    func itemName(optional id: Int) -> String? {
        id > 0 ? itemNamesByID[id] : nil
    }

    func titleName(optional id: Int) -> String? {
        id > 0 ? titleNamesByID[id] : nil
    }

    func superRareName(optional id: Int) -> String? {
        id > 0 ? superRareNamesByID[id] : nil
    }

    func labyrinthName(optional id: Int) -> String? {
        id > 0 ? labyrinthNamesByID[id] : nil
    }

    func explorationDifficultyName(for titleId: Int) -> String {
        if let titleName = titleName(optional: titleId), !titleName.isEmpty {
            return titleName
        }
        return "無称号"
    }

    func displayName(for itemID: CompositeItemID) -> String {
        let baseName = prefixedName(
            itemName: itemName(optional: itemID.baseItemId) ?? "不明なアイテム",
            titleName: titleName(optional: itemID.baseTitleId),
            superRareName: superRareName(optional: itemID.baseSuperRareId)
        )

        guard itemID.jewelItemId > 0 else {
            return baseName
        }

        let jewelName = prefixedName(
            itemName: itemName(optional: itemID.jewelItemId) ?? "不明な宝石",
            titleName: titleName(optional: itemID.jewelTitleId),
            superRareName: superRareName(optional: itemID.jewelSuperRareId)
        )
        return "\(baseName)[\(jewelName)]"
    }

    private func prefixedName(
        itemName: String,
        titleName: String?,
        superRareName: String?
    ) -> String {
        ([superRareName, titleName].compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        } + [itemName]).joined()
    }
}
