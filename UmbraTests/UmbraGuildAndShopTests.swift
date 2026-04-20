// Verifies guild-side mutations that affect roster state, party composition, equipment, inventory,
// shop flows, and debug generation helpers.
// These tests focus on persistence-backed state transitions where one action can touch several
// stores at once and regressions are hard to spot from UI behavior alone.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraGuildAndShopTests {
    @Test
    func jewelEnhancementAddsFullJewelBaseStatsAndHalfBattleStats() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let baseItem = try #require(masterData.items.first(where: { $0.category != .jewel }))
        let jewelItem = try #require(masterData.items.first(where: { $0.category == .jewel }))
        let baseItemID = CompositeItemID.baseItem(itemId: baseItem.id)
        let jewelItemID = CompositeItemID.baseItem(itemId: jewelItem.id)

        try guildServices.inventory.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 1),
                CompositeItemStack(itemID: jewelItemID, count: 1)
            ],
            masterData: masterData
        )

        try await guildServices.equipment.enhanceWithJewel(
            baseItemID: baseItemID,
            baseCharacterId: nil,
            jewelItemID: jewelItemID,
            jewelCharacterId: nil,
            masterData: masterData
        )

        let resultItemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 0,
            baseItemId: baseItem.id,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: jewelItem.id
        )
        let resolution = try EquipmentResolver(masterData: masterData).resolve(
            equippedItemStacks: [CompositeItemStack(itemID: resultItemID, count: 1)]
        )

        #expect(try guildCoreDataRepository.loadInventoryStacks() == [
            CompositeItemStack(itemID: resultItemID, count: 1)
        ])
        #expect(resolution.baseStats == CharacterBaseStats(
            vitality: baseItem.nativeBaseStats.vitality + jewelItem.nativeBaseStats.vitality,
            strength: baseItem.nativeBaseStats.strength + jewelItem.nativeBaseStats.strength,
            mind: baseItem.nativeBaseStats.mind + jewelItem.nativeBaseStats.mind,
            intelligence: baseItem.nativeBaseStats.intelligence + jewelItem.nativeBaseStats.intelligence,
            agility: baseItem.nativeBaseStats.agility + jewelItem.nativeBaseStats.agility,
            luck: baseItem.nativeBaseStats.luck + jewelItem.nativeBaseStats.luck
        ))
        #expect(resolution.battleStats == CharacterBattleStats(
            maxHP: baseItem.nativeBattleStats.maxHP + (jewelItem.nativeBattleStats.maxHP / 2),
            physicalAttack: baseItem.nativeBattleStats.physicalAttack + (jewelItem.nativeBattleStats.physicalAttack / 2),
            physicalDefense: baseItem.nativeBattleStats.physicalDefense + (jewelItem.nativeBattleStats.physicalDefense / 2),
            magic: baseItem.nativeBattleStats.magic + (jewelItem.nativeBattleStats.magic / 2),
            magicDefense: baseItem.nativeBattleStats.magicDefense + (jewelItem.nativeBattleStats.magicDefense / 2),
            healing: baseItem.nativeBattleStats.healing + (jewelItem.nativeBattleStats.healing / 2),
            accuracy: baseItem.nativeBattleStats.accuracy + (jewelItem.nativeBattleStats.accuracy / 2),
            evasion: baseItem.nativeBattleStats.evasion + (jewelItem.nativeBattleStats.evasion / 2),
            attackCount: baseItem.nativeBattleStats.attackCount + (jewelItem.nativeBattleStats.attackCount / 2),
            criticalRate: baseItem.nativeBattleStats.criticalRate + (jewelItem.nativeBattleStats.criticalRate / 2),
            breathPower: baseItem.nativeBattleStats.breathPower + (jewelItem.nativeBattleStats.breathPower / 2)
        ))
    }

    @Test
    func jewelExtractionFromInventorySplitsIntoBaseAndInventoryJewel() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let baseItem = try #require(masterData.items.first(where: { $0.category != .jewel }))
        let jewelItem = try #require(masterData.items.first(where: { $0.category == .jewel }))
        let enhancedItemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 0,
            baseItemId: baseItem.id,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: jewelItem.id
        )

        try guildServices.inventory.addInventoryStacks(
            [CompositeItemStack(itemID: enhancedItemID, count: 1)],
            masterData: masterData
        )

        try await guildServices.equipment.extractJewel(
            itemID: enhancedItemID,
            characterId: nil,
            masterData: masterData
        )

        #expect(try guildCoreDataRepository.loadInventoryStacks().sorted {
            $0.itemID.isOrdered(before: $1.itemID)
        } == [
            CompositeItemStack(itemID: .baseItem(itemId: baseItem.id), count: 1),
            CompositeItemStack(itemID: .baseItem(itemId: jewelItem.id), count: 1)
        ])
    }

    @Test
    func jewelExtractionFromEquippedItemKeepsBaseEquippedAndReturnsJewelToInventory() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let baseItem = try #require(masterData.items.first(where: { $0.category != .jewel }))
        let jewelItem = try #require(masterData.items.first(where: { $0.category == .jewel }))
        let enhancedItemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 0,
            baseItemId: baseItem.id,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: jewelItem.id
        )

        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        var equippedCharacter = character
        equippedCharacter.equippedItemStacks = [CompositeItemStack(itemID: enhancedItemID, count: 1)]
        snapshot = GuildRosterSnapshot(
            playerState: snapshot.playerState,
            characters: [equippedCharacter],
            labyrinthProgressRecords: snapshot.labyrinthProgressRecords
        )
        try guildCoreDataRepository.saveRosterState(
            snapshot,
            parties: try guildCoreDataRepository.loadParties(),
            inventoryStacks: []
        )

        try await guildServices.equipment.extractJewel(
            itemID: enhancedItemID,
            characterId: character.characterId,
            masterData: masterData
        )

        let updatedCharacter = try #require(try guildCoreDataRepository.loadCharacter(characterId: character.characterId))
        #expect(updatedCharacter.equippedItemStacks == [
            CompositeItemStack(itemID: .baseItem(itemId: baseItem.id), count: 1)
        ])
        #expect(try guildCoreDataRepository.loadInventoryStacks() == [
            CompositeItemStack(itemID: .baseItem(itemId: jewelItem.id), count: 1)
        ])
    }

    @Test
    func jewelEnhancementDecrementsInventoryBaseAndJewelByOne() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let baseItemID = CompositeItemID.baseItem(itemId: try itemId(for: .sword, in: masterData))
        let jewelItemID = CompositeItemID.baseItem(itemId: try itemId(for: .jewel, in: masterData))
        let resultItemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 0,
            baseItemId: baseItemID.baseItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: jewelItemID.baseItemId
        )

        try guildServices.inventory.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 3),
                CompositeItemStack(itemID: jewelItemID, count: 2)
            ],
            masterData: masterData
        )

        try await guildServices.equipment.enhanceWithJewel(
            baseItemID: baseItemID,
            baseCharacterId: nil,
            jewelItemID: jewelItemID,
            jewelCharacterId: nil,
            masterData: masterData
        )

        let inventoryStacks = try guildCoreDataRepository.loadInventoryStacks()
        #expect(inventoryStacks.first(where: { $0.itemID == baseItemID })?.count == 2)
        #expect(inventoryStacks.first(where: { $0.itemID == jewelItemID })?.count == 1)
        #expect(inventoryStacks.first(where: { $0.itemID == resultItemID })?.count == 1)
        #expect(inventoryStacks.reduce(into: 0) { $0 += $1.count } == 4)
    }

    @Test
    func jewelEnhancementKeepsEquippedTargetOnCharacterAndOnlyTransformsOneItem() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let baseItemID = CompositeItemID.baseItem(itemId: try itemId(for: .sword, in: masterData))
        let jewelItemID = CompositeItemID.baseItem(itemId: try itemId(for: .jewel, in: masterData))
        let resultItemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 0,
            baseItemId: baseItemID.baseItemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: jewelItemID.baseItemId
        )

        try guildServices.inventory.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 2),
                CompositeItemStack(itemID: jewelItemID, count: 2)
            ],
            masterData: masterData
        )
        _ = try await guildServices.equipment.equip(
            itemID: baseItemID,
            toCharacter: character.characterId,
            masterData: masterData
        )
        _ = try await guildServices.equipment.equip(
            itemID: baseItemID,
            toCharacter: character.characterId,
            masterData: masterData
        )

        try await guildServices.equipment.enhanceWithJewel(
            baseItemID: baseItemID,
            baseCharacterId: character.characterId,
            jewelItemID: jewelItemID,
            jewelCharacterId: nil,
            masterData: masterData
        )

        let updatedCharacter = try #require(try guildCoreDataRepository.loadCharacter(characterId: character.characterId))
        let inventoryStacks = try guildCoreDataRepository.loadInventoryStacks()

        #expect(updatedCharacter.equippedItemCount == 2)
        #expect(updatedCharacter.equippedItemStacks.first(where: { $0.itemID == baseItemID })?.count == 1)
        #expect(updatedCharacter.equippedItemStacks.first(where: { $0.itemID == resultItemID })?.count == 1)
        #expect(updatedCharacter.equippedItemStacks.reduce(into: 0) { $0 += $1.count } == 2)
        #expect(inventoryStacks.first(where: { $0.itemID == jewelItemID })?.count == 1)
        #expect(inventoryStacks.contains(where: { $0.itemID == baseItemID }) == false)
        #expect(inventoryStacks.contains(where: { $0.itemID == resultItemID }) == false)
    }

    @Test
    func unlockPartyConsumesGoldAndCreatesSequentialParty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataRepository.saveRosterSnapshot(snapshot)

        _ = try guildServices.parties.unlockParty()

        #expect(
            try guildCoreDataRepository.loadRosterSnapshot().playerState.gold
                == 10_000_000 - PartyRecord.unlockCost(forExistingPartyCount: 1)!
        )
        #expect(try guildCoreDataRepository.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: []),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [])
        ])
    }

    @Test
    func movingCharacterBetweenPartiesUpdatesMembership() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let firstCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let secondCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataRepository.saveRosterSnapshot(snapshot)

        _ = try guildServices.parties.unlockParty()
        _ = try await guildServices.parties.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        _ = try await guildServices.parties.addCharacter(characterId: secondCharacter.characterId, toParty: 1)
        _ = try await guildServices.parties.addCharacter(characterId: firstCharacter.characterId, toParty: 2)

        #expect(try guildCoreDataRepository.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [secondCharacter.characterId]),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [firstCharacter.characterId])
        ])
    }

    @Test
    func renamingPartyTrimsWhitespaceAndLength() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )

        _ = try guildServices.parties.renameParty(
            partyId: 1,
            name: "  これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です  "
        )

        let renamedParty = try #require(guildCoreDataRepository.loadParties().first)
        #expect(renamedParty.name == String("これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です".prefix(PartyRecord.maxNameLength)))
    }

    @Test
    func resumingBackgroundProgressChainsAutomaticRunsFromLatestCompletionTime() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "自動周回迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let itemDropNotificationService = ItemDropNotificationService(masterData: masterData)
        let rosterStore = GuildRosterStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.roster,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.parties,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataRepository: explorationCoreDataRepository,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )

        rosterStore.reload()
        partyStore.reload()

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        rosterStore.reload()
        partyStore.reload()

        let firstStartedAt = Date(timeIntervalSinceReferenceDate: 100)
        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            startedAt: firstStartedAt,
            masterData: masterData
        )
        _ = await explorationStore.refreshProgress(
            at: firstStartedAt.addingTimeInterval(1),
            masterData: masterData
        )

        try guildServices.parties.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 110))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 113),
            partyStore: partyStore,
            partyService: guildServices.parties,
            masterData: masterData
        )

        let runs = explorationStore.runs
            .filter { $0.partyId == 1 }
            .sorted { $0.partyRunId < $1.partyRunId }
        let allRunsCompleted = runs.allSatisfy { $0.isCompleted }

        #expect(runs.count == 4)
        #expect(allRunsCompleted)
        #expect(runs.map(\.startedAt) == [
            Date(timeIntervalSinceReferenceDate: 100),
            Date(timeIntervalSinceReferenceDate: 110),
            Date(timeIntervalSinceReferenceDate: 111),
            Date(timeIntervalSinceReferenceDate: 112),
        ])
        #expect(runs.compactMap { $0.completion?.completedAt } == [
            Date(timeIntervalSinceReferenceDate: 101),
            Date(timeIntervalSinceReferenceDate: 111),
            Date(timeIntervalSinceReferenceDate: 112),
            Date(timeIntervalSinceReferenceDate: 113),
        ])
        let persistedRoster = try guildCoreDataRepository.loadRosterSnapshot()
        let persistedParty = try #require(guildCoreDataRepository.loadParties().first)
        #expect(persistedRoster.playerState.lastBackgroundedAt == nil)
        #expect(persistedParty.pendingAutomaticRunCount == 0)
        #expect(persistedParty.pendingAutomaticRunStartedAt == nil)
    }

    @Test
    func queuingAutomaticRunsCapsPendingCountAtTwenty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "上限確認迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )
        try guildServices.parties.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 100))
        try guildServices.parties.queueAutomaticRunsForResume(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 140),
            partyStatusesById: [:],
            masterData: masterData
        )

        let persistedParty = try #require(guildCoreDataRepository.loadParties().first)
        #expect(persistedParty.pendingAutomaticRunCount == PartyRecord.maxPendingAutomaticRunCount)
        #expect(persistedParty.pendingAutomaticRunStartedAt == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test
    func resumingBackgroundProgressQueuesOnlyCompletedAutomaticRunsAfterLatestCompletionTime() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "経過時間迷宮",
                    progressIntervalSeconds: 10,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let itemDropNotificationService = ItemDropNotificationService(masterData: masterData)
        let rosterStore = GuildRosterStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.roster,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.parties,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataRepository: explorationCoreDataRepository,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )

        rosterStore.reload()
        partyStore.reload()

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildServices.roster.updateAutoBattleSettings(
            characterId: character.characterId,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .breath, .recoverySpell, .attackSpell]
            )
        )
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        rosterStore.reload()
        partyStore.reload()

        let firstStartedAt = Date().addingTimeInterval(60)
        let secondStartedAt = firstStartedAt.addingTimeInterval(10)
        let firstCompletedAt = firstStartedAt.addingTimeInterval(10)
        let secondCompletedAt = firstStartedAt.addingTimeInterval(20)

        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            startedAt: firstStartedAt,
            masterData: masterData
        )

        try guildServices.parties.recordBackgroundedAt(firstStartedAt.addingTimeInterval(5))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: firstStartedAt.addingTimeInterval(29),
            partyStore: partyStore,
            partyService: guildServices.parties,
            masterData: masterData
        )
        await explorationStore.reload(masterData: masterData)

        let runs = explorationStore.runs
            .filter { $0.partyId == 1 }
            .sorted { $0.partyRunId < $1.partyRunId }

        #expect(runs.map(\.startedAt) == [
            firstStartedAt,
            secondStartedAt,
        ])
        #expect(runs.compactMap { $0.completion?.completedAt } == [
            firstCompletedAt,
            secondCompletedAt,
        ])
        #expect(runs.contains(where: { !$0.isCompleted }) == false)
    }

    @Test
    func queueAutomaticRunsDoesNotQueuePartialElapsedRun() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "部分経過迷宮",
                    progressIntervalSeconds: 10,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        try guildServices.parties.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 100))
        try guildServices.parties.queueAutomaticRunsForResume(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 109),
            partyStatusesById: [:],
            masterData: masterData
        )

        let persistedParty = try #require(guildCoreDataRepository.loadParties().first)
        #expect(persistedParty.pendingAutomaticRunCount == 0)
        #expect(persistedParty.pendingAutomaticRunStartedAt == nil)
    }

    @Test
    func resumingBackgroundProgressClearsInvalidPendingPartyAndContinuesOtherParties() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "選別迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let itemDropNotificationService = ItemDropNotificationService(masterData: masterData)
        let rosterStore = GuildRosterStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.roster,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.parties,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataRepository: explorationCoreDataRepository,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataRepository.saveRosterSnapshot(snapshot)

        _ = try guildServices.parties.unlockParty()
        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 2)
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )
        _ = try await guildServices.parties.setSelectedLabyrinth(
            partyId: 2,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        rosterStore.reload()
        partyStore.reload()

        try guildServices.parties.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 110))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 113),
            partyStore: partyStore,
            partyService: guildServices.parties,
            masterData: masterData
        )

        let firstPartyRuns = explorationStore.runs.filter { $0.partyId == 1 }
        let secondPartyRuns = explorationStore.runs
            .filter { $0.partyId == 2 }
            .sorted { $0.partyRunId < $1.partyRunId }
        let persistedParties = try guildCoreDataRepository.loadParties()
        let firstParty = try #require(persistedParties.first(where: { $0.partyId == 1 }))
        let secondParty = try #require(persistedParties.first(where: { $0.partyId == 2 }))

        #expect(firstPartyRuns.isEmpty)
        #expect(secondPartyRuns.count == 3)
        #expect(secondPartyRuns.allSatisfy { $0.isCompleted })
        #expect(secondPartyRuns.map(\.startedAt) == [
            Date(timeIntervalSinceReferenceDate: 110),
            Date(timeIntervalSinceReferenceDate: 111),
            Date(timeIntervalSinceReferenceDate: 112),
        ])
        #expect(firstParty.pendingAutomaticRunCount == 0)
        #expect(firstParty.pendingAutomaticRunStartedAt == nil)
        #expect(secondParty.pendingAutomaticRunCount == 0)
        #expect(secondParty.pendingAutomaticRunStartedAt == nil)
    }

    @Test
    func partyCatTicketSettingPersists() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )

        _ = try await guildServices.parties.setAutomaticallyUsesCatTicket(
            partyId: 1,
            isEnabled: true
        )

        let persistedParty = try #require(guildCoreDataRepository.loadParties().first)
        #expect(persistedParty.automaticallyUsesCatTicket)
    }

    @Test
    func reviveOperationsRestoreDefeatedCharactersAndPersistAutoReviveSetting() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let firstCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let secondCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try setCurrentHP(characterId: firstCharacter.characterId, to: 0, in: container)
        try setCurrentHP(characterId: secondCharacter.characterId, to: 0, in: container)

        _ = try guildServices.roster.reviveCharacter(
            characterId: firstCharacter.characterId,
            masterData: masterData
        )
        let afterSingleRevive = try guildCoreDataRepository.loadRosterSnapshot().characters
        #expect(afterSingleRevive.first(where: { $0.characterId == firstCharacter.characterId })?.currentHP ?? 0 > 0)
        #expect(afterSingleRevive.first(where: { $0.characterId == secondCharacter.characterId })?.currentHP == 0)

        _ = try guildServices.roster.reviveAllDefeated(masterData: masterData)
        let afterBulkRevive = try guildCoreDataRepository.loadRosterSnapshot().characters
        #expect(afterBulkRevive.allSatisfy { $0.currentHP > 0 })

        let updatedSnapshot = try guildServices.roster.setAutoReviveDefeatedCharactersEnabled(true)
        #expect(updatedSnapshot.playerState.autoReviveDefeatedCharacters)
        #expect(try guildCoreDataRepository.loadRosterSnapshot().playerState.autoReviveDefeatedCharacters)
    }

    @Test
    func updatingAutoBattleSettingsPersistsCharacterRates() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let updatedCharacter = try await guildServices.roster.updateAutoBattleSettings(
            characterId: character.characterId,
            autoBattleSettings: CharacterAutoBattleSettings(
                rates: CharacterActionRates(
                    breath: 10,
                    attack: 20,
                    recoverySpell: 30,
                    attackSpell: 40
                ),
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )

        #expect(updatedCharacter.autoBattleSettings.rates == CharacterActionRates(
            breath: 10,
            attack: 20,
            recoverySpell: 30,
            attackSpell: 40
        ))
        #expect(updatedCharacter.autoBattleSettings.priority == [.attackSpell, .attack, .recoverySpell, .breath])
        #expect(
            try guildCoreDataRepository.loadCharacter(characterId: character.characterId)?.autoBattleSettings.rates
                == CharacterActionRates(
                    breath: 10,
                    attack: 20,
                    recoverySpell: 30,
                    attackSpell: 40
                )
        )
        #expect(
            try guildCoreDataRepository.loadCharacter(characterId: character.characterId)?.autoBattleSettings.priority
                == [.attackSpell, .attack, .recoverySpell, .breath]
        )
    }

    @Test
    func changingJobUpdatesJobsAndKeepsOnlyPreviousPassiveSkills() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let updatedCharacter = try await guildServices.roster.changeJob(
            characterId: character.characterId,
            to: try jobId(named: "騎士", in: masterData),
            masterData: masterData
        )
        let updatedStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: updatedCharacter, masterData: masterData)
        )
        let magicianJobId = try jobId(named: "魔導士", in: masterData)
        let knightJobId = try jobId(named: "騎士", in: masterData)
        let magicSkillId = try skillId(named: "魔法+10%", in: masterData)
        let expectedSpellIDs = try Set(
            spellIds(named: ["炎", "氷", "電撃", "魔法バフ"], in: masterData)
        )

        #expect(updatedCharacter.previousJobId == magicianJobId)
        #expect(updatedCharacter.currentJobId == knightJobId)
        #expect(updatedCharacter.portraitAssetID == "job_knight_\(updatedCharacter.portraitGender.assetKey)")
        #expect(Set(updatedStatus.spellIds) == expectedSpellIDs)
        #expect(updatedStatus.skillIds.contains(magicSkillId))
    }

    @Test
    func changingJobTwiceFails() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        _ = try await guildServices.roster.changeJob(
            characterId: character.characterId,
            to: try jobId(named: "剣士", in: masterData),
            masterData: masterData
        )

        do {
            _ = try await guildServices.roster.changeJob(
                characterId: character.characterId,
                to: try jobId(named: "狩人", in: masterData),
                masterData: masterData
            )
            Issue.record("二度目の転職は失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("転職済み") == true)
        }
    }

    @Test
    func changingJobClampsCurrentHPIntoRecalculatedRange() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let overMaxCharacter = try guildServices.roster.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let belowZeroCharacter = try guildServices.roster.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "狩人", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try setCurrentHP(characterId: overMaxCharacter.characterId, to: 99_999, in: container)
        try setCurrentHP(characterId: belowZeroCharacter.characterId, to: -10, in: container)

        let overMaxUpdatedCharacter = try await guildServices.roster.changeJob(
            characterId: overMaxCharacter.characterId,
            to: try jobId(named: "騎士", in: masterData),
            masterData: masterData
        )
        let belowZeroUpdatedCharacter = try await guildServices.roster.changeJob(
            characterId: belowZeroCharacter.characterId,
            to: try jobId(named: "僧侶", in: masterData),
            masterData: masterData
        )

        let overMaxStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: overMaxUpdatedCharacter, masterData: masterData)
        )
        let belowZeroStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: belowZeroUpdatedCharacter, masterData: masterData)
        )

        #expect(overMaxUpdatedCharacter.currentHP == overMaxStatus.maxHP)
        #expect(belowZeroUpdatedCharacter.currentHP == 0)
        #expect((0...belowZeroStatus.maxHP).contains(belowZeroUpdatedCharacter.currentHP))
    }

    @Test
    func changingJobTrimsEquippedOverflowFromTailAndReturnsItemsToInventory() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let baseStats = battleBaseStats()
        let battleStats = MasterData.BattleStats(
            maxHP: 0,
            physicalAttack: 0,
            physicalDefense: 0,
            magic: 0,
            magicDefense: 0,
            healing: 0,
            accuracy: 0,
            evasion: 0,
            attackCount: 0,
            criticalRate: 0,
            breathPower: 0
        )
        let coefficients = MasterData.BattleStatCoefficients(
            maxHP: 1.0,
            physicalAttack: 1.0,
            physicalDefense: 1.0,
            magic: 1.0,
            magicDefense: 1.0,
            healing: 1.0,
            accuracy: 1.0,
            evasion: 1.0,
            attackCount: 1.0,
            criticalRate: 1.0,
            breathPower: 1.0
        )
        let capacityPenaltySkillID = 1
        let masterData = MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [
                MasterData.Race(
                    id: 1,
                    key: "test-race",
                    name: "テスト種族",
                    levelCap: 99,
                    baseHirePrice: 1,
                    baseStats: baseStats,
                    passiveSkillIds: [],
                    levelSkillIds: []
                )
            ],
            jobs: [
                MasterData.Job(
                    id: 1,
                    key: "base-job",
                    name: "基準職",
                    hirePriceMultiplier: 1.0,
                    coefficients: coefficients,
                    passiveSkillIds: [],
                    levelSkillIds: [],
                    jobChangeRequirement: nil
                ),
                MasterData.Job(
                    id: 2,
                    key: "limited-job",
                    name: "制限職",
                    hirePriceMultiplier: 1.0,
                    coefficients: coefficients,
                    passiveSkillIds: [capacityPenaltySkillID],
                    levelSkillIds: [],
                    jobChangeRequirement: nil
                )
            ],
            aptitudes: [
                MasterData.Aptitude(
                    id: 1,
                    name: "テスト資質",
                    passiveSkillIds: []
                )
            ],
            items: (1...4).map { itemID in
                MasterData.Item(
                    id: itemID,
                    name: "テスト装備\(itemID)",
                    category: .sword,
                    rarity: .normal,
                    basePrice: 1,
                    nativeBaseStats: baseStats,
                    nativeBattleStats: battleStats,
                    skillIds: [],
                    rangeClass: .melee,
                    normalDropTier: 1
                )
            },
            titles: [],
            superRares: [],
            skills: [
                MasterData.Skill(
                    id: capacityPenaltySkillID,
                    name: "装備可能数-1",
                    description: "装備可能数を1減らす。",
                    effects: [
                        MasterData.SkillEffect.equipmentCapacityModifier(value: -1)
                    ]
                )
            ],
            spells: [],
            recruitNames: MasterData.RecruitNames(
                male: [],
                female: [],
                unisex: []
            ),
            enemies: [],
            labyrinths: []
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        let sortedItemIDs = masterData.items.map(\.id).sorted()
        #expect(sortedItemIDs.count == 4)
        let equippedStacks = [
            CompositeItemStack(itemID: CompositeItemID.baseItem(itemId: sortedItemIDs[2]), count: 1),
            CompositeItemStack(itemID: CompositeItemID.baseItem(itemId: sortedItemIDs[0]), count: 1),
            CompositeItemStack(itemID: CompositeItemID.baseItem(itemId: sortedItemIDs[3]), count: 1),
            CompositeItemStack(itemID: CompositeItemID.baseItem(itemId: sortedItemIDs[1]), count: 1)
        ]
        let orderedStacks = equippedStacks.sorted { $0.itemID.isOrdered(before: $1.itemID) }
        let expectedRetainedStacks = Array(orderedStacks.prefix(2))
        let expectedRemovedStacks = Array(orderedStacks.suffix(2))
        var persistedCharacter = try #require(
            try guildCoreDataRepository.loadCharacter(characterId: character.characterId)
        )
        persistedCharacter.equippedItemStacks = equippedStacks
        try guildCoreDataRepository.saveCharacter(persistedCharacter)

        let updatedCharacter = try await guildServices.roster.changeJob(
            characterId: character.characterId,
            to: 2,
            masterData: masterData
        )

        #expect(updatedCharacter.equippedItemStacks == expectedRetainedStacks)
        #expect(
            updatedCharacter.equippedItemCount
                == updatedCharacter.maximumEquippedItemCount(masterData: masterData)
        )
        #expect(updatedCharacter.maximumEquippedItemCount(masterData: masterData) == 2)
        #expect(try guildCoreDataRepository.loadInventoryStacks() == expectedRemovedStacks)
    }

    @Test
    func equippingAndUnequippingUpdatesInventoryAndCharacterStacks() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemID = CompositeItemID.baseItem(itemId: try #require(masterData.items.first?.id))

        try guildServices.inventory.addInventoryStacks(
            [CompositeItemStack(itemID: itemID, count: 2)],
            masterData: masterData
        )

        let equippedCharacter = try await guildServices.equipment.equip(
            itemID: itemID,
            toCharacter: character.characterId,
            masterData: masterData
        )
        #expect(equippedCharacter.equippedItemStacks == [CompositeItemStack(itemID: itemID, count: 1)])
        #expect(try guildCoreDataRepository.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 1)])

        let unequippedCharacter = try await guildServices.equipment.unequip(
            itemID: itemID,
            fromCharacter: character.characterId,
            masterData: masterData
        )
        #expect(unequippedCharacter.equippedItemStacks.isEmpty)
        #expect(try guildCoreDataRepository.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 2)])
    }

    @Test
    func equipUsesSkillAdjustedEquipmentCapacity() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "騎士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemIDs = masterData.items.prefix(4).map { CompositeItemID.baseItem(itemId: $0.id) }
        #expect(itemIDs.count == 4)
        #expect(character.maximumEquippedItemCount(masterData: masterData) == 4)

        try guildServices.inventory.addInventoryStacks(
            itemIDs.map { CompositeItemStack(itemID: $0, count: 1) },
            masterData: masterData
        )

        for itemID in itemIDs {
            _ = try await guildServices.equipment.equip(
                itemID: itemID,
                toCharacter: character.characterId,
                masterData: masterData
            )
        }

        let updatedCharacter = try #require(
            try guildCoreDataRepository.loadCharacter(characterId: character.characterId)
        )
        #expect(updatedCharacter.equippedItemCount == 4)
        #expect(updatedCharacter.maximumEquippedItemCount(masterData: masterData) == 4)
        #expect(try guildCoreDataRepository.loadInventoryStacks().isEmpty)
    }

    @Test
    func autoSellSettingsPersistExactCompositeItemIDs() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let compositeItemID = CompositeItemID(
            baseSuperRareId: try #require(masterData.superRares.first?.id),
            baseTitleId: try #require(masterData.titles.first?.id),
            baseItemId: try itemId(for: .sword, in: masterData),
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )

        let updatedPlayerState = try guildServices.roster.setAutoSellEnabled(
            itemID: compositeItemID,
            isEnabled: true,
            masterData: masterData
        )

        #expect(updatedPlayerState.autoSellItemIDs == Set([compositeItemID]))
        #expect(
            try guildCoreDataRepository.loadFreshRosterSnapshot().playerState.autoSellItemIDs
                == Set([compositeItemID])
        )
    }

    @Test
    func configuringAutoSellSellsSelectedInventoryStacks() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let itemID = CompositeItemID(
            baseSuperRareId: try #require(masterData.superRares.first?.id),
            baseTitleId: try #require(masterData.titles.first?.id),
            baseItemId: try itemId(for: .sword, in: masterData),
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.shopInventoryInitialized = true
        let sellCount = 3

        try guildCoreDataRepository.saveTradeState(
            playerState: snapshot.playerState,
            inventoryStacks: [CompositeItemStack(itemID: itemID, count: sellCount)],
            shopInventoryStacks: []
        )

        let updatedPlayerState = try guildServices.shop.configureAutoSell(
            itemIDs: [itemID],
            masterData: masterData
        )

        #expect(updatedPlayerState.autoSellItemIDs == Set([itemID]))
        #expect(
            try guildCoreDataRepository.loadFreshRosterSnapshot().playerState.gold
                == PlayerState.initial.gold + ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) * sellCount
        )
        #expect(try guildCoreDataRepository.loadInventoryStacks().isEmpty)
        #expect(
            try guildCoreDataRepository.loadShopInventoryStacks()
                == [CompositeItemStack(itemID: itemID, count: sellCount)]
        )
    }

    @Test
    func stockOrganizationConsumesExactShopStackAndAddsCatTickets() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let baseItem = try #require(masterData.items.first(where: { $0.rarity != .normal }))
        let itemID = CompositeItemID.baseItem(itemId: baseItem.id)
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.shopInventoryInitialized = true

        try guildCoreDataRepository.saveTradeState(
            playerState: snapshot.playerState,
            inventoryStacks: [],
            shopInventoryStacks: [
                CompositeItemStack(
                    itemID: itemID,
                    count: ShopPricingCalculator.stockOrganizationBundleSize
                )
            ]
        )

        try guildServices.shop.organizeShopInventoryItem(
            itemID: itemID,
            masterData: masterData
        )

        #expect(try guildCoreDataRepository.loadShopInventoryStacks().isEmpty)
        #expect(
            try guildCoreDataRepository.loadFreshRosterSnapshot().playerState.catTicketCount
                == PlayerState.initial.catTicketCount + ShopPricingCalculator.stockOrganizationTicketCount(for: baseItem.basePrice)
        )
    }

    @Test
    func shopCatalogEvaluatesBaseAndJewelComponentsSeparately() {
        let masterData = shopCatalogTestMasterData()
        let itemID = CompositeItemID(
            baseSuperRareId: 1,
            baseTitleId: 1,
            baseItemId: 1,
            jewelSuperRareId: 1,
            jewelTitleId: 1,
            jewelItemId: 2
        )

        #expect(ShopPricingCalculator.purchasePrice(for: itemID, masterData: masterData) == 4_200)
        #expect(ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) == 210)
    }

    @Test
    func shopCatalogKeepsBaseSideModifiersOffTheJewelSide() {
        let masterData = shopCatalogTestMasterData()
        let itemID = CompositeItemID(
            baseSuperRareId: 0,
            baseTitleId: 1,
            baseItemId: 1,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 2
        )

        #expect(ShopPricingCalculator.purchasePrice(for: itemID, masterData: masterData) == 1_900)
        #expect(ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) == 95)
    }

    @Test
    func shopCatalogCapsEconomicPriceBeforeSellbackCalculation() {
        let masterData = shopCatalogTestMasterData()
        let itemID = CompositeItemID.baseItem(itemId: 3)

        #expect(ShopPricingCalculator.purchasePrice(for: itemID, masterData: masterData) == EconomyPricing.maximumEconomicPrice)
        #expect(ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) == 5_000_000)
    }

    @Test
    func debugItemBatchGeneratorMovesIntoNextGroupWhenTitleOnlyIsExhausted() {
        let masterData = debugItemGenerationMasterData()
        let generator = DebugItemBatchGenerator(masterData: masterData)

        let batch = generator.generate(requestedCombinationCount: 2, stackCount: 50)

        #expect(batch.generatedCombinationCount == 2)
        #expect(batch.inventoryStacks.count == 2)
        #expect(batch.inventoryStacks[0].count == 50)
        #expect(batch.inventoryStacks[0].itemID.baseTitleId == 1)
        #expect(batch.inventoryStacks[0].itemID.baseSuperRareId == 0)
        #expect(batch.inventoryStacks[0].itemID.jewelItemId == 0)
        #expect(batch.inventoryStacks[1].itemID.baseTitleId == 1)
        #expect(batch.inventoryStacks[1].itemID.baseSuperRareId == 1)
        #expect(batch.inventoryStacks[1].itemID.jewelItemId == 0)
    }

    @Test
    func debugItemBatchGeneratorStopsAfterAllAvailableCombinations() {
        let masterData = debugItemGenerationMasterData()
        let generator = DebugItemBatchGenerator(masterData: masterData)

        let batch = generator.generate(requestedCombinationCount: 10, stackCount: 99)

        #expect(generator.totalCombinationCount == 3)
        #expect(batch.generatedCombinationCount == 3)
        #expect(batch.inventoryStacks.count == 3)
        #expect(batch.inventoryStacks.last?.count == 99)
        #expect(batch.inventoryStacks.last?.itemID.baseSuperRareId == 1)
        #expect(batch.inventoryStacks.last?.itemID.baseTitleId == 1)
        #expect(batch.inventoryStacks.last?.itemID.jewelItemId == 2)
        #expect(batch.inventoryStacks.last?.itemID.jewelSuperRareId == 1)
        #expect(batch.inventoryStacks.last?.itemID.jewelTitleId == 1)
    }

}
