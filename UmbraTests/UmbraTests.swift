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
                    labyrinthId: try #require(masterData.labyrinths.first?.id)
                ),
                ConfiguredRunStart(
                    partyId: 2,
                    labyrinthId: try #require(masterData.labyrinths.first?.id)
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
            startedAt: Date(timeIntervalSinceReferenceDate: 200_000),
            maximumLoopCount: 1,
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
            startedAt: startedAt,
            maximumLoopCount: 1,
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
            startedAt: startedAt,
            maximumLoopCount: 1,
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
            startedAt: startedAt,
            maximumLoopCount: 1,
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
            startedAt: startedAt,
            maximumLoopCount: 1,
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
            startedAt: startedAt,
            maximumLoopCount: 1,
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
                runId: "spell-specific",
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
                runId: "sleep-test",
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
        try await explorationCoreDataStore.insertRun(
            makeCompletedRunRecord(
                partyRunId: 1,
                startedAt: Date(timeIntervalSinceReferenceDate: 1_000)
            )
        )
        try await explorationCoreDataStore.insertRun(
            makeCompletedRunRecord(
                partyRunId: 2,
                startedAt: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        )
        try await explorationCoreDataStore.insertRun(
            makeCompletedRunRecord(
                partyRunId: 3,
                startedAt: Date(timeIntervalSinceReferenceDate: 3_000)
            )
        )

        #expect(try await explorationCoreDataStore.pruneCompletedRunsExceedingRetentionLimit())
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1) == nil)
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 2) != nil)
        #expect(try await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 3) != nil)
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
        level: 1,
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

private func firstResolvedBattle(
    matchingSeeds seeds: Range<Int>,
    partyMembers: [PartyBattleMember],
    masterData: MasterData,
    predicate: (SingleBattleResult) -> Bool
) throws -> SingleBattleResult? {
    for seed in seeds {
        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: "test-\(seed)",
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
        targetFloorNumber: 1,
        startedAt: startedAt,
        rootSeed: UInt64(partyRunId),
        maximumLoopCount: 1,
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
            completedLoopCount: 1,
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
