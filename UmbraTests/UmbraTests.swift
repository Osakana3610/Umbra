// Verifies runtime master data and guild hiring logic.

import CoreData
import Foundation
import Testing
@testable import Umbra

@MainActor
struct UmbraTests {
    @Test
    func generatedMasterDataDecodes() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "デバッグの洞窟")
    }

    @Test
    func recruitNamesDecodeByGender() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.recruitNames.male.isEmpty)
        #expect(!masterData.recruitNames.female.isEmpty)
        #expect(!masterData.recruitNames.unisex.isEmpty)
    }

    @Test
    func guildCoreDataStoreCreatesInitialPlayerState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)

        let snapshot = try guildCoreDataStore.loadRosterSnapshot()
        let parties = try guildCoreDataStore.loadParties()

        #expect(snapshot.playerState == .initial)
        #expect(snapshot.characters.isEmpty)
        #expect(parties == [PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [])])
    }

    @Test
    func hireCharacterPersistsPlayerAndCharacterState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let result = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        )

        #expect(result.hireCost == 1)
        #expect(result.playerState.gold == 999)
        #expect(result.playerState.nextCharacterId == 2)
        #expect(result.character.characterId == 1)
        #expect(!result.character.name.isEmpty)
        #expect(matchesRecruitNamePool(character: result.character, masterData: masterData))
        #expect(result.character.level == 1)
        #expect(result.character.currentHP > 0)
        #expect(result.character.autoBattleSettings == .default)

        let reloadedSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        #expect(reloadedSnapshot.playerState == result.playerState)
        #expect(reloadedSnapshot.characters == [result.character])
    }

    @Test
    func completeStatusCalculationBuildsBattleStatsAndCapabilities() throws {
        let masterData = try loadGeneratedMasterData()
        let character = CharacterRecord(
            characterId: 1,
            name: "テスト騎士",
            raceId: try raceId(named: "人間", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "騎士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .male,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )

        let status = try #require(CharacterDerivedStatsCalculator.status(for: character, masterData: masterData))

        #expect(status.baseStats == CharacterBaseStats(
            vitality: 7,
            strength: 7,
            mind: 7,
            intelligence: 7,
            agility: 7,
            luck: 7
        ))
        #expect(status.battleStats == CharacterBattleStats(
            maxHP: 231,
            physicalAttack: 42,
            physicalDefense: 23,
            magic: 42,
            magicDefense: 21,
            healing: 32,
            accuracy: 8,
            evasion: 7,
            attackCount: 1,
            criticalRate: 1,
            breathPower: 42
        ))
        #expect(status.battleDerivedStats == .baseline)
        #expect(status.canUseBreath == false)
        #expect(status.spellIds.isEmpty)
        #expect(status.interruptKinds == [.counter])
        #expect(status.skillIds.count == Set(status.skillIds).count)
    }

    @Test
    func completeStatusCalculationCollectsDerivedEffectsAndSpells() throws {
        let masterData = try loadGeneratedMasterData()
        let spellcastingCharacter = CharacterRecord(
            characterId: 1,
            name: "テスト魔導士",
            raceId: try raceId(named: "サイキック", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .male,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )
        let breathCharacter = CharacterRecord(
            characterId: 2,
            name: "テスト狩人",
            raceId: try raceId(named: "ドラゴニュート", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "狩人", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .female,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )

        let spellcastingStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: spellcastingCharacter, masterData: masterData)
        )
        let breathStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: breathCharacter, masterData: masterData)
        )

        #expect(Set(spellcastingStatus.spellIds) == Set(try spellIds(
            named: ["炎", "氷", "攻撃バフ", "電撃", "魔法バフ", "核攻撃"],
            in: masterData
        )))
        #expect(spellcastingStatus.battleStats.magic == 99)
        #expect(spellcastingStatus.skillIds.count == Set(spellcastingStatus.skillIds).count)

        #expect(breathStatus.canUseBreath)
        #expect(breathStatus.interruptKinds == [.pursuit])
        #expect(breathStatus.battleStats.breathPower == 59)
        #expect(breathStatus.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            magicDamageMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.0,
            meleeDamageMultiplier: 1.0,
            rangedDamageMultiplier: 1.1,
            actionSpeedMultiplier: 1.1,
            physicalResistanceMultiplier: 1.0,
            magicResistanceMultiplier: 1.0,
            breathResistanceMultiplier: 0.8
        ))
    }

    @Test
    func unlockPartyConsumesGoldAndCreatesSequentialParty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )

        _ = try guildService.unlockParty()

        #expect(try guildCoreDataStore.loadRosterSnapshot().playerState.gold == PlayerState.initial.gold - PartyRecord.unlockCost)
        #expect(try guildCoreDataStore.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: []),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [])
        ])
    }

    @Test
    func movingCharacterBetweenPartiesUpdatesMembership() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let firstCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let secondCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        _ = try guildService.unlockParty()
        _ = try await guildService.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        _ = try await guildService.addCharacter(characterId: secondCharacter.characterId, toParty: 1)
        _ = try await guildService.addCharacter(characterId: firstCharacter.characterId, toParty: 2)

        #expect(try guildCoreDataStore.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [secondCharacter.characterId]),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [firstCharacter.characterId])
        ])
    }

    @Test
    func renamingPartyTrimsWhitespaceAndLength() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )

        _ = try guildService.renameParty(
            partyId: 1,
            name: "  これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です  "
        )

        let renamedParty = try #require(guildCoreDataStore.loadParties().first)
        #expect(renamedParty.name == String("これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です".prefix(PartyRecord.maxNameLength)))
    }

    @Test
    func reviveOperationsRestoreDefeatedCharactersAndPersistAutoReviveSetting() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let firstCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let secondCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try setCurrentHP(characterId: firstCharacter.characterId, to: 0, in: container)
        try setCurrentHP(characterId: secondCharacter.characterId, to: 0, in: container)

        _ = try guildService.reviveCharacter(
            characterId: firstCharacter.characterId,
            masterData: masterData
        )
        let afterSingleRevive = try guildCoreDataStore.loadRosterSnapshot().characters
        #expect(afterSingleRevive.first(where: { $0.characterId == firstCharacter.characterId })?.currentHP ?? 0 > 0)
        #expect(afterSingleRevive.first(where: { $0.characterId == secondCharacter.characterId })?.currentHP == 0)

        _ = try guildService.reviveAllDefeated(masterData: masterData)
        let afterBulkRevive = try guildCoreDataStore.loadRosterSnapshot().characters
        #expect(afterBulkRevive.allSatisfy { $0.currentHP > 0 })

        let updatedSnapshot = try guildService.setAutoReviveDefeatedCharactersEnabled(true)
        #expect(updatedSnapshot.playerState.autoReviveDefeatedCharacters)
        #expect(try guildCoreDataStore.loadRosterSnapshot().playerState.autoReviveDefeatedCharacters)
    }

    @Test
    func recordingLastProgressedAtPersistsPlayerCheckpoint() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let rosterStore = GuildRosterStore(
            coreDataStore: guildCoreDataStore,
            service: guildService
        )

        rosterStore.reload()
        let checkpointDate = Date(timeIntervalSinceReferenceDate: 123_456)
        rosterStore.recordLastProgressedAt(checkpointDate)
        let persistedCheckpointDate = try guildCoreDataStore.loadRosterSnapshot().playerState.lastProgressedAt

        #expect(rosterStore.playerState?.lastProgressedAt == checkpointDate)
        #expect(persistedCheckpointDate == checkpointDate)
    }

    @Test
    func updatingAutoBattleSettingsPersistsCharacterRates() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let updatedCharacter = try await guildService.updateAutoBattleSettings(
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
            try guildCoreDataStore.loadCharacter(characterId: character.characterId)?.autoBattleSettings.rates
                == CharacterActionRates(
                    breath: 10,
                    attack: 20,
                    recoverySpell: 30,
                    attackSpell: 40
                )
        )
        #expect(
            try guildCoreDataStore.loadCharacter(characterId: character.characterId)?.autoBattleSettings.priority
                == [.attackSpell, .attack, .recoverySpell, .breath]
        )
    }

    @Test
    func changingJobUpdatesJobsAndKeepsOnlyPreviousPassiveSkills() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let updatedCharacter = try await guildService.changeJob(
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

        #expect(updatedCharacter.previousJobId == magicianJobId)
        #expect(updatedCharacter.currentJobId == knightJobId)
        #expect(updatedStatus.spellIds.isEmpty)
        #expect(updatedStatus.skillIds.contains(magicSkillId))
    }

    @Test
    func changingJobTwiceFails() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        _ = try await guildService.changeJob(
            characterId: character.characterId,
            to: try jobId(named: "剣士", in: masterData),
            masterData: masterData
        )

        do {
            _ = try await guildService.changeJob(
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
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let overMaxCharacter = try guildService.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let belowZeroCharacter = try guildService.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "狩人", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try setCurrentHP(characterId: overMaxCharacter.characterId, to: 99_999, in: container)
        try setCurrentHP(characterId: belowZeroCharacter.characterId, to: -10, in: container)

        let overMaxUpdatedCharacter = try await guildService.changeJob(
            characterId: overMaxCharacter.characterId,
            to: try jobId(named: "騎士", in: masterData),
            masterData: masterData
        )
        let belowZeroUpdatedCharacter = try await guildService.changeJob(
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
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try raceId(named: "人間", in: masterData),
            jobId: try jobId(named: "騎士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let equippedStacks = Array(masterData.items.prefix(4).map { item in
            CompositeItemStack(itemID: CompositeItemID.baseItem(itemId: item.id), count: 1)
        })
        var persistedCharacter = try #require(
            try guildCoreDataStore.loadCharacter(characterId: character.characterId)
        )
        persistedCharacter.equippedItemStacks = equippedStacks
        try guildCoreDataStore.saveCharacter(persistedCharacter)

        let updatedCharacter = try await guildService.changeJob(
            characterId: character.characterId,
            to: try jobId(named: "剣士", in: masterData),
            masterData: masterData
        )

        #expect(updatedCharacter.equippedItemStacks == Array(equippedStacks.prefix(3)))
        #expect(updatedCharacter.equippedItemCount == updatedCharacter.maximumEquippedItemCount)
        #expect(try guildCoreDataStore.loadInventoryStacks() == [equippedStacks[3]])
    }

    @Test
    func equippingAndUnequippingUpdatesInventoryAndCharacterStacks() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemID = CompositeItemID.baseItem(itemId: try #require(masterData.items.first?.id))

        try guildService.addInventoryStacks(
            [CompositeItemStack(itemID: itemID, count: 2)],
            masterData: masterData
        )

        let equippedCharacter = try await guildService.equip(
            itemID: itemID,
            toCharacter: character.characterId,
            masterData: masterData
        )
        #expect(equippedCharacter.equippedItemStacks == [CompositeItemStack(itemID: itemID, count: 1)])
        #expect(try guildCoreDataStore.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 1)])

        let unequippedCharacter = try await guildService.unequip(
            itemID: itemID,
            fromCharacter: character.characterId,
            masterData: masterData
        )
        #expect(unequippedCharacter.equippedItemStacks.isEmpty)
        #expect(try guildCoreDataStore.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 2)])
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

    @Test
    func startingBulkRunsKeepsStartedAtAlignedAcrossParties() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterDataStore = MasterDataStore()
        let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
        let rosterStore = GuildRosterStore(
            coreDataStore: guildCoreDataStore,
            service: guildService,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataStore: ExplorationCoreDataStore(container: container),
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = try loadGeneratedMasterData()

        let firstCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let secondCharacter = try guildService.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        _ = try guildService.unlockParty()
        _ = try await guildService.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        _ = try await guildService.addCharacter(characterId: secondCharacter.characterId, toParty: 2)

        let startedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        await explorationStore.startConfiguredRuns(
            [
                ConfiguredRunStart(
                    partyId: 1,
                    labyrinthId: try #require(masterData.labyrinths.first?.id),
                    selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id)
                ),
                ConfiguredRunStart(
                    partyId: 2,
                    labyrinthId: try #require(masterData.labyrinths.first?.id),
                    selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id)
                ),
            ],
            startedAt: startedAt,
            masterData: masterData
        )

        let runs = explorationStore.runs.sorted { $0.partyId < $1.partyId }
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.startedAt == startedAt })
    }

    @Test
    func explorationProgressRefreshesRosterStoreGold() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let masterDataStore = MasterDataStore()
        let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
        let rosterStore = GuildRosterStore(
            coreDataStore: guildCoreDataStore,
            service: guildService
        )
        let explorationStore = ExplorationStore(
            coreDataStore: explorationCoreDataStore,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        rosterStore.reload()
        let startingGold = try #require(rosterStore.playerState?.gold)
        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)

        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let result = await explorationStore.refreshProgress(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completionGold = try #require(explorationStore.runs.first?.completion?.gold)

        #expect(result.didApplyRewards)
        #expect(completionGold == 40)
        #expect(try guildCoreDataStore.loadRosterSnapshot().playerState.gold == startingGold + completionGold)
        #expect(try guildCoreDataStore.loadFreshRosterSnapshot().playerState.gold == startingGold + completionGold)
        rosterStore.refreshFromPersistence()
        #expect(rosterStore.playerState?.gold == startingGold + completionGold)
    }

    @Test
    func resumeIdleProgressStartsAutomaticRunsAfterExistingRunCompletes() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let masterDataStore = MasterDataStore()
        let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
        let rosterStore = GuildRosterStore(
            coreDataStore: guildCoreDataStore,
            service: guildService
        )
        let partyStore = PartyStore(
            coreDataStore: guildCoreDataStore,
            service: guildService
        )
        let explorationStore = ExplorationStore(
            coreDataStore: explorationCoreDataStore,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = try loadGeneratedMasterData()
        let defaultDifficultyTitleId = try #require(masterData.defaultExplorationDifficultyTitle?.id)
        let labyrinth = try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" }))
        let runDurationSeconds = labyrinth.floors.reduce(0) { partialResult, floor in
            partialResult + floor.battleCount
        } * labyrinth.progressIntervalSeconds

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildService.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: labyrinth.id,
            selectedDifficultyTitleId: defaultDifficultyTitleId
        )
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        rosterStore.reload()
        partyStore.reload()
        let startedAt = Date(timeIntervalSinceReferenceDate: 410_000)
        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: labyrinth.id,
            selectedDifficultyTitleId: defaultDifficultyTitleId,
            startedAt: startedAt,
            masterData: masterData
        )
        rosterStore.recordLastProgressedAt(startedAt)

        let resumedAt = startedAt.addingTimeInterval(Double(runDurationSeconds * 3))
        let checkpointDate = try #require(rosterStore.playerState?.lastProgressedAt)
        let didResume = await explorationStore.resumeIdleProgress(
            since: checkpointDate,
            currentDate: resumedAt,
            parties: partyStore.parties,
            masterData: masterData
        )

        let completedRuns = explorationStore.runs
            .filter(\.isCompleted)
            .sorted { $0.startedAt < $1.startedAt }
        #expect(didResume)
        #expect(explorationStore.runs.count == 2)
        #expect(completedRuns.count == 2)
        #expect(explorationStore.runs.allSatisfy { $0.isCompleted })
        #expect(completedRuns.map(\.startedAt) == [
            startedAt,
            startedAt.addingTimeInterval(Double(runDurationSeconds))
        ])
    }

    @Test
    func activeRunBlocksPartyAndEquipmentMutations() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemID = CompositeItemID.baseItem(itemId: try #require(masterData.items.first?.id))

        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try guildService.addInventoryStacks(
            [CompositeItemStack(itemID: itemID, count: 1)],
            masterData: masterData
        )
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 200_000),
            masterData: masterData
        )

        do {
            _ = try await guildService.removeCharacter(characterId: character.characterId, fromParty: 1)
            Issue.record("探索中パーティからメンバーを外せてはいけません。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }

        do {
            _ = try await guildService.equip(
                itemID: itemID,
                toCharacter: character.characterId,
                masterData: masterData
            )
            Issue.record("探索中キャラクターの装備変更は失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }

        do {
            _ = try await guildService.changeJob(
                characterId: character.characterId,
                to: try jobId(named: "剣士", in: masterData),
                masterData: masterData
            )
            Issue.record("探索中キャラクターの転職は失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }
    }

    @Test
    func startingRunRestoresLivingPartyMembersToMaxHP() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 10,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 3, in: container)

        let injuredCharacterRecord = try guildCoreDataStore.loadCharacter(characterId: character.characterId)
        let injuredCharacter = try #require(injuredCharacterRecord)
        let maxHP = try #require(
            CharacterDerivedStatsCalculator.status(for: injuredCharacter, masterData: masterData)?.maxHP
        )

        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 260_000),
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let persistedCharacterRecord = try guildCoreDataStore.loadCharacter(characterId: character.characterId)
        let persistedCharacter = try #require(persistedCharacterRecord)

        #expect(startedRun.memberSnapshots.map(\.currentHP) == [maxHP])
        #expect(startedRun.currentPartyHPs == [maxHP])
        #expect(persistedCharacter.currentHP == maxHP)
    }

    @Test
    func startingRunRejectsPartyContainingDefeatedMember() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try setCurrentHP(characterId: character.characterId, to: 0, in: container)

        do {
            _ = try await explorationService.startRun(
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                startedAt: Date(timeIntervalSinceReferenceDate: 270_000),
                masterData: masterData
            )
            Issue.record("HP 0 のメンバーを含むパーティは出撃できてはいけません。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("HPが0") == true)
        }
    }

    @Test
    func startingRunPrecomputesPlannedArtifactsWhileKeepingProgressHidden() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        let startedAt = Date(timeIntervalSinceReferenceDate: 280_000)
        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let storedDetail = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))

        #expect(startedRun.completedBattleCount == 0)
        #expect(startedRun.completion == nil)
        #expect(startedRun.battleLogs.isEmpty)

        #expect(storedDetail.completedBattleCount == 0)
        #expect(storedDetail.completion == nil)
        #expect(storedDetail.battleLogs.count == 1)
        #expect(storedDetail.goldBuffer == 40)
        #expect(storedDetail.experienceRewards == [
            ExplorationExperienceReward(characterId: character.characterId, experience: 40)
        ])
    }

    @Test
    func refreshingRunRevealsProgressFromStoredBattlePlan() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        let startedAt = Date(timeIntervalSinceReferenceDate: 290_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let plannedDetail = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))
        let firstBattlePartyHPs = plannedDetail.battleLogs[0].combatants
            .filter { $0.side == .ally }
            .sorted { $0.formationIndex < $1.formationIndex }
            .map(\.remainingHP)

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(1),
            masterData: masterData
        )
        let activeRun = try #require(snapshot.runs.first)
        let refreshedDetail = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))

        #expect(activeRun.completedBattleCount == 1)
        #expect(activeRun.completion == nil)
        #expect(refreshedDetail.battleLogs.count == plannedDetail.battleLogs.count)
        #expect(refreshedDetail.completedBattleCount == 1)
        #expect(refreshedDetail.currentPartyHPs == firstBattlePartyHPs)
    }

    @Test
    func loadRunDetailPreservesActionTargetIdsIndependentFromResults() async throws {
        let explorationCoreDataStore = ExplorationCoreDataStore(
            container: PersistenceController(inMemory: true).container
        )
        let firstTargetId = BattleCombatantID(rawValue: "enemy:1:1")
        let secondTargetId = BattleCombatantID(rawValue: "enemy:1:2")

        try await explorationCoreDataStore.insertRun(
            RunSessionRecord(
                partyRunId: 1,
                partyId: 1,
                labyrinthId: 1,
                selectedDifficultyTitleId: 1,
                targetFloorNumber: 1,
                startedAt: Date(timeIntervalSinceReferenceDate: 295_000),
                rootSeed: 1,
                memberSnapshots: [],
                memberCharacterIds: [],
                completedBattleCount: 0,
                currentPartyHPs: [],
                memberExperienceMultipliers: [],
                goldMultiplier: 1,
                rareDropMultiplier: 1,
                titleDropMultiplier: 1,
                partyAverageLuck: 0,
                latestBattleFloorNumber: nil,
                latestBattleNumber: nil,
                latestBattleOutcome: nil,
                battleLogs: [
                    ExplorationBattleLog(
                        battleRecord: BattleRecord(
                            runId: RunSessionID(partyId: 1, partyRunId: 1),
                            floorNumber: 1,
                            battleNumber: 1,
                            result: .victory,
                            turns: [
                                BattleTurnRecord(
                                    turnNumber: 1,
                                    actions: [
                                        BattleActionRecord(
                                            actorId: BattleCombatantID(rawValue: "character:1"),
                                            actionKind: .attack,
                                            actionRef: nil,
                                            actionFlags: [],
                                            targetIds: [firstTargetId, secondTargetId],
                                            results: [
                                                BattleTargetResult(
                                                    targetId: secondTargetId,
                                                    resultKind: .damage,
                                                    value: 12,
                                                    statusId: nil,
                                                    flags: []
                                                )
                                            ]
                                        )
                                    ]
                                )
                            ]
                        ),
                        combatants: [
                            BattleCombatantSnapshot(
                                id: BattleCombatantID(rawValue: "character:1"),
                                name: "前衛",
                                side: .ally,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 10,
                                formationIndex: 0
                            ),
                            BattleCombatantSnapshot(
                                id: firstTargetId,
                                name: "敵A",
                                side: .enemy,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 10,
                                formationIndex: 0
                            ),
                            BattleCombatantSnapshot(
                                id: secondTargetId,
                                name: "敵B",
                                side: .enemy,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 0,
                                formationIndex: 1
                            )
                        ]
                    )
                ],
                goldBuffer: 0,
                experienceRewards: [],
                dropRewards: [],
                completion: nil
            )
        )

        let storedDetail = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))
        let storedAction = try #require(
            storedDetail.battleLogs.first?.battleRecord.turns.first?.actions.first
        )

        #expect(storedAction.targetIds == [firstTargetId, secondTargetId])
        #expect(storedAction.results.map(\.targetId) == [secondTargetId])
    }

    @Test
    func refreshingCompletedRunAppliesRewardsToPlayerAndCharacterState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(snapshot.didApplyRewards)
        #expect(completion.reason == .cleared)
        #expect(completion.gold == 40)
        #expect(completion.experienceRewards == [
            ExplorationExperienceReward(characterId: character.characterId, experience: 40)
        ])

        let rosterSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        let updatedCharacter = try #require(
            rosterSnapshot.characters.first(where: { $0.characterId == character.characterId })
        )
        #expect(rosterSnapshot.playerState.gold == PlayerState.initial.gold - 1 + completion.gold)
        #expect(updatedCharacter.experience == 40)
        #expect(updatedCharacter.currentHP == completedRun.currentPartyHPs.first)
    }

    @Test
    func clearingRunUnlocksNextExplorationDifficulty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()
        let labyrinthId = try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" })?.id)
        let defaultDifficultyTitleId = try #require(masterData.defaultExplorationDifficultyTitle?.id)
        let nextDifficultyTitleId = try #require(
            masterData.nextExplorationDifficultyTitleId(after: defaultDifficultyTitleId)
        )

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: defaultDifficultyTitleId,
            startedAt: Date(timeIntervalSinceReferenceDate: 310_000),
            masterData: masterData
        )
        _ = try await explorationService.refreshRuns(
            at: Date(timeIntervalSinceReferenceDate: 310_010),
            masterData: masterData
        )

        let progressRecord = try guildCoreDataStore.loadFreshRosterSnapshot().labyrinthProgressRecords.first {
            $0.labyrinthId == labyrinthId
        }
        #expect(progressRecord?.highestUnlockedDifficultyTitleId == nextDifficultyTitleId)
    }

    @Test
    func refreshProgressUsesStoredRunMemberSnapshotsInsteadOfLiveCharacters() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        let startedAt = Date(timeIntervalSinceReferenceDate: 320_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの遺跡" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        try promoteCharacter(
            characterId: character.characterId,
            level: 1,
            in: container
        )

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(completion.reason == .cleared)
        #expect(completion.gold == 40)
        #expect(completion.experienceRewards == [
            ExplorationExperienceReward(characterId: character.characterId, experience: 40)
        ])
    }

    @Test
    func autoReviveRestoresDefeatedPartyMembersWhenRunReturns() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = try loadGeneratedMasterData()

        let character = try guildService.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try guildService.setAutoReviveDefeatedCharactersEnabled(true)

        let startedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "デバッグの塔" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        #expect(completedRun.completion?.reason == .defeated)

        let updatedCharacter = try #require(
            guildCoreDataStore.loadRosterSnapshot().characters.first(where: { $0.characterId == character.characterId })
        )
        #expect(updatedCharacter.currentHP > 0)
    }

    @Test
    func meleeWeaponDamageUsesMeleeDamageMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(meleeDamageMultiplier: 2.0),
            isUnarmed: false,
            weaponRangeClass: .melee
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 1.0,
            weaponMultiplier: 2.0
        )
        #expect(damage == expected)
    }

    @Test
    func rangedWeaponDamageUsesRangedDamageMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(rangedDamageMultiplier: 2.0),
            isUnarmed: false,
            weaponRangeClass: .ranged
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "狩人", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 0.70,
            weaponMultiplier: 2.0
        )
        #expect(damage == expected)
    }

    @Test
    func unarmedAttackGetsBonusMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            isUnarmed: true,
            weaponRangeClass: .none
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "格闘家", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 1.0,
            weaponMultiplier: 1.5
        )
        #expect(damage == expected)
    }

    @Test
    func missedAttackCanStillTriggerCounter() throws {
        let counterSkill = MasterData.Skill(
            id: 1,
            name: "反撃",
            description: "反撃する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .interruptGrant,
                    target: nil,
                    operation: nil,
                    value: nil,
                    spellIds: [],
                    condition: nil,
                    interruptKind: .counter
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [counterSkill],
            enemyBaseStats: battleBaseStats(vitality: 20, agility: 1),
            enemySkillIds: [counterSkill.id]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                let firstActionMissed = firstTurn.actions.first?.results.contains(where: { $0.resultKind == .miss }) ?? false
                return firstActionMissed && firstTurn.actions.contains(where: { $0.actionKind == .counter })
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(firstTurn.actions.first?.actionKind == .attack)
        #expect(firstTurn.actions.first?.results.contains(where: { $0.resultKind == .miss }) == true)
        #expect(firstTurn.actions.contains(where: { $0.actionKind == .counter }))
    }

    @Test
    func spellSpecificDamageAndResistanceModifiersAffectAttackSpellDamage() throws {
        let fireSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let fireAccessSkill = MasterData.Skill(
            id: 1,
            name: "火球習得",
            description: "火球を習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [fireSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let fireBoostSkill = MasterData.Skill(
            id: 2,
            name: "火球強化",
            description: "火球を強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .battleDerivedModifier,
                    target: "spellDamageMultiplier",
                    operation: "mul",
                    value: 1.5,
                    spellIds: [fireSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let fireResistanceSkill = MasterData.Skill(
            id: 3,
            name: "火球耐性",
            description: "火球を軽減する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .battleDerivedModifier,
                    target: "magicResistanceMultiplier",
                    operation: "mul",
                    value: 0.5,
                    spellIds: [fireSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [fireAccessSkill, fireBoostSkill, fireResistanceSkill],
            spells: [fireSpell],
            allyBaseStats: battleBaseStats(vitality: 40, intelligence: 40, agility: 100),
            allyRaceSkillIds: [fireAccessSkill.id, fireBoostSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 20),
            enemySkillIds: [fireResistanceSkill.id]
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "魔導士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let resolvedAllyStatus = CharacterDerivedStatsCalculator.status(for: allyCharacter, masterData: masterData)
        let allyStatus = try #require(resolvedAllyStatus)
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 20),
            jobId: 1,
            level: 1,
            skillIds: [fireResistanceSkill.id],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)

        #expect(allyStatus.spellDamageMultiplier(for: fireSpell.id) == 1.5)
        #expect(enemyStatus.magicResistanceMultiplier(for: fireSpell.id) == 0.5)

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attackSpell))
        let basePower = Double(max(allyStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
        let damageMultiplier = allyStatus.battleDerivedStats.magicDamageMultiplier
            * allyStatus.battleDerivedStats.spellDamageMultiplier
            * allyStatus.spellDamageMultiplier(for: fireSpell.id)
            * (fireSpell.multiplier ?? 1.0)
        let resistanceMultiplier = enemyStatus.battleDerivedStats.magicResistanceMultiplier
            * enemyStatus.magicResistanceMultiplier(for: fireSpell.id)
        let expected = max(Int((basePower * damageMultiplier * resistanceMultiplier).rounded()), 1)
        #expect(damage == expected)
    }

    @Test
    func sleepSpellAppliesAilmentAndSkipsQueuedAction() throws {
        let sleepSpell = MasterData.Spell(
            id: 1,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepAccessSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [sleepSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepAccessSkill],
            spells: [sleepSpell],
            allyRaceSkillIds: [sleepAccessSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 20),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "眠術師",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 50,
                physicalDefense: 0,
                magic: 10,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [sleepSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstTurn.actions.count == 1)
        #expect(
            firstAction.results.contains(where: {
                $0.resultKind == .modifierApplied && $0.statusId == BattleAilment.sleep.rawValue
            })
        )
    }

    @Test
    func battleFallsBackToDefendWhenAllActionCandidatesAreRejected() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let allySettings = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .recoverySpell, .attackSpell, .breath]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "防御役",
                    status: allyStatus,
                    autoBattleSettings: allySettings
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(result.result == .draw)
        #expect(result.battleRecord.turns.count == 20)
        #expect(
            result.battleRecord.turns.allSatisfy { turn in
                turn.actions.allSatisfy { $0.actionKind == .defend }
            }
        )
    }

    @Test
    func explorationDrawDoesNotGrantRewards() throws {
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 100, agility: 100),
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "引き分け迷宮",
                    enemyCountCap: 1,
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let session = RunSessionRecord(
            partyRunId: 1,
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            targetFloorNumber: 1,
            startedAt: Date(timeIntervalSinceReferenceDate: 600_000),
            rootSeed: 0,
            memberSnapshots: [
                makeBattleTestCharacter(
                    id: 1,
                    name: "防御役",
                    currentHP: 100,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.attack, .recoverySpell, .attackSpell, .breath]
                    )
                )
            ],
            memberCharacterIds: [1],
            completedBattleCount: 0,
            currentPartyHPs: [100],
            memberExperienceMultipliers: [1.0],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleDropMultiplier: 1,
            partyAverageLuck: 0,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
            battleLogs: [],
            goldBuffer: 0,
            experienceRewards: [],
            dropRewards: [],
            completion: nil
        )
        var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]

        let plannedSession = try ExplorationResolver.plan(
            session: session,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )

        #expect(plannedSession.completedBattleCount == 1)
        #expect(plannedSession.battleLogs.count == 1)
        #expect(plannedSession.battleLogs.first?.battleRecord.result == .draw)
        #expect(plannedSession.completion?.reason == .draw)
        #expect(plannedSession.goldBuffer == 0)
        #expect(plannedSession.experienceRewards.isEmpty)
        #expect(plannedSession.dropRewards.isEmpty)
    }

    @Test
    func recoverySpellTargetsLowestCurrentHPMember() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healSkill = MasterData.Skill(
            id: 1,
            name: "ヒール習得",
            description: "ヒールを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [healSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerCharacter = makeBattleTestCharacter(
            id: 1,
            name: "僧侶",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id]
        )
        let firstTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 2,
                name: "前衛A",
                currentHP: 50,
                level: 5,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        let secondTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 3,
                name: "前衛B",
                currentHP: 40,
                level: 10,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                PartyBattleMember(character: healerCharacter, status: healerStatus),
                firstTarget,
                secondTarget
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:3")])
    }

    @Test
    func recoverySpellBreaksHPTiesByHigherLevel() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healSkill = MasterData.Skill(
            id: 1,
            name: "ヒール習得",
            description: "ヒールを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [healSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerCharacter = makeBattleTestCharacter(
            id: 1,
            name: "僧侶",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id]
        )
        let lowerLevelTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 2,
                name: "前衛A",
                currentHP: 40,
                level: 5,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        let higherLevelTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 3,
                name: "前衛B",
                currentHP: 40,
                level: 10,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                PartyBattleMember(character: healerCharacter, status: healerStatus),
                lowerLevelTarget,
                higherLevelTarget
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:3")])
    }

    @Test
    func encounterPlanningScalesEnemyLevelAndAllowsDuplicatesUpToCap() throws {
        let hardTitle = MasterData.Title(
            id: 2,
            key: "hard",
            name: "高難度",
            positiveMultiplier: 1.6,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let masterData = makeExplorationBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1),
            titles: [
                MasterData.Title(
                    id: 1,
                    key: "untitled",
                    name: "無名",
                    positiveMultiplier: 1.0,
                    negativeMultiplier: 1.0,
                    dropWeight: 1
                ),
                hardTitle
            ],
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "重複迷宮",
                    enemyCountCap: 3,
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 3, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let session = RunSessionRecord(
            partyRunId: 1,
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: hardTitle.id,
            targetFloorNumber: 1,
            startedAt: Date(timeIntervalSinceReferenceDate: 610_000),
            rootSeed: 0,
            memberSnapshots: [
                makeBattleTestCharacter(
                    id: 1,
                    name: "探索者",
                    currentHP: 100,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 100,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.breath, .attack, .recoverySpell, .attackSpell]
                    )
                )
            ],
            memberCharacterIds: [1],
            completedBattleCount: 0,
            currentPartyHPs: [100],
            memberExperienceMultipliers: [1.0],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleDropMultiplier: 1,
            partyAverageLuck: 0,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
            battleLogs: [],
            goldBuffer: 0,
            experienceRewards: [],
            dropRewards: [],
            completion: nil
        )
        var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]

        let plannedSession = try ExplorationResolver.plan(
            session: session,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )
        let enemySnapshots = plannedSession.battleLogs.first?.combatants.filter { $0.side == .enemy } ?? []

        #expect(enemySnapshots.count == 3)
        #expect(enemySnapshots.allSatisfy { $0.name == "テスト敵" })
        #expect(enemySnapshots.allSatisfy { $0.level == 5 })
    }

    @Test
    func defendingHalvesPhysicalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .attack])
        let attackResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(attackResult.value == expectedDamage)
        #expect(attackResult.flags.contains(.guarded))
    }

    @Test
    func defendingHalvesBreathDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 20
            ),
            canUseBreath: true
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "竜人",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 100,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.breath, .attack, .recoverySpell, .attackSpell]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .breath])
        let breathResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.breathPower - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(breathResult.value == expectedDamage)
        #expect(breathResult.flags.contains(.guarded))
    }

    @Test
    func defendingHalvesAttackSpellDamage() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .attackSpell])
        let spellResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(spellResult.value == expectedDamage)
        #expect(spellResult.flags.contains(.guarded))
    }

    @Test
    func attackSpellTargetsDistinctEnemiesWithoutDuplicates() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "連鎖火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 2,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.targetIds.count == 2)
        #expect(Set(firstAction.targetIds).count == 2)
    }

    @Test
    func attackSpellTargetsAllLivingEnemiesWhenTargetCountExceedsLivingCount() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 3,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.targetIds.count == 2)
        #expect(Set(firstAction.targetIds).count == 2)
    }

    @Test
    func sameSpellIsUsedAtMostOncePerBattle() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let attackSpellSkill = MasterData.Skill(
            id: 1,
            name: "火球習得",
            description: "火球を習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [attackSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [attackSpellSkill],
            spells: [attackSpell],
            allyRaceSkillIds: [attackSpellSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "魔術師",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 1,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") }

        #expect(allyActions.filter { $0.actionKind == .attackSpell }.count == 1)
        #expect(allyActions.dropFirst().allSatisfy { $0.actionKind == .defend })
    }

    @Test
    func simultaneousInterruptsResolveInPriorityOrder() throws {
        let counterSkill = MasterData.Skill(
            id: 1,
            name: "反撃",
            description: "反撃する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .interruptGrant,
                    target: nil,
                    operation: nil,
                    value: nil,
                    spellIds: [],
                    condition: nil,
                    interruptKind: .counter
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [counterSkill],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1),
            enemySkillIds: [counterSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.extraAttack]
        )
        let pursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 500),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.pursuit]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus),
                    makePartyBattleMember(id: 2, name: "狩人", status: pursuerStatus)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                return Array(firstTurn.actions.prefix(4).map(\.actionKind)) == [
                    .attack,
                    .counter,
                    .extraAttack,
                    .pursuit
                ]
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(4).map(\.actionKind)) == [
            .attack,
            .counter,
            .extraAttack,
            .pursuit
        ])
    }

    @Test
    func completedExplorationLogsArePrunedByRetentionCount() async throws {
        let previousValue = UserDefaults.standard.object(forKey: ExplorationLogRetentionLimit.userDefaultsKey)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: ExplorationLogRetentionLimit.userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ExplorationLogRetentionLimit.userDefaultsKey)
            }
        }

        UserDefaults.standard.set(2, forKey: ExplorationLogRetentionLimit.userDefaultsKey)

        let explorationCoreDataStore = ExplorationCoreDataStore(
            container: PersistenceController(inMemory: true).container
        )
        for partyRunId in 1...201 {
            try await explorationCoreDataStore.insertRun(
                makeCompletedRunRecord(
                    partyRunId: partyRunId,
                    startedAt: Date(timeIntervalSinceReferenceDate: Double(partyRunId) * 1_000)
                )
            )
        }

        #expect(try await explorationCoreDataStore.pruneCompletedRunsExceedingRetentionLimit())
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1) == nil)
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 2) != nil)
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 201) != nil)
    }

    @Test
    func publishFormatsPartyPrefixedDisplayText() {
        let masterData = itemDropNotificationTestMasterData()
        let masterDataStore = MasterDataStore(phase: .loaded(masterData))
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let service = ItemDropNotificationService(
            masterDataStore: masterDataStore,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 3,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: CompositeItemID(
                                baseSuperRareId: 1,
                                baseTitleId: 1,
                                baseItemId: 1,
                                jewelSuperRareId: 0,
                                jewelTitleId: 0,
                                jewelItemId: 0
                            ),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        ),
                        ExplorationDropReward(
                            itemID: CompositeItemID.baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 2
                        )
                    ]
                )
            ]
        )

        #expect(service.droppedItems.count == 2)
        #expect(service.droppedItems[0].displayText == "PT3：極光剣")
        #expect(service.droppedItems[0].isSuperRare)
        #expect(service.droppedItems[1].displayText == "PT3：剣")
    }

    @Test
    func clearRemovesPublishedNotifications() {
        let masterDataStore = MasterDataStore(phase: .loaded(itemDropNotificationTestMasterData()))
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let service = ItemDropNotificationService(
            masterDataStore: masterDataStore,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )
        service.clear()

        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForDisabledTitle() {
        let masterDataStore = MasterDataStore(phase: .loaded(itemDropNotificationTestMasterData()))
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettings.setTitleEnabled(false, titleId: 1, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterDataStore: masterDataStore,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1, titleId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettings.allowsNotification(
            for: .baseItem(itemId: 1, titleId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForDisabledSuperRare() {
        let masterDataStore = MasterDataStore(phase: .loaded(itemDropNotificationTestMasterData()))
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettings.setSuperRareEnabled(false, superRareId: 1, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterDataStore: masterDataStore,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1, superRareId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettings.allowsNotification(
            for: .baseItem(itemId: 1, superRareId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForIgnoredNormalRarityItems() {
        let masterDataStore = MasterDataStore(phase: .loaded(itemDropNotificationTestMasterData()))
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettings.setShowsNormalRarityItems(false, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterDataStore: masterDataStore,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettings.allowsNotification(
            for: .baseItem(itemId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

}

@MainActor
private func matchesRecruitNamePool(character: CharacterRecord, masterData: MasterData) -> Bool {
    switch character.portraitGender {
    case .male:
        masterData.recruitNames.male.contains(character.name)
    case .female:
        masterData.recruitNames.female.contains(character.name)
    case .unisex:
        masterData.recruitNames.unisex.contains(character.name)
    }
}

private func loadGeneratedMasterData() throws -> MasterData {
    if let testHostPath = ProcessInfo.processInfo.environment["TEST_HOST"] {
        let hostBundleURL = URL(fileURLWithPath: testHostPath).deletingLastPathComponent()
        if let hostBundle = Bundle(url: hostBundleURL),
           let fileURL = hostBundle.url(forResource: "masterdata", withExtension: "json") {
            return try MasterDataLoader.load(fileURL: fileURL)
        }
    }

    for bundle in [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
        if let fileURL = bundle.url(forResource: "masterdata", withExtension: "json") {
            return try MasterDataLoader.load(fileURL: fileURL)
        }
    }

    let fileURL = generatedMasterDataURL()
    return try MasterDataLoader.load(fileURL: fileURL)
}

private func itemDropNotificationTestMasterData() -> MasterData {
    MasterData(
        metadata: MasterData.Metadata(generator: "test"),
        races: [],
        jobs: [],
        aptitudes: [],
        items: [
            MasterData.Item(
                id: 1,
                name: "剣",
                category: .sword,
                rarity: .normal,
                basePrice: 10,
                nativeBaseStats: MasterData.BaseStats(
                    vitality: 0,
                    strength: 0,
                    mind: 0,
                    intelligence: 0,
                    agility: 0,
                    luck: 0
                ),
                nativeBattleStats: MasterData.BattleStats(
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
                ),
                skillIds: [],
                rangeClass: .melee,
                normalDropTier: 1
            )
        ],
        titles: [
            MasterData.Title(
                id: 1,
                key: "light",
                name: "光",
                positiveMultiplier: 1,
                negativeMultiplier: 1,
                dropWeight: 1
            )
        ],
        superRares: [
            MasterData.SuperRare(
                id: 1,
                name: "極",
                skillIds: []
            )
        ],
        skills: [],
        spells: [],
        recruitNames: MasterData.RecruitNames(
            male: [],
            female: [],
            unisex: []
        ),
        enemies: [],
        labyrinths: []
    )
}

private func generatedMasterDataURL() -> URL {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot = testsDirectory.deletingLastPathComponent()
    return repositoryRoot.appending(path: "Generator/Output/masterdata.json")
}

@MainActor
private func promoteCharacter(
    characterId: Int,
    level: Int,
    in container: NSPersistentContainer
) throws {
    let context = container.viewContext
    let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "characterId == %d", characterId)
    let character = try #require(context.fetch(request).first)
    character.level = Int64(level)
    character.currentHP = 1
    try context.save()
}

@MainActor
private func setCurrentHP(
    characterId: Int,
    to currentHP: Int,
    in container: NSPersistentContainer
) throws {
    let context = container.viewContext
    let request = NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "characterId == %d", characterId)
    let character = try #require(context.fetch(request).first)
    character.currentHP = Int64(currentHP)
    try context.save()
}

@MainActor
private func raceId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.races.first(where: { $0.name == name })?.id)
}

@MainActor
private func jobId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.jobs.first(where: { $0.name == name })?.id)
}

@MainActor
private func skillId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.skills.first(where: { $0.name == name })?.id)
}

@MainActor
private func spellIds(named names: [String], in masterData: MasterData) throws -> [Int] {
    try names.map { name in
        try #require(masterData.spells.first(where: { $0.name == name })?.id)
    }
}

private func battleBaseStats(
    vitality: Int = 0,
    strength: Int = 0,
    mind: Int = 0,
    intelligence: Int = 0,
    agility: Int = 0,
    luck: Int = 0
) -> MasterData.BaseStats {
    MasterData.BaseStats(
        vitality: vitality,
        strength: strength,
        mind: mind,
        intelligence: intelligence,
        agility: agility,
        luck: luck
    )
}

private func battleCharacterBaseStats(
    vitality: Int = 0,
    strength: Int = 0,
    mind: Int = 0,
    intelligence: Int = 0,
    agility: Int = 0,
    luck: Int = 0
) -> CharacterBaseStats {
    CharacterBaseStats(
        vitality: vitality,
        strength: strength,
        mind: mind,
        intelligence: intelligence,
        agility: agility,
        luck: luck
    )
}

private func makeBattleDerivedStats(
    physicalDamageMultiplier: Double = 1.0,
    magicDamageMultiplier: Double = 1.0,
    spellDamageMultiplier: Double = 1.0,
    criticalDamageMultiplier: Double = 1.0,
    meleeDamageMultiplier: Double = 1.0,
    rangedDamageMultiplier: Double = 1.0,
    actionSpeedMultiplier: Double = 1.0,
    physicalResistanceMultiplier: Double = 1.0,
    magicResistanceMultiplier: Double = 1.0,
    breathResistanceMultiplier: Double = 1.0
) -> CharacterBattleDerivedStats {
    CharacterBattleDerivedStats(
        physicalDamageMultiplier: physicalDamageMultiplier,
        magicDamageMultiplier: magicDamageMultiplier,
        spellDamageMultiplier: spellDamageMultiplier,
        criticalDamageMultiplier: criticalDamageMultiplier,
        meleeDamageMultiplier: meleeDamageMultiplier,
        rangedDamageMultiplier: rangedDamageMultiplier,
        actionSpeedMultiplier: actionSpeedMultiplier,
        physicalResistanceMultiplier: physicalResistanceMultiplier,
        magicResistanceMultiplier: magicResistanceMultiplier,
        breathResistanceMultiplier: breathResistanceMultiplier
    )
}

private func makeBattleTestStatus(
    baseStats: CharacterBaseStats = CharacterBaseStats(
        vitality: 0,
        strength: 0,
        mind: 0,
        intelligence: 0,
        agility: 100,
        luck: 0
    ),
    battleStats: CharacterBattleStats,
    battleDerivedStats: CharacterBattleDerivedStats = .baseline,
    skillIds: [Int] = [],
    spellIds: [Int] = [],
    interruptKinds: [InterruptKind] = [],
    canUseBreath: Bool = false,
    isUnarmed: Bool = false,
    weaponRangeClass: ItemRangeClass = .melee,
    spellDamageMultipliersBySpellID: [Int: Double] = [:],
    spellResistanceMultipliersBySpellID: [Int: Double] = [:]
) -> CharacterStatus {
    CharacterStatus(
        baseStats: baseStats,
        battleStats: battleStats,
        battleDerivedStats: battleDerivedStats,
        skillIds: skillIds,
        spellIds: spellIds,
        interruptKinds: interruptKinds,
        canUseBreath: canUseBreath,
        isUnarmed: isUnarmed,
        weaponRangeClass: weaponRangeClass,
        spellDamageMultipliersBySpellID: spellDamageMultipliersBySpellID,
        spellResistanceMultipliersBySpellID: spellResistanceMultipliersBySpellID
    )
}

private func makeAutoBattleSettings(
    breath: Int,
    attack: Int,
    recoverySpell: Int,
    attackSpell: Int,
    priority: [BattleActionKind]
) -> CharacterAutoBattleSettings {
    CharacterAutoBattleSettings(
        rates: CharacterActionRates(
            breath: breath,
            attack: attack,
            recoverySpell: recoverySpell,
            attackSpell: attackSpell
        ),
        priority: priority
    )
}

private func makePartyBattleMember(
    id: Int,
    name: String,
    status: CharacterStatus,
    currentHP: Int? = nil,
    autoBattleSettings: CharacterAutoBattleSettings? = nil
) -> PartyBattleMember {
    let battleSettings = autoBattleSettings ?? makeAutoBattleSettings(
        breath: 0,
        attack: 100,
        recoverySpell: 0,
        attackSpell: 0,
        priority: [.attack, .breath, .recoverySpell, .attackSpell]
    )
    let character = makeBattleTestCharacter(
        id: id,
        name: name,
        currentHP: currentHP ?? status.maxHP,
        autoBattleSettings: battleSettings
    )
    return PartyBattleMember(character: character, status: status)
}

private func makeBattleTestCharacter(
    id: Int,
    name: String,
    currentHP: Int,
    level: Int = 1,
    autoBattleSettings: CharacterAutoBattleSettings
) -> CharacterRecord {
    CharacterRecord(
        characterId: id,
        name: name,
        raceId: 1,
        previousJobId: 0,
        currentJobId: 1,
        aptitudeId: 1,
        portraitGender: .male,
        experience: 0,
        level: level,
        currentHP: currentHP,
        autoBattleSettings: autoBattleSettings
    )
}

private func makeBattleTestMasterData(
    skills: [MasterData.Skill] = [],
    spells: [MasterData.Spell] = [],
    allyBaseStats: MasterData.BaseStats = battleBaseStats(),
    allyRaceSkillIds: [Int] = [],
    enemyBaseStats: MasterData.BaseStats,
    enemySkillIds: [Int] = [],
    enemyActionRates: MasterData.ActionRates = MasterData.ActionRates(
        breath: 0,
        attack: 0,
        recoverySpell: 0,
        attackSpell: 0
    ),
    enemyActionPriority: [BattleActionKind] = [.attack, .breath, .recoverySpell, .attackSpell]
) -> MasterData {
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

    return MasterData(
        metadata: MasterData.Metadata(generator: "test"),
        races: [
            MasterData.Race(
                id: 1,
                name: "テスト種族",
                levelCap: 99,
                baseHirePrice: 1,
                baseStats: allyBaseStats,
                skillIds: allyRaceSkillIds
            )
        ],
        jobs: [
            MasterData.Job(
                id: 1,
                name: "テスト職",
                hirePriceMultiplier: 1.0,
                coefficients: coefficients,
                passiveSkillIds: [],
                levelSkillIds: [],
                jobChangeRequirement: nil
            )
        ],
        aptitudes: [
            MasterData.Aptitude(
                id: 1,
                name: "テスト資質"
            )
        ],
        items: [],
        titles: [],
        superRares: [],
        skills: skills,
        spells: spells,
        recruitNames: MasterData.RecruitNames(
            male: [],
            female: [],
            unisex: []
        ),
        enemies: [
            MasterData.Enemy(
                id: 1,
                name: "テスト敵",
                enemyRace: .monster,
                jobId: 1,
                baseStats: enemyBaseStats,
                goldBaseValue: 0,
                experienceBaseValue: 0,
                skillIds: enemySkillIds,
                rareDropItemIds: [],
                actionRates: enemyActionRates,
                actionPriority: enemyActionPriority
            )
        ],
        labyrinths: []
    )
}

private func makeExplorationBattleTestMasterData(
    skills: [MasterData.Skill] = [],
    spells: [MasterData.Spell] = [],
    allyBaseStats: MasterData.BaseStats = battleBaseStats(),
    allyRaceSkillIds: [Int] = [],
    enemyBaseStats: MasterData.BaseStats,
    enemySkillIds: [Int] = [],
    enemyActionRates: MasterData.ActionRates = MasterData.ActionRates(
        breath: 0,
        attack: 0,
        recoverySpell: 0,
        attackSpell: 0
    ),
    enemyActionPriority: [BattleActionKind] = [.attack, .breath, .recoverySpell, .attackSpell],
    titles: [MasterData.Title] = [
        MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
    ],
    labyrinths: [MasterData.Labyrinth]
) -> MasterData {
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

    return MasterData(
        metadata: MasterData.Metadata(generator: "test"),
        races: [
            MasterData.Race(
                id: 1,
                name: "テスト種族",
                levelCap: 99,
                baseHirePrice: 1,
                baseStats: allyBaseStats,
                skillIds: allyRaceSkillIds
            )
        ],
        jobs: [
            MasterData.Job(
                id: 1,
                name: "テスト職",
                hirePriceMultiplier: 1.0,
                coefficients: coefficients,
                passiveSkillIds: [],
                levelSkillIds: [],
                jobChangeRequirement: nil
            )
        ],
        aptitudes: [
            MasterData.Aptitude(
                id: 1,
                name: "テスト資質"
            )
        ],
        items: [],
        titles: titles,
        superRares: [],
        skills: skills,
        spells: spells,
        recruitNames: MasterData.RecruitNames(
            male: [],
            female: [],
            unisex: []
        ),
        enemies: [
            MasterData.Enemy(
                id: 1,
                name: "テスト敵",
                enemyRace: .monster,
                jobId: 1,
                baseStats: enemyBaseStats,
                goldBaseValue: 10,
                experienceBaseValue: 10,
                skillIds: enemySkillIds,
                rareDropItemIds: [],
                actionRates: enemyActionRates,
                actionPriority: enemyActionPriority
            )
        ],
        labyrinths: labyrinths
    )
}

private func firstResolvedBattle(
    matchingSeeds seeds: Range<Int>,
    partyMembers: [PartyBattleMember],
    masterData: MasterData,
    predicate: (SingleBattleResult) -> Bool
) throws -> SingleBattleResult? {
    for seed in seeds {
        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                rootSeed: UInt64(seed),
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: partyMembers,
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        if predicate(result) {
            return result
        }
    }

    return nil
}

private func firstDamageValue(
    in result: SingleBattleResult,
    actionKind: BattleLogActionKind
) -> Int? {
    result.battleRecord.turns
        .flatMap(\.actions)
        .first(where: { $0.actionKind == actionKind })?
        .results
        .first(where: { $0.resultKind == .damage })?
        .value
}

private func expectedPhysicalDamage(
    attacker: CharacterStatus,
    defender: CharacterStatus,
    formationMultiplier: Double,
    weaponMultiplier: Double
) -> Int {
    max(
        Int(
            (
                Double(max(attacker.battleStats.physicalAttack - defender.battleStats.physicalDefense, 0))
                * attacker.battleDerivedStats.physicalDamageMultiplier
                * formationMultiplier
                * weaponMultiplier
                * defender.battleDerivedStats.physicalResistanceMultiplier
            ).rounded()
        ),
        1
    )
}

private func makeCompletedRunRecord(
    partyRunId: Int,
    startedAt: Date
) -> RunSessionRecord {
    RunSessionRecord(
        partyRunId: partyRunId,
        partyId: 1,
        labyrinthId: 1,
        selectedDifficultyTitleId: 1,
        targetFloorNumber: 1,
        startedAt: startedAt,
        rootSeed: UInt64(partyRunId),
        memberSnapshots: [],
        memberCharacterIds: [],
        completedBattleCount: 0,
        currentPartyHPs: [],
        memberExperienceMultipliers: [],
        goldMultiplier: 1,
        rareDropMultiplier: 1,
        titleDropMultiplier: 1,
        partyAverageLuck: 0,
        latestBattleFloorNumber: nil,
        latestBattleNumber: nil,
        latestBattleOutcome: nil,
        battleLogs: [],
        goldBuffer: 0,
        experienceRewards: [],
        dropRewards: [],
        completion: RunCompletionRecord(
            completedAt: startedAt.addingTimeInterval(60),
            reason: .cleared,
            gold: 0,
            experienceRewards: [],
            dropRewards: []
        )
    )
}

private func debugItemGenerationMasterData() -> MasterData {
    let baseStats = MasterData.BaseStats(
        vitality: 0,
        strength: 0,
        mind: 0,
        intelligence: 0,
        agility: 0,
        luck: 0
    )
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

    return MasterData(
        metadata: MasterData.Metadata(generator: "test"),
        races: [],
        jobs: [],
        aptitudes: [],
        items: [
            MasterData.Item(
                id: 1,
                name: "テスト剣",
                category: .sword,
                rarity: .normal,
                basePrice: 1,
                nativeBaseStats: baseStats,
                nativeBattleStats: battleStats,
                skillIds: [],
                rangeClass: .melee,
                normalDropTier: 1
            ),
            MasterData.Item(
                id: 2,
                name: "テスト宝石",
                category: .jewel,
                rarity: .normal,
                basePrice: 1,
                nativeBaseStats: baseStats,
                nativeBattleStats: battleStats,
                skillIds: [],
                rangeClass: .none,
                normalDropTier: 1
            )
        ],
        titles: [
            MasterData.Title(
                id: 1,
                key: "test",
                name: "テスト",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        ],
        superRares: [
            MasterData.SuperRare(
                id: 1,
                name: "極",
                skillIds: []
            )
        ],
        skills: [],
        spells: [],
        recruitNames: MasterData.RecruitNames(
            male: [],
            female: [],
            unisex: []
        ),
        enemies: [],
        labyrinths: []
    )
}
