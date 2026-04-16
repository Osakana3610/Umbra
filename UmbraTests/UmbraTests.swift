// Verifies runtime master data and guild hiring logic.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraTests {
    // MARK: - Master Data and Bootstrap

    @Test
    func generatedMasterDataDecodes() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "草原")
    }

    @Test
    func recruitNamesDecodeByGender() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.recruitNames.male.isEmpty)
        #expect(!masterData.recruitNames.female.isEmpty)
        #expect(!masterData.recruitNames.unisex.isEmpty)
    }

    @Test
    func itemBrowserFilterCatalogCollectsVisibleCategoriesAndTitles() throws {
        let masterData = try loadGeneratedMasterData()
        let roughTitleID = try #require(masterData.titles.first(where: { $0.key == "rough" })?.id)
        let untitledTitle = try #require(masterData.titles.first(where: { $0.key == "untitled" }))
        let swordID = try itemId(for: .sword, in: masterData)
        let armorID = try itemId(for: .armor, in: masterData)
        let jewelID = try itemId(for: .jewel, in: masterData)
        let catalog = ItemBrowserFilterCatalog(
            itemIDs: [
                CompositeItemID(
                    baseSuperRareId: 0,
                    baseTitleId: 0,
                    baseItemId: swordID,
                    jewelSuperRareId: 0,
                    jewelTitleId: roughTitleID,
                    jewelItemId: jewelID
                ),
                .baseItem(itemId: armorID)
            ],
            masterData: masterData
        )

        #expect(catalog.categories == [.sword, .armor])
        #expect(catalog.titles.map(\.id) == masterData.titles.map(\.id))
        #expect(catalog.titles.first(where: { $0.id == untitledTitle.id })?.label == "無称号")
        #expect(untitledTitle.name.isEmpty)
        #expect(catalog.titles.map(\.id).contains(roughTitleID))
    }

    @Test
    func itemBrowserFilterMatchesCategoryTitleAndSuperRareSelections() throws {
        let masterData = try loadGeneratedMasterData()
        let roughTitleID = try #require(masterData.titles.first(where: { $0.key == "rough" })?.id)
        let untitledTitleID = try #require(masterData.titles.first(where: { $0.key == "untitled" })?.id)
        let superRareID = try #require(masterData.superRares.first?.id)
        let swordID = try itemId(for: .sword, in: masterData)
        let armorID = try itemId(for: .armor, in: masterData)
        let filter = ItemBrowserFilter(
            hiddenCategories: [.armor],
            hiddenTitleIDs: [untitledTitleID],
            showsOnlySuperRare: true
        )

        #expect(filter.matches(
            itemID: .baseItem(
                itemId: swordID,
                titleId: roughTitleID,
                superRareId: superRareID
            ),
            category: .sword
        ))
        #expect(filter.matches(
            itemID: .baseItem(
                itemId: swordID,
                titleId: untitledTitleID,
                superRareId: superRareID
            ),
            category: .sword
        ) == false)
        #expect(filter.matches(
            itemID: .baseItem(
                itemId: armorID,
                titleId: roughTitleID,
                superRareId: superRareID
            ),
            category: .armor
        ) == false)
        #expect(filter.matches(
            itemID: .baseItem(
                itemId: swordID,
                titleId: roughTitleID
            ),
            category: .sword
        ) == false)
    }

    @Test
    func guildCoreDataStoreCreatesInitialPlayerState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)

        let snapshot = try guildCoreDataStore.loadRosterSnapshot()
        let parties = try guildCoreDataStore.loadParties()

        #expect(snapshot.playerState == .initial)
        #expect(snapshot.playerState.catTicketCount == 10)
        #expect(snapshot.characters.isEmpty)
        #expect(parties == [PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [])])
    }

    @Test
    func playerBackgroundTimestampAndPartyPendingRunsPersist() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let backgroundedAt = Date(timeIntervalSinceReferenceDate: 12_345)
        let pendingStartedAt = Date(timeIntervalSinceReferenceDate: 12_346)

        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.lastBackgroundedAt = backgroundedAt
        try guildCoreDataStore.saveRosterSnapshot(snapshot)

        var parties = try guildCoreDataStore.loadParties()
        parties[0].pendingAutomaticRunCount = 2
        parties[0].pendingAutomaticRunStartedAt = pendingStartedAt
        try guildCoreDataStore.saveParties(parties)

        let reloadedSnapshot = try guildCoreDataStore.loadFreshRosterSnapshot()
        let reloadedParties = try guildCoreDataStore.loadParties()

        #expect(reloadedSnapshot.playerState.lastBackgroundedAt == backgroundedAt)
        #expect(reloadedParties == [
            PartyRecord(
                partyId: 1,
                name: "パーティ1",
                memberCharacterIds: [],
                pendingAutomaticRunCount: 2,
                pendingAutomaticRunStartedAt: pendingStartedAt
            )
        ])
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

        let raceId = try #require(masterData.races.first?.id)
        let jobId = try #require(masterData.jobs.first?.id)
        let expectedHireCost = try #require(
            GuildHiring.price(
                raceId: raceId,
                jobId: jobId,
                masterData: masterData
            )
        )
        #expect(result.hireCost == expectedHireCost)
        #expect(result.playerState.gold == PlayerState.initial.gold - expectedHireCost)
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
    func hirePriceCapsAtMaximumEconomicPrice() {
        let masterData = MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [
                MasterData.Race(
                    id: 1,
                    key: "expensive-race",
                    name: "高額種族",
                    levelCap: 99,
                    baseHirePrice: 100_000_000,
                    baseStats: battleBaseStats(),
                    passiveSkillIds: [],
                    levelSkillIds: []
                )
            ],
            jobs: [
                MasterData.Job(
                    id: 1,
                    key: "expensive-job",
                    name: "高額職",
                    hirePriceMultiplier: 2.0,
                    coefficients: MasterData.BattleStatCoefficients(
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
                    ),
                    passiveSkillIds: [],
                    levelSkillIds: [],
                    jobChangeRequirement: nil
                )
            ],
            aptitudes: [],
            items: [],
            titles: [],
            superRares: [],
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

        #expect(GuildHiring.price(raceId: 1, jobId: 1, masterData: masterData) == EconomyPricing.maximumEconomicPrice)
    }

    @Test
    func partyUnlockCostCapsFinalUnlockOnly() {
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 1) == 2_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 2) == 4_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 3) == 8_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 4) == 16_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 5) == 32_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 6) == 64_000_000)
        #expect(PartyRecord.unlockCost(forExistingPartyCount: 7) == EconomyPricing.maximumEconomicPrice)

        #expect(PartyRecord.unlockRequiresCappedJewel(forExistingPartyCount: 6) == false)
        #expect(PartyRecord.unlockRequiresCappedJewel(forExistingPartyCount: 7))
    }

    @Test
    func finalPartyUnlockConsumesCappedJewel() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [],
            jobs: [],
            aptitudes: [],
            items: [
                MasterData.Item(
                    id: 1,
                    name: "極宝石",
                    category: .jewel,
                    rarity: .normal,
                    basePrice: 200_000_000,
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
                    rangeClass: .ranged,
                    normalDropTier: 1
                )
            ],
            titles: [],
            superRares: [],
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
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.gold = 120_000_000
        let parties = (1...7).map { partyId in
            PartyRecord(
                partyId: partyId,
                name: PartyRecord.defaultName(for: partyId),
                memberCharacterIds: []
            )
        }
        let cappedJewel = CompositeItemID.baseItem(itemId: 1)

        try guildCoreDataStore.saveRosterState(
            snapshot,
            parties: parties,
            inventoryStacks: [CompositeItemStack(itemID: cappedJewel, count: 1)]
        )

        let updatedParties = try guildService.unlockParty(
            consuming: EconomicCapJewelSelection(
                itemID: cappedJewel,
                characterId: nil
            ),
            masterData: masterData
        )
        let reloadedSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        let reloadedInventory = try guildCoreDataStore.loadInventoryStacks()

        #expect(updatedParties.count == 8)
        #expect(reloadedSnapshot.playerState.gold == 20_000_001)
        #expect(reloadedInventory.isEmpty)
    }

    // MARK: - Character Status and Equipment Aggregation

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
            portraitAssetID: "job_knight_male",
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
            maxHP: 347,
            physicalAttack: 47,
            physicalDefense: 35,
            magic: 32,
            magicDefense: 29,
            healing: 25,
            accuracy: 9,
            evasion: 5,
            attackCount: 1,
            criticalRate: 1,
            breathPower: 42
        ))
        #expect(status.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            attackMagicMultiplier: 1.0,
            healingMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.0,
            meleeDamageMultiplier: 1.0,
            rangedDamageMultiplier: 1.0,
            actionSpeedMultiplier: 1.0,
            physicalResistanceMultiplier: 1.0,
            magicResistanceMultiplier: 0.94,
            breathResistanceMultiplier: 1.0
        ))
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
            portraitAssetID: "job_magician_male",
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
            portraitAssetID: "job_hunter_female",
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
            named: ["炎", "氷", "電撃", "魔法バフ"],
            in: masterData
        )))
        #expect(spellcastingStatus.battleStats.magic == 155)
        #expect(spellcastingStatus.skillIds.count == Set(spellcastingStatus.skillIds).count)

        #expect(breathStatus.canUseBreath)
        #expect(breathStatus.interruptKinds == [.counter, .pursuit])
        #expect(breathStatus.battleStats.breathPower == 60)
        #expect(breathStatus.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            attackMagicMultiplier: 1.0,
            healingMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.0,
            meleeDamageMultiplier: 1.0,
            rangedDamageMultiplier: 1.1,
            actionSpeedMultiplier: 1.1,
            physicalResistanceMultiplier: 0.8,
            magicResistanceMultiplier: 0.94,
            breathResistanceMultiplier: 0.8
        ))
    }

    @Test
    func completeStatusCalculationUsesHighestNormalDropJewelizeChance() throws {
        let masterData = try loadGeneratedMasterData()
        let character = CharacterRecord(
            characterId: 1,
            name: "テスト錬金術師",
            raceId: try raceId(named: "人間", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "錬金術師", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .male,
            portraitAssetID: "job_alchemist_male",
            experience: 0,
            level: 75,
            currentHP: 1,
            autoBattleSettings: .default
        )

        let status = try #require(CharacterDerivedStatsCalculator.status(for: character, masterData: masterData))

        #expect(abs(status.normalDropJewelizeChance - 0.05) < 0.000_000_001)
    }

    @Test
    func completeStatusCalculationAppliesAllBattleStatMultiplierAndRevokesGrantedSpell() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let grantSkill = MasterData.Skill(
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
        let revokeSkill = MasterData.Skill(
            id: 2,
            name: "火球忘却",
            description: "火球を忘却する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "revoke",
                    value: nil,
                    spellIds: [attackSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let allStatSkill = MasterData.Skill(
            id: 3,
            name: "全能力強化",
            description: "全戦闘能力値が上昇する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .allBattleStatMultiplier,
                    target: nil,
                    operation: nil,
                    value: 1.5,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [grantSkill, revokeSkill, allStatSkill],
            spells: [attackSpell],
            allyBaseStats: battleBaseStats(vitality: 10, strength: 10),
            allyRaceSkillIds: [grantSkill.id, revokeSkill.id, allStatSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let character = makeBattleTestCharacter(
            id: 1,
            name: "賢者",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )

        let status = try #require(CharacterDerivedStatsCalculator.status(for: character, masterData: masterData))

        #expect(status.battleStats.maxHP == 45)
        #expect(status.battleStats.physicalAttack == 9)
        #expect(status.spellIds.isEmpty)
    }

    @Test
    func unarmedConditionalSkillOnlyAppliesWhileUnarmed() throws {
        let unarmedSkill = MasterData.Skill(
            id: 1,
            name: "素手攻撃強化",
            description: "格闘状態のとき物理攻撃が増加する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .battleStatModifier,
                    target: "physicalAttack",
                    operation: "pctAdd",
                    value: 1.0,
                    spellIds: [],
                    condition: .unarmed,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [unarmedSkill],
            allyBaseStats: battleBaseStats(strength: 10),
            allyRaceSkillIds: [unarmedSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 1)
        )

        let armedStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(strength: 10),
                jobId: 1,
                level: 1,
                skillIds: [unarmedSkill.id],
                masterData: masterData,
                isUnarmed: false
            )
        )
        let unarmedStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(strength: 10),
                jobId: 1,
                level: 1,
                skillIds: [unarmedSkill.id],
                masterData: masterData,
                isUnarmed: true
            )
        )

        #expect(armedStatus.battleStats.physicalAttack == 6)
        #expect(unarmedStatus.battleStats.physicalAttack == 12)
    }

    @Test
    func enemyStatusIncludesCurrentJobPassiveAndUnlockedLevelSkills() throws {
        let passiveSkill = MasterData.Skill(
            id: 1,
            name: "職パッシブ攻撃補正",
            description: "物理攻撃を固定値強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .battleStatModifier,
                    target: "physicalAttack",
                    operation: "flatAdd",
                    value: 5,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let levelSkill = MasterData.Skill(
            id: 2,
            name: "職レベル魔力補正",
            description: "魔力を固定値強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .battleStatModifier,
                    target: "magic",
                    operation: "flatAdd",
                    value: 7,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [passiveSkill, levelSkill],
            jobPassiveSkillIds: [passiveSkill.id],
            jobLevelSkillIds: [levelSkill.id],
            enemyBaseStats: battleBaseStats(strength: 10, intelligence: 8)
        )
        let enemy = try #require(masterData.enemies.first)
        let status = try #require(
            CharacterDerivedStatsCalculator.status(
                for: enemy,
                level: 15,
                masterData: masterData
            )
        )

        #expect(status.skillIds == [passiveSkill.id, levelSkill.id])
        #expect(status.battleStats.physicalAttack == 95)
        #expect(status.battleStats.magic == 79)
    }

    @Test
    func equipmentAggregationKeepsBothWeaponRangesWhenMixed() throws {
        let masterData = try loadGeneratedMasterData()
        let meleeItemID = try #require(masterData.items.first(where: { $0.rangeClass == .melee })?.id)
        let rangedItemID = try #require(masterData.items.first(where: { $0.rangeClass == .ranged })?.id)
        let aggregation = try EquipmentAggregator(masterData: masterData).aggregate(
            equippedItemStacks: [
                CompositeItemStack(itemID: .baseItem(itemId: meleeItemID), count: 1),
                CompositeItemStack(itemID: .baseItem(itemId: rangedItemID), count: 1)
            ]
        )

        #expect(aggregation.hasMeleeWeapon)
        #expect(aggregation.hasRangedWeapon)
    }

    @Test
    func armorEquipmentFlatMultiplierScalesArmorBattleStats() throws {
        let armorSkill = MasterData.Skill(
            id: 1,
            name: "鎧固定値+50%",
            description: "鎧カテゴリ装備の固定値を強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .specialRule,
                    target: "armorEquipmentBattleStatFlatMultiplier",
                    operation: nil,
                    value: 1.5,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [armorSkill],
            enemyBaseStats: battleBaseStats()
        )
        let status = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(),
                jobId: 1,
                level: 1,
                skillIds: [armorSkill.id],
                masterData: masterData,
                equipmentBattleStats: CharacterBattleStats(
                    maxHP: 10,
                    physicalAttack: 0,
                    physicalDefense: 4,
                    magic: 0,
                    magicDefense: 6,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                ),
                armorEquipmentBattleStats: CharacterBattleStats(
                    maxHP: 10,
                    physicalAttack: 0,
                    physicalDefense: 4,
                    magic: 0,
                    magicDefense: 6,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        #expect(status.battleStats.maxHP == 15)
        #expect(status.battleStats.physicalDefense == 6)
        #expect(status.battleStats.magicDefense == 9)
    }

    @Test
    func swordEquipmentFlatMultiplierScalesOnlySwordBattleStats() throws {
        let swordSkill = MasterData.Skill(
            id: 1,
            name: "剣固定値+40%",
            description: "剣カテゴリ装備の固定値を強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .specialRule,
                    target: "swordEquipmentBattleStatFlatMultiplier",
                    operation: nil,
                    value: 1.4,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [swordSkill],
            enemyBaseStats: battleBaseStats()
        )
        let status = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(),
                jobId: 1,
                level: 1,
                skillIds: [swordSkill.id],
                masterData: masterData,
                equipmentBattleStats: CharacterBattleStats(
                    maxHP: 0,
                    physicalAttack: 15,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 4,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                ),
                equipmentBattleStatsByCategory: [
                    .sword: CharacterBattleStats(
                        maxHP: 0,
                        physicalAttack: 10,
                        physicalDefense: 0,
                        magic: 0,
                        magicDefense: 0,
                        healing: 0,
                        accuracy: 2,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    .bow: CharacterBattleStats(
                        maxHP: 0,
                        physicalAttack: 5,
                        physicalDefense: 0,
                        magic: 0,
                        magicDefense: 0,
                        healing: 0,
                        accuracy: 2,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    )
                ]
            )
        )

        #expect(status.battleStats.physicalAttack == 19)
        #expect(status.battleStats.accuracy == 5)
    }

    @Test
    func defenseEquipmentFlatMultiplierScalesDefenseCategories() throws {
        let defenseSkill = MasterData.Skill(
            id: 1,
            name: "防具固定値+35%",
            description: "防具カテゴリ装備の固定値を強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .specialRule,
                    target: "defenseEquipmentBattleStatFlatMultiplier",
                    operation: nil,
                    value: 1.35,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [defenseSkill],
            enemyBaseStats: battleBaseStats()
        )
        let status = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(),
                jobId: 1,
                level: 1,
                skillIds: [defenseSkill.id],
                masterData: masterData,
                equipmentBattleStats: CharacterBattleStats(
                    maxHP: 15,
                    physicalAttack: 3,
                    physicalDefense: 10,
                    magic: 0,
                    magicDefense: 9,
                    healing: 2,
                    accuracy: 0,
                    evasion: 1,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                ),
                equipmentBattleStatsByCategory: [
                    .armor: CharacterBattleStats(
                        maxHP: 10,
                        physicalAttack: 0,
                        physicalDefense: 4,
                        magic: 0,
                        magicDefense: 3,
                        healing: 0,
                        accuracy: 0,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    .shield: CharacterBattleStats(
                        maxHP: 5,
                        physicalAttack: 0,
                        physicalDefense: 3,
                        magic: 0,
                        magicDefense: 2,
                        healing: 0,
                        accuracy: 0,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    .robe: CharacterBattleStats(
                        maxHP: 0,
                        physicalAttack: 0,
                        physicalDefense: 1,
                        magic: 0,
                        magicDefense: 4,
                        healing: 2,
                        accuracy: 0,
                        evasion: 1,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    .gauntlet: CharacterBattleStats(
                        maxHP: 0,
                        physicalAttack: 0,
                        physicalDefense: 2,
                        magic: 0,
                        magicDefense: 0,
                        healing: 0,
                        accuracy: 0,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    .sword: CharacterBattleStats(
                        maxHP: 0,
                        physicalAttack: 3,
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
                ]
            )
        )

        #expect(status.battleStats.maxHP == 20)
        #expect(status.battleStats.physicalAttack == 3)
        #expect(status.battleStats.physicalDefense == 14)
        #expect(status.battleStats.magicDefense == 12)
        #expect(status.battleStats.healing == 3)
        #expect(status.battleStats.evasion == 1)
    }

    @Test
    func magicDefenseEquipmentFlatMultiplierScalesAllEquipmentMagicDefense() throws {
        let magicDefenseSkill = MasterData.Skill(
            id: 1,
            name: "魔法防御固定値+50%",
            description: "装備由来の魔法防御固定値を強化する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .specialRule,
                    target: "magicDefenseEquipmentFlatMultiplier",
                    operation: nil,
                    value: 1.5,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [magicDefenseSkill],
            enemyBaseStats: battleBaseStats()
        )
        let status = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(),
                jobId: 1,
                level: 1,
                skillIds: [magicDefenseSkill.id],
                masterData: masterData,
                equipmentBattleStats: CharacterBattleStats(
                    maxHP: 0,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 10,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        #expect(status.battleStats.magicDefense == 15)
    }

    @Test
    func jewelEnhancementConsumesInputsAndAddsHalfJewelStats() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()
        let baseItem = try #require(masterData.items.first(where: { $0.category != .jewel }))
        let jewelItem = try #require(masterData.items.first(where: { $0.category == .jewel }))
        let baseItemID = CompositeItemID.baseItem(itemId: baseItem.id)
        let jewelItemID = CompositeItemID.baseItem(itemId: jewelItem.id)

        try guildService.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 1),
                CompositeItemStack(itemID: jewelItemID, count: 1)
            ],
            masterData: masterData
        )

        try await guildService.enhanceWithJewel(
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
        let aggregation = try EquipmentAggregator(masterData: masterData).aggregate(
            equippedItemStacks: [CompositeItemStack(itemID: resultItemID, count: 1)]
        )

        #expect(try guildCoreDataStore.loadInventoryStacks() == [
            CompositeItemStack(itemID: resultItemID, count: 1)
        ])
        #expect(aggregation.baseStats == CharacterBaseStats(
            vitality: baseItem.nativeBaseStats.vitality + (jewelItem.nativeBaseStats.vitality / 2),
            strength: baseItem.nativeBaseStats.strength + (jewelItem.nativeBaseStats.strength / 2),
            mind: baseItem.nativeBaseStats.mind + (jewelItem.nativeBaseStats.mind / 2),
            intelligence: baseItem.nativeBaseStats.intelligence + (jewelItem.nativeBaseStats.intelligence / 2),
            agility: baseItem.nativeBaseStats.agility + (jewelItem.nativeBaseStats.agility / 2),
            luck: baseItem.nativeBaseStats.luck + (jewelItem.nativeBaseStats.luck / 2)
        ))
        #expect(aggregation.battleStats == CharacterBattleStats(
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
    func jewelEnhancementDecrementsInventoryBaseAndJewelByOne() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()
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

        try guildService.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 3),
                CompositeItemStack(itemID: jewelItemID, count: 2)
            ],
            masterData: masterData
        )

        try await guildService.enhanceWithJewel(
            baseItemID: baseItemID,
            baseCharacterId: nil,
            jewelItemID: jewelItemID,
            jewelCharacterId: nil,
            masterData: masterData
        )

        let inventoryStacks = try guildCoreDataStore.loadInventoryStacks()
        #expect(inventoryStacks.first(where: { $0.itemID == baseItemID })?.count == 2)
        #expect(inventoryStacks.first(where: { $0.itemID == jewelItemID })?.count == 1)
        #expect(inventoryStacks.first(where: { $0.itemID == resultItemID })?.count == 1)
        #expect(inventoryStacks.reduce(into: 0) { $0 += $1.count } == 4)
    }

    @Test
    func jewelEnhancementKeepsEquippedTargetOnCharacterAndOnlyTransformsOneItem() async throws {
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

        try guildService.addInventoryStacks(
            [
                CompositeItemStack(itemID: baseItemID, count: 2),
                CompositeItemStack(itemID: jewelItemID, count: 2)
            ],
            masterData: masterData
        )
        _ = try await guildService.equip(
            itemID: baseItemID,
            toCharacter: character.characterId,
            masterData: masterData
        )
        _ = try await guildService.equip(
            itemID: baseItemID,
            toCharacter: character.characterId,
            masterData: masterData
        )

        try await guildService.enhanceWithJewel(
            baseItemID: baseItemID,
            baseCharacterId: character.characterId,
            jewelItemID: jewelItemID,
            jewelCharacterId: nil,
            masterData: masterData
        )

        let updatedCharacter = try #require(try guildCoreDataStore.loadCharacter(characterId: character.characterId))
        let inventoryStacks = try guildCoreDataStore.loadInventoryStacks()

        #expect(updatedCharacter.equippedItemCount == 2)
        #expect(updatedCharacter.equippedItemStacks.first(where: { $0.itemID == baseItemID })?.count == 1)
        #expect(updatedCharacter.equippedItemStacks.first(where: { $0.itemID == resultItemID })?.count == 1)
        #expect(updatedCharacter.equippedItemStacks.reduce(into: 0) { $0 += $1.count } == 2)
        #expect(inventoryStacks.first(where: { $0.itemID == jewelItemID })?.count == 1)
        #expect(inventoryStacks.contains(where: { $0.itemID == baseItemID }) == false)
        #expect(inventoryStacks.contains(where: { $0.itemID == resultItemID }) == false)
    }

    // MARK: - Guild and Party Mutations

    @Test
    func unlockPartyConsumesGoldAndCreatesSequentialParty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataStore.saveRosterSnapshot(snapshot)

        _ = try guildService.unlockParty()

        #expect(
            try guildCoreDataStore.loadRosterSnapshot().playerState.gold
                == 10_000_000 - PartyRecord.unlockCost(forExistingPartyCount: 1)!
        )
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
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataStore.saveRosterSnapshot(snapshot)

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
    func resumingBackgroundProgressChainsAutomaticRunsFromLatestCompletionTime() async throws {
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
            service: guildService,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataStore: guildCoreDataStore,
            service: guildService,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataStore: explorationCoreDataStore,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "自動周回迷宮",
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

        rosterStore.reload()
        partyStore.reload()

        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildService.setSelectedLabyrinth(
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

        try guildService.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 110))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 113),
            partyStore: partyStore,
            guildService: guildService,
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
        let persistedRoster = try guildCoreDataStore.loadRosterSnapshot()
        let persistedParty = try #require(guildCoreDataStore.loadParties().first)
        #expect(persistedRoster.playerState.lastBackgroundedAt == nil)
        #expect(persistedParty.pendingAutomaticRunCount == 0)
        #expect(persistedParty.pendingAutomaticRunStartedAt == nil)
    }

    @Test
    func queuingAutomaticRunsCapsPendingCountAtTwenty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "上限確認迷宮",
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

        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildService.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )
        try guildService.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 100))
        try guildService.queueAutomaticRunsForResume(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 140),
            partyStatusesById: [:],
            masterData: masterData
        )

        let persistedParty = try #require(guildCoreDataStore.loadParties().first)
        #expect(persistedParty.pendingAutomaticRunCount == PartyRecord.maxPendingAutomaticRunCount)
        #expect(persistedParty.pendingAutomaticRunStartedAt == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test
    func resumingBackgroundProgressQueuesOnlyCompletedAutomaticRunsAfterLatestCompletionTime() async throws {
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
            service: guildService,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataStore: guildCoreDataStore,
            service: guildService,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataStore: explorationCoreDataStore,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "経過時間迷宮",
                    enemyCountCap: 1,
                    progressIntervalSeconds: 10,
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

        rosterStore.reload()
        partyStore.reload()

        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildService.updateAutoBattleSettings(
            characterId: character.characterId,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .breath, .recoverySpell, .attackSpell]
            )
        )
        _ = try await guildService.setSelectedLabyrinth(
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

        try guildService.recordBackgroundedAt(firstStartedAt.addingTimeInterval(5))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: firstStartedAt.addingTimeInterval(29),
            partyStore: partyStore,
            guildService: guildService,
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
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "部分経過迷宮",
                    enemyCountCap: 1,
                    progressIntervalSeconds: 10,
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

        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildService.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        try guildService.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 100))
        try guildService.queueAutomaticRunsForResume(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 109),
            partyStatusesById: [:],
            masterData: masterData
        )

        let persistedParty = try #require(guildCoreDataStore.loadParties().first)
        #expect(persistedParty.pendingAutomaticRunCount == 0)
        #expect(persistedParty.pendingAutomaticRunStartedAt == nil)
    }

    @Test
    func resumingBackgroundProgressClearsInvalidPendingPartyAndContinuesOtherParties() async throws {
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
            service: guildService,
            phase: .loaded
        )
        let partyStore = PartyStore(
            coreDataStore: guildCoreDataStore,
            service: guildService,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataStore: explorationCoreDataStore,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 10),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "選別迷宮",
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
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataStore.saveRosterSnapshot(snapshot)

        _ = try guildService.unlockParty()
        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 2)
        _ = try await guildService.setSelectedLabyrinth(
            partyId: 1,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )
        _ = try await guildService.setSelectedLabyrinth(
            partyId: 2,
            selectedLabyrinthId: 1,
            selectedDifficultyTitleId: 1
        )

        rosterStore.reload()
        partyStore.reload()

        try guildService.recordBackgroundedAt(Date(timeIntervalSinceReferenceDate: 110))
        await explorationStore.resumeBackgroundProgress(
            reopenedAt: Date(timeIntervalSinceReferenceDate: 113),
            partyStore: partyStore,
            guildService: guildService,
            masterData: masterData
        )

        let firstPartyRuns = explorationStore.runs.filter { $0.partyId == 1 }
        let secondPartyRuns = explorationStore.runs
            .filter { $0.partyId == 2 }
            .sorted { $0.partyRunId < $1.partyRunId }
        let persistedParties = try guildCoreDataStore.loadParties()
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
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )

        _ = try await guildService.setAutomaticallyUsesCatTicket(
            partyId: 1,
            isEnabled: true
        )

        let persistedParty = try #require(guildCoreDataStore.loadParties().first)
        #expect(persistedParty.automaticallyUsesCatTicket)
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
                        MasterData.SkillEffect(
                            kind: .equipmentCapacityModifier,
                            target: nil,
                            operation: nil,
                            value: -1,
                            spellIds: [],
                            condition: nil,
                            interruptKind: nil
                        )
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

        let character = try guildService.hireCharacter(
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
            try guildCoreDataStore.loadCharacter(characterId: character.characterId)
        )
        persistedCharacter.equippedItemStacks = equippedStacks
        try guildCoreDataStore.saveCharacter(persistedCharacter)

        let updatedCharacter = try await guildService.changeJob(
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
        #expect(try guildCoreDataStore.loadInventoryStacks() == expectedRemovedStacks)
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
    func equipUsesSkillAdjustedEquipmentCapacity() async throws {
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
        let itemIDs = masterData.items.prefix(4).map { CompositeItemID.baseItem(itemId: $0.id) }
        #expect(itemIDs.count == 4)
        #expect(character.maximumEquippedItemCount(masterData: masterData) == 4)

        try guildService.addInventoryStacks(
            itemIDs.map { CompositeItemStack(itemID: $0, count: 1) },
            masterData: masterData
        )

        for itemID in itemIDs {
            _ = try await guildService.equip(
                itemID: itemID,
                toCharacter: character.characterId,
                masterData: masterData
            )
        }

        let updatedCharacter = try #require(
            try guildCoreDataStore.loadCharacter(characterId: character.characterId)
        )
        #expect(updatedCharacter.equippedItemCount == 4)
        #expect(updatedCharacter.maximumEquippedItemCount(masterData: masterData) == 4)
        #expect(try guildCoreDataStore.loadInventoryStacks().isEmpty)
    }

    @Test
    func autoSellSettingsPersistExactCompositeItemIDs() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()
        let compositeItemID = CompositeItemID(
            baseSuperRareId: try #require(masterData.superRares.first?.id),
            baseTitleId: try #require(masterData.titles.first?.id),
            baseItemId: try itemId(for: .sword, in: masterData),
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )

        let updatedPlayerState = try guildService.setAutoSellEnabled(
            itemID: compositeItemID,
            isEnabled: true,
            masterData: masterData
        )

        #expect(updatedPlayerState.autoSellItemIDs == Set([compositeItemID]))
        #expect(
            try guildCoreDataStore.loadFreshRosterSnapshot().playerState.autoSellItemIDs
                == Set([compositeItemID])
        )
    }

    @Test
    func configuringAutoSellSellsSelectedInventoryStacks() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()
        let itemID = CompositeItemID(
            baseSuperRareId: try #require(masterData.superRares.first?.id),
            baseTitleId: try #require(masterData.titles.first?.id),
            baseItemId: try itemId(for: .sword, in: masterData),
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.shopInventoryInitialized = true
        let sellCount = 3

        try guildCoreDataStore.saveTradeState(
            playerState: snapshot.playerState,
            inventoryStacks: [CompositeItemStack(itemID: itemID, count: sellCount)],
            shopInventoryStacks: []
        )

        let updatedPlayerState = try guildService.configureAutoSell(
            itemIDs: [itemID],
            masterData: masterData
        )

        #expect(updatedPlayerState.autoSellItemIDs == Set([itemID]))
        #expect(
            try guildCoreDataStore.loadFreshRosterSnapshot().playerState.gold
                == PlayerState.initial.gold + ShopCatalog.sellPrice(for: itemID, masterData: masterData) * sellCount
        )
        #expect(try guildCoreDataStore.loadInventoryStacks().isEmpty)
        #expect(
            try guildCoreDataStore.loadShopInventoryStacks()
                == [CompositeItemStack(itemID: itemID, count: sellCount)]
        )
    }

    @Test
    func stockOrganizationConsumesExactShopStackAndAddsCatTickets() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: ExplorationCoreDataStore(container: container)
        )
        let masterData = try loadGeneratedMasterData()
        let baseItem = try #require(masterData.items.first(where: { $0.rarity != .normal }))
        let itemID = CompositeItemID.baseItem(itemId: baseItem.id)
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.shopInventoryInitialized = true

        try guildCoreDataStore.saveTradeState(
            playerState: snapshot.playerState,
            inventoryStacks: [],
            shopInventoryStacks: [
                CompositeItemStack(
                    itemID: itemID,
                    count: ShopCatalog.stockOrganizationBundleSize
                )
            ]
        )

        try guildService.organizeShopInventoryItem(
            itemID: itemID,
            masterData: masterData
        )

        #expect(try guildCoreDataStore.loadShopInventoryStacks().isEmpty)
        #expect(
            try guildCoreDataStore.loadFreshRosterSnapshot().playerState.catTicketCount
                == PlayerState.initial.catTicketCount + ShopCatalog.stockOrganizationTicketCount(for: baseItem.basePrice)
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

        #expect(ShopCatalog.purchasePrice(for: itemID, masterData: masterData) == 4_200)
        #expect(ShopCatalog.sellPrice(for: itemID, masterData: masterData) == 210)
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

        #expect(ShopCatalog.purchasePrice(for: itemID, masterData: masterData) == 1_900)
        #expect(ShopCatalog.sellPrice(for: itemID, masterData: masterData) == 95)
    }

    @Test
    func shopCatalogCapsEconomicPriceBeforeSellbackCalculation() {
        let masterData = shopCatalogTestMasterData()
        let itemID = CompositeItemID.baseItem(itemId: 3)

        #expect(ShopCatalog.purchasePrice(for: itemID, masterData: masterData) == EconomyPricing.maximumEconomicPrice)
        #expect(ShopCatalog.sellPrice(for: itemID, masterData: masterData) == 5_000_000)
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

    // MARK: - Exploration Session Progression

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
        var snapshot = try guildCoreDataStore.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataStore.saveRosterSnapshot(snapshot)

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
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataStore,
            masterData: masterData
        )

        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
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
        #expect(completionGold > 0)
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
    func startingRunAppliesExplorationTimeSkillToProgressInterval() async throws {
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
            jobId: try jobId(named: "忍者", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)

        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 265_000),
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)

        #expect(startedRun.progressIntervalMultiplier == 0.8)
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
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataStore,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 280_000)
        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
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
        #expect(storedDetail.battleLogs.count > startedRun.battleLogs.count)
        #expect(storedDetail.goldBuffer > 0)
        #expect(!storedDetail.experienceRewards.isEmpty)

        let refreshedSnapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10_000),
            masterData: masterData
        )
        let completedRun = try #require(refreshedSnapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(storedDetail.battleLogs == completedRun.battleLogs)
        #expect(storedDetail.goldBuffer == completion.gold)
        #expect(storedDetail.experienceRewards == completion.experienceRewards)
    }

    @Test
    func startingRunAutomaticallyUsesCatTicketWhenConfiguredAndAvailable() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        let explorationService = ExplorationSessionService(coreDataStore: explorationCoreDataStore)
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 100),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "キャット・チケット迷宮",
                    enemyCountCap: 1,
                    progressIntervalSeconds: 10,
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

        let character = try guildService.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildService.addCharacter(characterId: character.characterId, toParty: 1)

        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            startedAt: startedAt,
            catTicketUsage: .automaticIfAvailable,
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let refreshedRoster = try guildCoreDataStore.loadFreshRosterSnapshot()

        #expect(refreshedRoster.playerState.catTicketCount == 9)
        #expect(startedRun.progressIntervalMultiplier == 0.5)
        #expect(startedRun.goldMultiplier == 2.0)
        #expect(startedRun.rareDropMultiplier == 2.0)
        #expect(startedRun.memberExperienceMultipliers == [2.0])

        let plannedDetail = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))
        #expect(plannedDetail.goldBuffer == 20)
        #expect(plannedDetail.experienceRewards == [
            ExplorationExperienceReward(characterId: character.characterId, experience: 20)
        ])

        let refreshedSnapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(5),
            masterData: masterData
        )
        let completedRun = try #require(refreshedSnapshot.runs.first)
        #expect(completedRun.completedBattleCount == 1)
        #expect(completedRun.completion?.completedAt == startedAt.addingTimeInterval(5))
    }

    @Test
    func startingRunRequiringCatTicketFailsWhenPlayerHasNone() async throws {
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

        var rosterSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        rosterSnapshot.playerState.catTicketCount = 0
        try guildCoreDataStore.saveRosterSnapshot(rosterSnapshot)

        do {
            _ = try await explorationService.startRun(
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                startedAt: Date(timeIntervalSinceReferenceDate: 305_000),
                catTicketUsage: .required,
                masterData: masterData
            )
            Issue.record("キャット・チケット必須出撃は所持0枚で失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("キャット・チケットが不足") == true)
        }
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
                progressIntervalMultiplier: 1,
                goldMultiplier: 1,
                rareDropMultiplier: 1,
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
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataStore,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        let startingGold = try guildCoreDataStore.loadRosterSnapshot().playerState.gold
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let plannedRun = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(snapshot.didApplyRewards)
        #expect(completion.gold == plannedRun.goldBuffer)
        #expect(completion.experienceRewards == plannedRun.experienceRewards)
        #expect(completedRun.battleLogs == plannedRun.battleLogs)

        let rosterSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        let updatedCharacter = try #require(
            rosterSnapshot.characters.first(where: { $0.characterId == character.characterId })
        )
        let awardedExperience = completion.experienceRewards
            .first(where: { $0.characterId == character.characterId })?
            .experience ?? 0
        let completedRunCurrentHP = try #require(completedRun.currentPartyHPs.first)
        let expectedCurrentHP: Int
        if rosterSnapshot.playerState.autoReviveDefeatedCharacters && completedRunCurrentHP == 0 {
            expectedCurrentHP = try #require(
                CharacterDerivedStatsCalculator.status(for: updatedCharacter, masterData: masterData)?.maxHP
            )
        } else {
            expectedCurrentHP = completedRunCurrentHP
        }
        #expect(rosterSnapshot.playerState.gold == startingGold + completion.gold)
        #expect(updatedCharacter.experience == awardedExperience)
        #expect(updatedCharacter.currentHP == expectedCurrentHP)
    }

    @Test
    func refreshingCompletedRunReportsInventoryAndShopRewardCountsSeparately() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataStore = GuildCoreDataStore(container: container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: container)
        let masterData = try loadGeneratedMasterData()
        let inventoryItemID = CompositeItemID.baseItem(itemId: try itemId(for: .sword, in: masterData))
        let autoSellItemID = CompositeItemID.baseItem(itemId: try itemId(for: .armor, in: masterData))
        var rosterSnapshot = try guildCoreDataStore.loadRosterSnapshot()
        rosterSnapshot.playerState.autoSellItemIDs = [autoSellItemID]
        try guildCoreDataStore.saveRosterSnapshot(rosterSnapshot)

        let completion = RunCompletionRecord(
            completedAt: Date(timeIntervalSinceReferenceDate: 305_010),
            reason: .cleared,
            gold: 0,
            experienceRewards: [],
            dropRewards: [
                ExplorationDropReward(itemID: inventoryItemID, sourceFloorNumber: 1, sourceBattleNumber: 1),
                ExplorationDropReward(itemID: inventoryItemID, sourceFloorNumber: 1, sourceBattleNumber: 1),
                ExplorationDropReward(itemID: autoSellItemID, sourceFloorNumber: 1, sourceBattleNumber: 1)
            ]
        )

        try await explorationCoreDataStore.insertRun(
            RunSessionRecord(
                partyRunId: 1,
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                targetFloorNumber: 1,
                startedAt: Date(timeIntervalSinceReferenceDate: 305_000),
                rootSeed: 1,
                memberSnapshots: [],
                memberCharacterIds: [],
                completedBattleCount: 1,
                currentPartyHPs: [],
                memberExperienceMultipliers: [],
                progressIntervalMultiplier: 1,
                goldMultiplier: 1,
                rareDropMultiplier: 1,
                partyAverageLuck: 0,
                latestBattleFloorNumber: 1,
                latestBattleNumber: 1,
                latestBattleOutcome: .victory,
                battleLogs: [],
                goldBuffer: 0,
                experienceRewards: [],
                dropRewards: completion.dropRewards,
                completion: completion
            )
        )
        let completedRun = try #require(
            await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1)
        )

        let rewardApplication = try await explorationCoreDataStore.commitProgressUpdates(
            [(currentSession: completedRun, resolvedSession: completedRun)],
            masterData: masterData
        )

        #expect(rewardApplication.didApplyRewards)
        #expect(rewardApplication.appliedInventoryCounts == [inventoryItemID: 2])
        #expect(rewardApplication.appliedShopInventoryCounts == [autoSellItemID: 1])
        #expect(
            try guildCoreDataStore.loadInventoryStacks()
                == [CompositeItemStack(itemID: inventoryItemID, count: 2)]
        )
        #expect(
            try guildCoreDataStore.loadShopInventoryStacks()
                == [CompositeItemStack(itemID: autoSellItemID, count: 1)]
        )
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
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 20, strength: 20, agility: 20),
            enemyBaseStats: battleBaseStats(vitality: 1),
            titles: [
                MasterData.Title(
                    id: 1,
                    key: "default",
                    name: "通常",
                    positiveMultiplier: 1.0,
                    negativeMultiplier: 1.0,
                    dropWeight: 1
                ),
                MasterData.Title(
                    id: 2,
                    key: "next",
                    name: "次段階",
                    positiveMultiplier: 1.2,
                    negativeMultiplier: 1.2,
                    dropWeight: 1
                )
            ],
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "解放確認迷宮",
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
        let labyrinthId = 1
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
        _ = try await guildService.updateAutoBattleSettings(
            characterId: character.characterId,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .breath, .recoverySpell, .attackSpell]
            )
        )

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
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataStore,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 320_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let plannedRun = try #require(await explorationCoreDataStore.loadRunDetail(partyId: 1, partyRunId: 1))

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

        #expect(completion.gold == plannedRun.goldBuffer)
        #expect(completion.experienceRewards == plannedRun.experienceRewards)
        #expect(completedRun.battleLogs == plannedRun.battleLogs)
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
        try unlockLabyrinth(
            named: "洞窟",
            in: guildCoreDataStore,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "洞窟" })?.id),
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

    // MARK: - Battle Resolution: Damage, Ailments, and Targeting

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
            hasMeleeWeapon: false,
            hasRangedWeapon: true,
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
    func mixedWeaponsApplyBothFormationMultipliers() throws {
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
            isUnarmed: false,
            hasMeleeWeapon: true,
            hasRangedWeapon: true,
            weaponRangeClass: .ranged
        )
        let defendingStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 1,
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
        let defendOnly = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .breath, .recoverySpell, .attackSpell]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "前衛1", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 2, name: "前衛2", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 3, name: "中衛1", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 4, name: "中衛2", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 5, name: "後衛", status: allyStatus)
                ],
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
            weaponMultiplier: 1.0
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
        let damageMultiplier = allyStatus.battleDerivedStats.attackMagicMultiplier
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
    func sleepCanWearOffAtEndOfTurnAndAllowActionOnNextTurn() throws {
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
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 100, agility: 1_000),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<16_384,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "剣士",
                        status: allyStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 100,
                            recoverySpell: 0,
                            attackSpell: 0,
                            priority: [.attack, .breath, .recoverySpell, .attackSpell]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                guard result.battleRecord.turns.count >= 2,
                      let firstTurn = result.battleRecord.turns.first,
                      let firstAction = firstTurn.actions.first else {
                    return false
                }

                let laterActions = result.battleRecord.turns.dropFirst().flatMap(\.actions)
                return firstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1")
                    && firstAction.actionKind == .attackSpell
                    && firstAction.targetIds == [BattleCombatantID(rawValue: "character:1")]
                    && firstAction.results.contains(where: {
                        $0.targetId == BattleCombatantID(rawValue: "character:1")
                            && $0.resultKind == .modifierApplied
                            && $0.statusId == BattleAilment.sleep.rawValue
                    })
                    && firstTurn.actions.count == 1
                    && laterActions.contains(where: {
                        $0.actorId == BattleCombatantID(rawValue: "character:1")
                            && $0.actionKind == .attack
                    })
            }
        )

        let laterActions = result.battleRecord.turns.dropFirst().flatMap(\.actions)
        #expect(laterActions.contains(where: {
            $0.actorId == BattleCombatantID(rawValue: "character:1")
                && $0.actionKind == .attack
        }))
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
            progressIntervalMultiplier: 1,
            goldMultiplier: 1,
            rareDropMultiplier: 1,
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
    func recoverySpellUsesHealingMultiplierAndPartyHealingModifier() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healingSupportSkill = MasterData.Skill(
            id: 2,
            name: "魔力支配",
            description: "味方全体の回復威力を30%上げる。",
            effects: [
                MasterData.SkillEffect(
                    kind: .partyModifier,
                    target: "allyHealingMultiplier",
                    operation: "pctAdd",
                    value: 0.3,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healingSupportSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 20,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(healingMultiplier: 1.5),
            skillIds: [healingSupportSkill.id],
            spellIds: [healSpell.id]
        )
        let targetStatus = makeBattleTestStatus(
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<512,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "結界師",
                        status: healerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: targetStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .recoverySpell
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:2")])
        #expect(firstAction.results.first?.value == 39)
    }

    @Test
    func recoverySpellAmountIgnoresSpellMultiplierPerSpec() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "強化ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 2.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
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
        let injuredStatus = makeBattleTestStatus(
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
                    name: "僧侶",
                    status: healerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛", status: injuredStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.results.first?.value == 30)
        #expect(result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: "character:2") })?.remainingHP == 31)
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
            progressIntervalMultiplier: 1,
            goldMultiplier: 1,
            rareDropMultiplier: 1,
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
        #expect(enemySnapshots.map(\.name) == ["テスト敵A", "テスト敵B", "テスト敵C"])
        #expect(enemySnapshots.allSatisfy { $0.level == 5 })
    }

    @Test
    func superRareRateMultiplierRewardsRemainingHPAndFasterBattles() {
        let runID = RunSessionID(partyId: 1, partyRunId: 1)
        let result = SingleBattleResult(
            context: BattleContext(
                runId: runID,
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            battleRecord: BattleRecord(
                runId: runID,
                floorNumber: 1,
                battleNumber: 1,
                result: .victory,
                turns: [
                    BattleTurnRecord(turnNumber: 1, actions: []),
                    BattleTurnRecord(turnNumber: 2, actions: []),
                    BattleTurnRecord(turnNumber: 3, actions: []),
                    BattleTurnRecord(turnNumber: 4, actions: []),
                    BattleTurnRecord(turnNumber: 5, actions: [])
                ]
            ),
            combatants: [
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: "character:1"),
                    name: "前衛",
                    side: .ally,
                    imageAssetID: nil,
                    level: 1,
                    initialHP: 100,
                    maxHP: 100,
                    remainingHP: 50,
                    formationIndex: 0
                ),
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: "character:2"),
                    name: "後衛",
                    side: .ally,
                    imageAssetID: nil,
                    level: 1,
                    initialHP: 100,
                    maxHP: 100,
                    remainingHP: 25,
                    formationIndex: 1
                )
            ]
        )

        #expect(ExplorationResolver.superRareRateMultiplier(for: result) == 1.75)
    }

    @Test
    func titleRollCountAddsPartyLuckWithoutUsingEnemyLevel() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 25,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 2,
                key: "eerie",
                name: "妖しい",
                positiveMultiplier: 1.5874,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )

        #expect(ExplorationResolver.titleRollCount(rewardContext: rewardContext) == 5)
    }

    @Test
    func resolveRewardsGuaranteesMinimumExperienceOfOnePerSurvivor() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [1, 2, 3],
            memberExperienceMultipliers: [1, 1, 1],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )
        let masterData = MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [],
            jobs: [],
            aptitudes: [],
            items: [],
            titles: [rewardContext.defaultTitle],
            superRares: [],
            skills: [],
            spells: [],
            recruitNames: MasterData.RecruitNames(
                male: [],
                female: [],
                unisex: []
            ),
            enemies: [
                MasterData.Enemy(
                    id: 1,
                    name: "微経験値敵",
                    enemyRace: .monster,
                    jobId: 1,
                    baseStats: battleBaseStats(),
                    goldBaseValue: 0,
                    experienceBaseValue: 1,
                    skillIds: [],
                    rareDropItemIds: [],
                    actionRates: MasterData.ActionRates(
                        breath: 0,
                        attack: 1,
                        recoverySpell: 0,
                        attackSpell: 0
                    ),
                    actionPriority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            ],
            labyrinths: []
        )
        let result = SingleBattleResult(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            battleRecord: BattleRecord(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                floorNumber: 1,
                battleNumber: 1,
                result: .victory,
                turns: [BattleTurnRecord(turnNumber: 1, actions: [])]
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
                    id: BattleCombatantID(rawValue: "character:2"),
                    name: "中衛",
                    side: .ally,
                    imageAssetID: nil,
                    level: 1,
                    initialHP: 10,
                    maxHP: 10,
                    remainingHP: 10,
                    formationIndex: 1
                ),
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: "character:3"),
                    name: "後衛",
                    side: .ally,
                    imageAssetID: nil,
                    level: 1,
                    initialHP: 10,
                    maxHP: 10,
                    remainingHP: 10,
                    formationIndex: 2
                )
            ]
        )

        let rewards = ExplorationResolver.resolveRewards(
            rewardContext: rewardContext,
            enemySeeds: [BattleEnemySeed(enemyId: 1, level: 1)],
            result: result,
            floorNumber: 1,
            battleNumber: 1,
            rootSeed: 0,
            masterData: masterData
        )

        #expect(rewards.experienceRewards == [
            ExplorationExperienceReward(characterId: 1, experience: 1),
            ExplorationExperienceReward(characterId: 2, experience: 1),
            ExplorationExperienceReward(characterId: 3, experience: 1)
        ])
    }

    @Test
    func resolveTitleCanReturnTitleLowerThanUntitled() {
        let untitledTitle = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let roughTitle = MasterData.Title(
            id: 2,
            key: "rough",
            name: "粗末な",
            positiveMultiplier: 0.5,
            negativeMultiplier: 2.0,
            dropWeight: 1
        )
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: untitledTitle,
            enemyTitle: untitledTitle
        )

        let title = ExplorationResolver.resolveTitle(
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rewardContext: rewardContext,
            titles: [roughTitle],
            rootSeed: 0
        )

        #expect(title.id == roughTitle.id)
    }

    @Test
    func normalDropTierRollCountUsesExponentialThresholds() {
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1) == 1)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 10) == 1)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 11) == 2)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 20) == 2)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 21) == 3)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 40) == 3)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 41) == 4)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 80) == 4)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 81) == 5)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 160) == 5)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 161) == 6)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 320) == 6)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 321) == 7)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 640) == 7)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 641) == 8)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1_280) == 8)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1_281) == 9)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 2_560) == 9)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 2_561) == 10)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 99_999) == 10)
    }

    @Test
    func normalDropTierKeepsBestResultWhenEnemyLevelAddsRolls() {
        for seed in 0..<128 {
            let singleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 10,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )
            let doubleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 11,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )
            let tripleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 21,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )

            #expect((singleRollTier ?? 0) <= (doubleRollTier ?? 0))
            #expect((doubleRollTier ?? 0) <= (tripleRollTier ?? 0))
        }
    }

    @Test
    func normalDropJewelizeCanSelectNonNormalJewelRarity() {
        let defaultItem = MasterData.Item(
            id: 1,
            name: "テストソード",
            category: .sword,
            rarity: .normal,
            basePrice: 100,
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
        let rareJewel = MasterData.Item(
            id: 2,
            name: "テストレア宝石",
            category: .jewel,
            rarity: .rare,
            basePrice: 100,
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
            rangeClass: .none,
            normalDropTier: 0
        )
        let title = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 1,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: title,
            enemyTitle: title
        )

        let item = ExplorationResolver.normalDropBaseItem(
            from: defaultItem,
            tier: 1,
            rewardContext: rewardContext,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            rootSeed: 0,
            itemTable: [
                defaultItem.id: defaultItem,
                rareJewel.id: rareJewel
            ]
        )

        #expect(item.id == rareJewel.id)
        #expect(item.rarity == .rare)
    }

    @Test
    func rareDropRateIncludesPartyLuckBaseRate() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 10,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 25,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 2,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )

        let expectedRate = (0.001 + cbrt(25.0) / 1_000) * 10 * 1.2
        let actualRate = ExplorationResolver.rareDropRate(enemyLevel: 27, rewardContext: rewardContext)

        #expect(abs(actualRate - expectedRate) < 0.000_000_001)
    }

    @Test
    func superRareResolutionUsesBattlePerformanceMultiplier() {
        let masterData = debugItemGenerationMasterData()
        let title = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )

        let withoutBonus = ExplorationResolver.resolveSuperRareId(
            title: title,
            superRareRateMultiplier: 0,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rootSeed: 0,
            masterData: masterData
        )
        let guaranteed = ExplorationResolver.resolveSuperRareId(
            title: title,
            superRareRateMultiplier: 1_000_000,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rootSeed: 0,
            masterData: masterData
        )

        #expect(withoutBonus == 0)
        #expect(guaranteed == 1)
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
    func criticalAttackSpellCanRepeatWithoutConsumingSecondCharge() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "未来火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
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
        let casterStatus = makeBattleTestStatus(
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
                criticalRate: 100,
                breathPower: 0
            ),
            spellIds: [attackSpell.id],
            actionRuleValuesByTarget: [
                "attackSpellCanCritical": [1],
                "repeatAttackSpellOnCritical": [1]
            ]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "予見者",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                let attackSpells = result.battleRecord.turns.flatMap(\.actions).filter {
                    $0.actorId == BattleCombatantID(rawValue: "character:1") && $0.actionKind == .attackSpell
                }
                return attackSpells.count >= 2
            }
        )

        let attackSpells = result.battleRecord.turns.flatMap(\.actions).filter {
            $0.actorId == BattleCombatantID(rawValue: "character:1") && $0.actionKind == .attackSpell
        }
        #expect(attackSpells.count >= 2)
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
    func battleResolutionIsDeterministicForSameInput() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 20)
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
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let context = BattleContext(
            runId: RunSessionID(partyId: 1, partyRunId: 1),
            rootSeed: 42,
            floorNumber: 1,
            battleNumber: 1
        )
        let partyMembers = [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)]
        let enemies = [BattleEnemySeed(enemyId: 1, level: 1)]

        let first = try SingleBattleResolver.resolve(
            context: context,
            partyMembers: partyMembers,
            enemies: enemies,
            masterData: masterData
        )
        let second = try SingleBattleResolver.resolve(
            context: context,
            partyMembers: partyMembers,
            enemies: enemies,
            masterData: masterData
        )

        #expect(first == second)
    }

    @Test
    func duplicateEnemyNamesReceiveAlphabeticSuffixes() throws {
        let baseMasterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 20)
        )
        let templateEnemy = try #require(baseMasterData.enemies.first)
        let masterData = MasterData(
            metadata: baseMasterData.metadata,
            races: baseMasterData.races,
            jobs: baseMasterData.jobs,
            aptitudes: baseMasterData.aptitudes,
            items: baseMasterData.items,
            titles: baseMasterData.titles,
            superRares: baseMasterData.superRares,
            skills: baseMasterData.skills,
            spells: baseMasterData.spells,
            recruitNames: baseMasterData.recruitNames,
            enemies: [
                MasterData.Enemy(
                    id: 1,
                    name: "ウルフ",
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                ),
                MasterData.Enemy(
                    id: 2,
                    name: "ウルフ",
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                ),
                MasterData.Enemy(
                    id: 3,
                    name: "スライム",
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                )
            ],
            labyrinths: baseMasterData.labyrinths
        )
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
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 2, level: 1),
                BattleEnemySeed(enemyId: 3, level: 1)
            ],
            masterData: masterData
        )

        #expect(result.combatants.filter { $0.side == .enemy }.map(\.name) == ["ウルフA", "ウルフB", "スライム"])
    }

    @Test
    func skippedQueuedActionStillAdvancesActionNumberForLaterRandoms() throws {
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
        let sleepSkill = MasterData.Skill(
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
            skills: [sleepSkill],
            spells: [sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 1, agility: 100),
            enemySkillIds: [sleepSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let queuedAllyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 98),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 1,
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
        let slowerAllyStatus = makeBattleTestStatus(
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
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 43),
                rootSeed: 43,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "前衛A",
                    status: queuedAllyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 100,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.attack, .breath, .recoverySpell, .attackSpell]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛B", status: slowerAllyStatus),
                makePartyBattleMember(id: 3, name: "前衛C", status: slowerAllyStatus)
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.dropFirst().first)
        let expectedTargetIndex = expectedAttackSpellTargetIndex(
            rootSeed: 43,
            actorID: "enemy:1:2",
            spellID: sleepSpell.id,
            candidateCount: 3,
            actionNumber: 3
        )
        let expectedTargetID = BattleCombatantID(rawValue: "character:\(expectedTargetIndex + 1)")

        #expect(firstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1"))
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:1")])
        #expect(firstTurn.actions.contains(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }) == false)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: "enemy:1:2"))
        #expect(secondAction.targetIds == [expectedTargetID])
    }

    @Test
    func higherSpellIDIsPreferredWhenMultipleAttackSpellsAreUsable() throws {
        let lowSpell = MasterData.Spell(
            id: 1,
            name: "小火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let highSpell = MasterData.Spell(
            id: 2,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [lowSpell, highSpell],
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let casterStatus = makeBattleTestStatus(
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
            spellIds: [lowSpell.id, highSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<2_048,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .attackSpell
                    && result.battleRecord.turns.first?.actions.first?.actionRef == highSpell.id
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.actionRef == highSpell.id)
    }

    @Test
    func lastAttackSpellIsUsedWhenHigherSpellIDsAreRejected() throws {
        let lowSpell = MasterData.Spell(
            id: 1,
            name: "小火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let highSpell = MasterData.Spell(
            id: 2,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [lowSpell, highSpell],
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let casterStatus = makeBattleTestStatus(
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
            spellIds: [lowSpell.id, highSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<2_048,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .attackSpell
                    && result.battleRecord.turns.first?.actions.first?.actionRef == lowSpell.id
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.actionRef == lowSpell.id)
    }

    @Test
    func fullHealSpellRestoresTargetToMaxHP() throws {
        let fullHealSpell = MasterData.Spell(
            id: 1,
            name: "フルヒール",
            category: .recovery,
            kind: .fullHeal,
            targetSide: .ally,
            targetCount: 1
        )
        let masterData = makeBattleTestMasterData(
            spells: [fullHealSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
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
                healing: 10,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [fullHealSpell.id]
        )
        let injuredStatus = makeBattleTestStatus(
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
                    name: "僧侶",
                    status: healerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛", status: injuredStatus, currentHP: 40)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.actionRef == fullHealSpell.id)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:2")])
        #expect(firstAction.results.first?.value == 60)
        #expect(result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: "character:2") })?.remainingHP == 100)
    }

    @Test
    func cleanseSpellRemovesSleepAndRecordsRemovedAilment() throws {
        let cleanseSpell = MasterData.Spell(
            id: 1,
            name: "キュア",
            category: .recovery,
            kind: .cleanse,
            targetSide: .ally,
            targetCount: 1
        )
        let sleepSpell = MasterData.Spell(
            id: 2,
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
            spells: [cleanseSpell, sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 20, intelligence: 20, agility: 1_000),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
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
            ),
            spellIds: [cleanseSpell.id]
        )
        let victimStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
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
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: healerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: victimStatus)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.count >= 2
                    && result.battleRecord.turns[0].actions.contains(where: { action in
                        action.actionKind == .attackSpell
                            && action.results.contains(where: {
                                $0.targetId == BattleCombatantID(rawValue: "character:2")
                                    && $0.resultKind == .modifierApplied
                                    && $0.statusId == BattleAilment.sleep.rawValue
                            })
                    })
                    && result.battleRecord.turns[1].actions.contains(where: { action in
                        action.actorId == BattleCombatantID(rawValue: "character:1")
                            && action.actionKind == .recoverySpell
                            && action.actionRef == cleanseSpell.id
                            && action.results.contains(where: {
                                $0.targetId == BattleCombatantID(rawValue: "character:2")
                                    && $0.resultKind == .ailmentRemoved
                                    && $0.statusId == BattleAilment.sleep.rawValue
                            })
                    })
            }
        )

        let secondTurn = try #require(result.battleRecord.turns.dropFirst().first)
        let cleanseAction = try #require(
            secondTurn.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") })
        )
        #expect(cleanseAction.actionKind == .recoverySpell)
        #expect(cleanseAction.actionRef == cleanseSpell.id)
        #expect(cleanseAction.results.contains(where: {
            $0.targetId == BattleCombatantID(rawValue: "character:2")
                && $0.resultKind == .ailmentRemoved
                && $0.statusId == BattleAilment.sleep.rawValue
        }))
    }

    // MARK: - Battle Resolution: Interrupts and Runtime State

    @Test
    func rescueWithSingleTargetRecoveryRevivesOnlyOneDefeatedAlly() throws {
        let singleHealSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let breathSkill = MasterData.Skill(
            id: 2,
            name: "ブレス",
            description: "ブレスを使う。",
            effects: [
                MasterData.SkillEffect(
                    kind: .breathAccess,
                    target: nil,
                    operation: nil,
                    value: nil,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [breathSkill],
            spells: [singleHealSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [breathSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 100,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            enemyActionPriority: [.breath, .attack, .recoverySpell, .attackSpell]
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 200,
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
            spellIds: [singleHealSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
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
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))
        #expect(rescue.actionRef == singleHealSpell.id)
        #expect(rescue.targetIds.count == 1)
        #expect(rescue.results.count == 1)
        #expect(rescue.results.first?.flags.contains(.revived) == true)
        #expect(rescue.results.first?.value == 30)
    }

    @Test
    func criticalAttackSetsActionFlag() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
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
                criticalRate: 100,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus)],
                masterData: masterData
            ) { result in
                result.battleRecord.turns
                    .flatMap(\.actions)
                    .contains(where: { $0.actionKind == .attack && $0.actionFlags.contains(.critical) })
            }
        )

        #expect(
            result.battleRecord.turns
                .flatMap(\.actions)
                .contains(where: { $0.actionKind == .attack && $0.actionFlags.contains(.critical) })
        )
    }

    @Test
    func actionSpeedMultiplierChangesTurnOrder() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let fastStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
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
            ),
            battleDerivedStats: makeBattleDerivedStats(actionSpeedMultiplier: 2.0)
        )
        let slowStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
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
            ),
            battleDerivedStats: makeBattleDerivedStats(actionSpeedMultiplier: 0.5)
        )
        let defendOnly = makeAutoBattleSettings(
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
                makePartyBattleMember(id: 1, name: "高速", status: fastStatus, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 2, name: "低速", status: slowStatus, autoBattleSettings: defendOnly)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let fastIndex = try #require(firstTurn.actions.firstIndex(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }))
        let slowIndex = try #require(firstTurn.actions.firstIndex(where: { $0.actorId == BattleCombatantID(rawValue: "character:2") }))
        #expect(fastIndex < slowIndex)
    }

    @Test
    func actionOrderTieBreakPrefersHigherLuckWhenScoresMatch() {
        let highLuck = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 20,
            agility: 10,
            formationIndex: 1
        )
        let lowLuck = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(highLuck, lowLuck))
        #expect(BattleActionOrderPriorityKey.ordersBefore(lowLuck, highLuck) == false)
    }

    @Test
    func actionOrderTieBreakPrefersHigherAgilityWhenLuckMatches() {
        let fast = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 20,
            formationIndex: 1
        )
        let slow = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(fast, slow))
        #expect(BattleActionOrderPriorityKey.ordersBefore(slow, fast) == false)
    }

    @Test
    func actionOrderTieBreakPrefersEarlierFormationWhenLuckAndAgilityMatch() {
        let earlier = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )
        let later = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 1
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(earlier, later))
        #expect(BattleActionOrderPriorityKey.ordersBefore(later, earlier) == false)
    }

    @Test
    func randomizeNormalActionOrderCanLetSlowActorMoveFirst() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let slowStatus = makeBattleTestStatus(
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
            ),
            actionRuleValuesByTarget: ["randomizeNormalActionOrder": [1]]
        )
        let fastStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "鈍足", status: slowStatus),
                    makePartyBattleMember(id: 2, name: "俊足", status: fastStatus)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actorId == BattleCombatantID(rawValue: "character:1")
            }
        )

        #expect(result.battleRecord.turns.first?.actions.first?.actorId == BattleCombatantID(rawValue: "character:1"))
    }

    @Test
    func physicalAttackTargetsMiddleRankWhenFrontRankIsDefeated() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 20, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
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
        let defendOnly = makeAutoBattleSettings(
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
                makePartyBattleMember(id: 1, name: "前衛A", status: allyStatus, currentHP: 0, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 2, name: "前衛B", status: allyStatus, currentHP: 0, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 3, name: "中衛", status: allyStatus, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 4, name: "後衛", status: allyStatus, autoBattleSettings: defendOnly)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1"))
        #expect(firstAction.actionKind == .attack)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: "character:3")])
    }

    @Test
    func normalAttackTargetingFrontRowAllHitsEntireFrontRank() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
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
            actionRuleValuesByTarget: ["normalAttackTargetingFrontRowAll": [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "暴君", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }))
        #expect(attack.actionKind == .attack)
        #expect(
            Set(attack.targetIds) == [
                BattleCombatantID(rawValue: "enemy:1:1"),
                BattleCombatantID(rawValue: "enemy:1:2")
            ]
        )
    }

    @Test
    func normalAttackHitsRandomAdditionalTarget() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
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
            actionRuleValuesByTarget: ["normalAttackHitsRandomAdditionalTarget": [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "豪腕", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }))
        #expect(attack.actionKind == .attack)
        #expect(attack.targetIds.count == 2)
        #expect(Set(attack.targetIds).count == 2)
        #expect(attack.targetIds.contains(BattleCombatantID(rawValue: "enemy:1:1")))
    }

    func normalAttackTargetingAllEnemiesChanceHitsAllLivingEnemiesOnSuccess() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
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
            actionRuleValuesByTarget: ["normalAttackTargetingAllEnemiesChance": [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "泰山", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }))
        #expect(attack.actionKind == .attack)
        #expect(
            Set(attack.targetIds) == [
                BattleCombatantID(rawValue: "enemy:1:1"),
                BattleCombatantID(rawValue: "enemy:1:2"),
                BattleCombatantID(rawValue: "enemy:1:3")
            ]
        )
    }

    @Test
    func carryOverRemainingHitsOnKillTransfersToNextEnemy() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
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
                physicalAttack: 10,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 3,
                criticalRate: 0,
                breathPower: 0
            ),
            actionRuleValuesByTarget: ["carryOverRemainingHitsOnKill": [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "連破役", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") }))
        let damageResults = attack.results.filter { $0.resultKind == .damage }
        #expect(attack.actionKind == .attack)
        #expect(Set(attack.targetIds) == [
            BattleCombatantID(rawValue: "enemy:1:1"),
            BattleCombatantID(rawValue: "enemy:1:2")
        ])
        #expect(damageResults.count == 2)
        #expect(damageResults.contains { $0.flags.contains(.defeated) })
    }

    @Test
    func breathCanQueueNormalAttackFollowUp() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
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
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 20
            ),
            canUseBreath: true,
            actionRuleValuesByTarget: ["normalAttackAfterBreath": [1]]
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
                    name: "竜息役",
                    status: attackerStatus,
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

        let firstTurnActions = try #require(result.battleRecord.turns.first?.actions)
        let actorActions = firstTurnActions.filter { $0.actorId == BattleCombatantID(rawValue: "character:1") }
        #expect(actorActions.map(\.actionKind) == [.breath, .attack])
    }

    @Test
    func multiHitAttackUsesDecayAcrossHits() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let singleHitStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
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
        let multiHitStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 3,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let singleHitResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "単発役", status: singleHitStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )
        let singleHitDamage = try #require(firstDamageValue(in: singleHitResult, actionKind: .attack))
        let expectedMultiHitDamage = Int((Double(singleHitDamage) * 1.75).rounded())
        let multiHitResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "連撃役", status: multiHitStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) == expectedMultiHitDamage
            }
        )

        #expect(firstDamageValue(in: multiHitResult, actionKind: .attack) == expectedMultiHitDamage)
    }

    @Test
    func startTurnSelfDamageAppliesBeforeActionResolution() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1),
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
                physicalAttack: 200,
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
            combatRuleValuesByTarget: ["startTurnSelfCurrentHPLossPct": [0.5]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(id: 1, name: "狂戦士", status: attackerStatus)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let attackerSnapshot = try #require(
            result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: "character:1") })
        )
        #expect(attackerSnapshot.remainingHP == 50)
    }

    @Test
    func damageVarianceWidthMultiplierCanChangeNormalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
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
            specialRuleValuesByTarget: ["damageVarianceWidthMultiplier": [2.0]]
        )
        let baselineStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
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
        let baselineResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "基準", status: baselineStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attack))

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "道化師", status: attackerStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack).map { $0 != baselineDamage } ?? false
            }
        )

        #expect(firstDamageValue(in: result, actionKind: .attack) != baselineDamage)
    }

    @Test
    func luckyHitCanDoubleNormalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
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
            specialRuleValuesByTarget: [
                "hitDamageLuckyChance": [1.0],
                "hitDamageLuckyMultiplier": [2.0]
            ]
        )
        let baselineStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
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
        let baselineResult = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "基準", status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attack))

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "道化師", status: attackerStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(firstDamageValue(in: result, actionKind: .attack) == baselineDamage * 2)
    }

    @Test
    func unluckyHitCanHalveAttackSpellDamage() throws {
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
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
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
            spellIds: [attackSpell.id],
            specialRuleValuesByTarget: [
                "hitDamageUnluckyChance": [1.0],
                "hitDamageUnluckyMultiplier": [0.5]
            ]
        )
        let baselineStatus = makeBattleTestStatus(
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
        let baselineResult = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "基準",
                    status: baselineStatus,
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
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attackSpell))

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
                    name: "道化師",
                    status: casterStatus,
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

        #expect(firstDamageValue(in: result, actionKind: .attackSpell) == Int((Double(baselineDamage) * 0.5).rounded()))
    }

    @Test
    func unarmedRepeatAttackDoesNotChain() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
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
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "格闘家", status: attackerStatus)],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                let firstTurnAttacks = firstTurn.actions.filter {
                    $0.actorId == BattleCombatantID(rawValue: "character:1")
                        && ($0.actionKind == .attack || $0.actionKind == .unarmedRepeat)
                }
                return firstTurnAttacks.count == 2
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstTurnAttacks = firstTurn.actions.filter {
            $0.actorId == BattleCombatantID(rawValue: "character:1")
                && ($0.actionKind == .attack || $0.actionKind == .unarmedRepeat)
        }
        #expect(firstTurnAttacks.count == 2)
        #expect(firstTurnAttacks.map(\.actionKind) == [.attack, .unarmedRepeat])
    }

    @Test
    func spellChargesResetBetweenBattles() throws {
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
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
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
        let partyMembers = [
            makePartyBattleMember(
                id: 1,
                name: "魔導士",
                status: casterStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 100,
                    priority: [.attackSpell, .attack, .recoverySpell, .breath]
                )
            )
        ]

        var resolvedPair: (SingleBattleResult, SingleBattleResult)?
        for seed in 0..<256 {
            let firstBattle = try SingleBattleResolver.resolve(
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
            let secondBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 2
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            let firstSpellCount = firstBattle.battleRecord.turns
                .flatMap(\.actions)
                .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") && $0.actionKind == .attackSpell }
                .count
            let secondSpellCount = secondBattle.battleRecord.turns
                .flatMap(\.actions)
                .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") && $0.actionKind == .attackSpell }
                .count
            if firstSpellCount == 1 && secondSpellCount == 1 {
                resolvedPair = (firstBattle, secondBattle)
                break
            }
        }

        let (firstBattle, secondBattle) = try #require(resolvedPair)
        #expect(firstBattle.battleRecord.turns.flatMap(\.actions).contains {
            $0.actorId == BattleCombatantID(rawValue: "character:1")
                && $0.actionKind == .attackSpell
                && $0.actionRef == attackSpell.id
        })
        #expect(secondBattle.battleRecord.turns.flatMap(\.actions).contains {
            $0.actorId == BattleCombatantID(rawValue: "character:1")
                && $0.actionKind == .attackSpell
                && $0.actionRef == attackSpell.id
        })
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
    func multiplePursuersCanTriggerFromSameAttack() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1),
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
            )
        )
        let firstPursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 600),
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
        let secondPursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 300),
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
                matchingSeeds: 0..<32_768,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus),
                    makePartyBattleMember(id: 2, name: "狩人A", status: firstPursuerStatus),
                    makePartyBattleMember(id: 3, name: "狩人B", status: secondPursuerStatus)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                return Array(firstTurn.actions.prefix(3).map(\.actionKind)) == [
                    .attack,
                    .pursuit,
                    .pursuit
                ]
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstThreeActions = Array(firstTurn.actions.prefix(3))
        #expect(firstThreeActions.map(\.actionKind) == [.attack, .pursuit, .pursuit])
        #expect(firstThreeActions[1].actorId == BattleCombatantID(rawValue: "character:2"))
        #expect(firstThreeActions[2].actorId == BattleCombatantID(rawValue: "character:3"))
    }

    @Test
    func rescueTriggersWhenEnemyAttackDefeatsAnAlly() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: victimStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      firstTurn.actions.count >= 2 else {
                    return false
                }
                let attack = firstTurn.actions[0]
                let rescue = firstTurn.actions[1]
                return attack.actionKind == .attack
                    && attack.targetIds == [BattleCombatantID(rawValue: "character:2")]
                    && rescue.actionKind == .rescue
                    && rescue.targetIds == [BattleCombatantID(rawValue: "character:2")]
                    && rescue.results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.attack, .rescue])
        #expect(firstTurn.actions[1].results.first?.value == 30)
    }

    @Test
    func rescueTriggersWhenEnemyCounterDefeatsAnAlly() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let counterSkill = MasterData.Skill(
            id: 2,
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
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1),
            enemySkillIds: [counterSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 1,
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "剣士", status: attackerStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      firstTurn.actions.count >= 3 else {
                    return false
                }
                let attack = firstTurn.actions[0]
                let counter = firstTurn.actions[1]
                let rescue = firstTurn.actions[2]
                return attack.actionKind == .attack
                    && counter.actionKind == .counter
                    && counter.targetIds == [BattleCombatantID(rawValue: "character:2")]
                    && counter.results.first?.flags.contains(.defeated) == true
                    && rescue.actionKind == .rescue
                    && rescue.targetIds == [BattleCombatantID(rawValue: "character:2")]
                    && rescue.results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(3).map(\.actionKind)) == [.attack, .counter, .rescue])
    }

    @Test
    func rescueTriggersWhenEnemyBreathDefeatsMultipleAllies() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let breathSkill = MasterData.Skill(
            id: 2,
            name: "ブレス",
            description: "ブレスを使う。",
            effects: [
                MasterData.SkillEffect(
                    kind: .breathAccess,
                    target: nil,
                    operation: nil,
                    value: nil,
                    spellIds: [],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [breathSkill],
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [breathSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 100,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            enemyActionPriority: [.breath, .attack, .recoverySpell, .attackSpell]
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
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
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))

        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.breath, .rescue])
        #expect(Set(rescue.targetIds) == Set([
            BattleCombatantID(rawValue: "character:2"),
            BattleCombatantID(rawValue: "character:3")
        ]))
        #expect(rescue.results.allSatisfy { $0.flags.contains(.revived) && $0.value == 30 })
    }

    @Test
    func rescueTriggersWhenEnemyAttackSpellDefeatsMultipleAllies() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let attackSpell = MasterData.Spell(
            id: 2,
            name: "ファイアストーム",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 3,
            multiplier: 1.0
        )
        let attackSpellSkill = MasterData.Skill(
            id: 3,
            name: "ファイアストーム習得",
            description: "ファイアストームを習得する。",
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
            spells: [healAllSpell, attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 100, agility: 1_000),
            enemySkillIds: [attackSpellSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
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
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))

        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.attackSpell, .rescue])
        #expect(Set(rescue.targetIds) == Set([
            BattleCombatantID(rawValue: "character:2"),
            BattleCombatantID(rawValue: "character:3")
        ]))
        #expect(rescue.results.allSatisfy { $0.flags.contains(.revived) && $0.value == 30 })
    }

    @Test
    func rescueDoesNotTriggerWhenNoAllyIsDefeated() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 1, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "僧侶", status: rescuerStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(result.battleRecord.turns.flatMap(\.actions).contains { $0.actionKind == .rescue } == false)
    }

    @Test
    func secondRescueInterruptIsDiscardedAfterFirstRevivesTarget() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
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
            spellIds: [healSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
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

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "前衛",
                        status: victimStatus,
                        currentHP: 1,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 100,
                            recoverySpell: 0,
                            attackSpell: 0,
                            priority: [.attack, .breath, .recoverySpell, .attackSpell]
                        )
                    ),
                    makePartyBattleMember(
                        id: 2,
                        name: "僧侶A",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(
                        id: 3,
                        name: "僧侶B",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      let attack = firstTurn.actions.first else {
                    return false
                }
                let rescues = firstTurn.actions.filter { $0.actionKind == .rescue }
                return attack.actorId == BattleCombatantID(rawValue: "enemy:1:1")
                    && attack.actionKind == .attack
                    && attack.targetIds == [BattleCombatantID(rawValue: "character:1")]
                    && rescues.count == 1
                    && rescues[0].targetIds == [BattleCombatantID(rawValue: "character:1")]
                    && rescues[0].results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescues = firstTurn.actions.filter { $0.actionKind == .rescue }
        #expect(rescues.count == 1)
        #expect(rescues.first?.results.first?.value == 30)
    }

    @Test
    func rescueValidationRejectsInactiveRescuer() {
        #expect(
            RescueResolutionValidation.survivingDefeatedTargetIndices(
                from: [1],
                aliveStates: [true, false],
                actorCanAct: false
            ) == nil
        )
    }

    @Test
    func sleepDoesNotCarryIntoNextBattle() throws {
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
            enemyBaseStats: battleBaseStats(vitality: 1, intelligence: 100, agility: 95),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let frontlinerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
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
        let finisherStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
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
        let partyMembers = [
            makePartyBattleMember(
                id: 1,
                name: "前衛A",
                status: frontlinerStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 100,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            ),
            makePartyBattleMember(
                id: 2,
                name: "前衛B",
                status: finisherStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 100,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            )
        ]

        var matchingPair: (SingleBattleResult, SingleBattleResult)?
        for seed in 0..<16_384 {
            let firstBattle = try SingleBattleResolver.resolve(
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
            let secondBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 2
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            guard let firstBattleFirstTurn = firstBattle.battleRecord.turns.first,
                  let firstBattleFirstAction = firstBattleFirstTurn.actions.first,
                  let secondBattleFirstTurn = secondBattle.battleRecord.turns.first else {
                continue
            }

            let sleepAppliedToFrontliner = firstBattleFirstAction.results.contains(where: {
                $0.targetId == BattleCombatantID(rawValue: "character:1")
                    && $0.resultKind == .modifierApplied
                    && $0.statusId == BattleAilment.sleep.rawValue
            })
            let frontlinerActsInSecondBattleOpeningTurn = secondBattleFirstTurn.actions.contains(where: {
                $0.actorId == BattleCombatantID(rawValue: "character:1")
                    && $0.actionKind == .attack
            })
            if firstBattleFirstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1")
                && firstBattleFirstAction.actionKind == .attackSpell
                && firstBattleFirstAction.targetIds == [BattleCombatantID(rawValue: "character:1")]
                && sleepAppliedToFrontliner
                && frontlinerActsInSecondBattleOpeningTurn {
                matchingPair = (firstBattle, secondBattle)
                break
            }
        }

        let (firstBattle, secondBattle) = try #require(matchingPair)
        let firstBattleFirstAction = try #require(firstBattle.battleRecord.turns.first?.actions.first)
        let secondBattleFirstTurn = try #require(secondBattle.battleRecord.turns.first)

        #expect(firstBattleFirstAction.actionKind == .attackSpell)
        #expect(firstBattleFirstAction.targetIds == [BattleCombatantID(rawValue: "character:1")])
        #expect(firstBattleFirstAction.results.contains(where: {
            $0.targetId == BattleCombatantID(rawValue: "character:1")
                && $0.resultKind == .modifierApplied
                && $0.statusId == BattleAilment.sleep.rawValue
        }))
        #expect(secondBattleFirstTurn.actions.contains(where: {
            $0.actorId == BattleCombatantID(rawValue: "character:1")
                && $0.actionKind == .attack
        }))
    }

    @Test
    func explorationRebuildsPartyStatusWithoutBattleBuffsOrBarriers() throws {
        let attackBuffSpell = MasterData.Spell(
            id: 1,
            name: "攻撃バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: "physicalDamage"
        )
        let physicalBarrierSpell = MasterData.Spell(
            id: 2,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: "physicalDamageTaken"
        )
        let attackBuffSkill = MasterData.Skill(
            id: 1,
            name: "攻撃バフ習得",
            description: "攻撃バフを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [attackBuffSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let barrierSkill = MasterData.Skill(
            id: 2,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [physicalBarrierSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [attackBuffSkill, barrierSkill],
            spells: [attackBuffSpell, physicalBarrierSpell],
            allyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 100),
            allyRaceSkillIds: [attackBuffSkill.id, barrierSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let baselineMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .attackSpell, .recoverySpell, .breath]
            )
        )
        let baselineStatus = try #require(CharacterDerivedStatsCalculator.status(for: baselineMember, masterData: masterData))

        let buffMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let buffBattle = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: buffMember, status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let barrierMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let barrierBattle = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 1,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: barrierMember, status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let buffAction = try #require(
            buffBattle.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") })
        )
        let barrierAction = try #require(
            barrierBattle.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: "character:1") })
        )
        var buffCache: [Int: ExplorationMemberStatusCacheEntry] = [:]
        var barrierCache: [Int: ExplorationMemberStatusCacheEntry] = [:]
        let resolvedAfterBuff = try ExplorationResolver.rebuildPartyMembersAfterBattle(
            from: [buffMember],
            currentPartyHPs: buffBattle.partyRemainingHPs,
            masterData: masterData,
            cachedStatuses: &buffCache
        )
        let resolvedAfterBarrier = try ExplorationResolver.rebuildPartyMembersAfterBattle(
            from: [barrierMember],
            currentPartyHPs: barrierBattle.partyRemainingHPs,
            masterData: masterData,
            cachedStatuses: &barrierCache
        )

        #expect(buffAction.actionKind == .attackSpell)
        #expect(buffAction.actionRef == attackBuffSpell.id)
        #expect(buffAction.results.allSatisfy { $0.resultKind == .modifierApplied })
        #expect(barrierAction.actionKind == .recoverySpell)
        #expect(barrierAction.actionRef == physicalBarrierSpell.id)
        #expect(barrierAction.results.allSatisfy { $0.resultKind == .modifierApplied })
        #expect(resolvedAfterBuff.first?.status == baselineStatus)
        #expect(resolvedAfterBarrier.first?.status == baselineStatus)
    }

    @Test
    func attackBuffIncreasesLaterPhysicalAttackDamage() throws {
        let attackBuffSpell = MasterData.Spell(
            id: 1,
            name: "攻撃バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: "physicalDamage"
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackBuffSpell],
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
            spellIds: [attackBuffSpell.id]
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
                    name: "剣士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 100,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") }
        let firstAttack = try #require(allyActions.first(where: { $0.actionKind == .attack }))

        #expect(allyActions.first?.actionKind == .attackSpell)
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 1.5
                ).rounded()
            ),
            1
        )

        #expect(firstAttack.results.first?.value == expectedDamage)
    }

    @Test
    func magicBuffIncreasesLaterAttackSpellDamage() throws {
        let damageSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let magicBuffSpell = MasterData.Spell(
            id: 2,
            name: "魔法バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: "magicDamage"
        )
        let masterData = makeBattleTestMasterData(
            spells: [damageSpell, magicBuffSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
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
            spellIds: [damageSpell.id, magicBuffSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                let allyActions = result.battleRecord.turns
                    .flatMap(\.actions)
                    .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") }
                return allyActions.first?.actionKind == .attackSpell
                    && allyActions.first?.actionRef == magicBuffSpell.id
                    && allyActions.contains(where: {
                        $0.actionKind == .attackSpell
                            && $0.actionRef == damageSpell.id
                            && $0.results.contains(where: { $0.resultKind == .damage })
                    })
            }
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: "character:1") }
        let damageAction = try #require(allyActions.first(where: { $0.actionRef == damageSpell.id }))
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let expectedDamage = max(
            Int(
                (
                    Double(max(casterStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 1.5
                    * (damageSpell.multiplier ?? 1.0)
                ).rounded()
            ),
            1
        )

        #expect(allyActions.first?.actionRef == magicBuffSpell.id)
        #expect(damageAction.results.first?.value == expectedDamage)
    }

    @Test
    func physicalBarrierReducesIncomingPhysicalDamage() throws {
        let physicalBarrierSpell = MasterData.Spell(
            id: 1,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: "physicalDamageTaken"
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [physicalBarrierSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [physicalBarrierSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
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

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )

        #expect(firstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1"))
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: "character:1"))
        #expect(secondAction.actionKind == .attack)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func normalAttackBreaksPhysicalBarrierOnHitAndIgnoresPhysicalDefense() throws {
        let physicalBarrierSpell = MasterData.Spell(
            id: 1,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: "physicalDamageTaken"
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [physicalBarrierSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [physicalBarrierSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
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
            ),
            actionRuleValuesByTarget: [
                "normalAttackBreakPhysicalBarrierOnHit": [1],
                "normalAttackIgnorePhysicalDefensePct": [0.3]
            ]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "暴君", status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let secondAction = try #require(result.battleRecord.turns.first?.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(allyStatus.battleStats.physicalAttack)
                    - (Double(enemyStatus.battleStats.physicalDefense) * 0.7)
                ).rounded()
            ),
            1
        )

        #expect(secondAction.actorId == BattleCombatantID(rawValue: "character:1"))
        #expect(secondAction.actionKind == .attack)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func magicBarrierReducesIncomingAttackSpellDamage() throws {
        let magicBarrierSpell = MasterData.Spell(
            id: 1,
            name: "魔法バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: "magicDamageTaken"
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "魔法バリア習得",
            description: "魔法バリアを習得する。",
            effects: [
                MasterData.SkillEffect(
                    kind: .magicAccess,
                    target: nil,
                    operation: "grant",
                    value: nil,
                    spellIds: [magicBarrierSpell.id],
                    condition: nil,
                    interruptKind: nil
                )
            ]
        )
        let attackSpell = MasterData.Spell(
            id: 2,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [magicBarrierSpell, attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
        )
        let casterStatus = makeBattleTestStatus(
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
                    status: casterStatus,
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

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(max(casterStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )

        #expect(firstAction.actorId == BattleCombatantID(rawValue: "enemy:1:1"))
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: "character:1"))
        #expect(secondAction.actionKind == .attackSpell)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func nuclearSpellTargetsAllLivingCombatants() throws {
        let nuclearSpell = MasterData.Spell(
            id: 1,
            name: "核攻撃",
            category: .attack,
            kind: .damage,
            targetSide: .both,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [nuclearSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
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
            spellIds: [nuclearSpell.id]
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
                    status: casterStatus,
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
        #expect(Set(firstAction.targetIds) == Set([
            BattleCombatantID(rawValue: "character:1"),
            BattleCombatantID(rawValue: "enemy:1:1"),
            BattleCombatantID(rawValue: "enemy:1:2")
        ]))
    }

    // MARK: - Retention and Item Drop Notifications

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

    @Test
    func equipmentStatusNotificationsPublishOnlyChangedStats() {
        let service = EquipmentStatusNotificationService()
        let beforeStatus = equipmentStatusNotificationTestStatus(
            baseStats: CharacterBaseStats(
                vitality: 10,
                strength: 12,
                mind: 8,
                intelligence: 7,
                agility: 9,
                luck: 6
            ),
            battleStats: CharacterBattleStats(
                maxHP: 25,
                physicalAttack: 14,
                physicalDefense: 11,
                magic: 10,
                magicDefense: 13,
                healing: 4,
                accuracy: 6,
                evasion: 5,
                attackCount: 2,
                criticalRate: 3,
                breathPower: 0
            ),
            battleDerivedStats: CharacterBattleDerivedStats(
                physicalDamageMultiplier: 1.0,
                attackMagicMultiplier: 1.0,
                healingMultiplier: 1.0,
                spellDamageMultiplier: 1.0,
                criticalDamageMultiplier: 1.0,
                meleeDamageMultiplier: 1.1,
                rangedDamageMultiplier: 1.0,
                actionSpeedMultiplier: 1.0,
                physicalResistanceMultiplier: 1.0,
                magicResistanceMultiplier: 1.0,
                breathResistanceMultiplier: 1.0
            )
        )
        let afterStatus = equipmentStatusNotificationTestStatus(
            baseStats: CharacterBaseStats(
                vitality: 10,
                strength: 14,
                mind: 8,
                intelligence: 7,
                agility: 9,
                luck: 6
            ),
            battleStats: CharacterBattleStats(
                maxHP: 29,
                physicalAttack: 14,
                physicalDefense: 11,
                magic: 10,
                magicDefense: 12,
                healing: 4,
                accuracy: 6,
                evasion: 5,
                attackCount: 2,
                criticalRate: 3,
                breathPower: 0
            ),
            battleDerivedStats: CharacterBattleDerivedStats(
                physicalDamageMultiplier: 1.0,
                attackMagicMultiplier: 1.0,
                healingMultiplier: 1.0,
                spellDamageMultiplier: 1.0,
                criticalDamageMultiplier: 1.0,
                meleeDamageMultiplier: 1.15,
                rangedDamageMultiplier: 1.0,
                actionSpeedMultiplier: 1.0,
                physicalResistanceMultiplier: 1.0,
                magicResistanceMultiplier: 1.0,
                breathResistanceMultiplier: 1.0
            )
        )

        service.publish(before: beforeStatus, after: afterStatus)

        #expect(service.notifications.map(\.displayText) == [
            "腕力 14（+2）",
            "最大HP 29（+4）",
            "魔法防御 12（-1）",
            "近接威力倍率 115%（+5%）"
        ])
    }

    @Test
    func clearRemovesPublishedEquipmentStatusNotifications() {
        let service = EquipmentStatusNotificationService()

        service.publish(
            before: equipmentStatusNotificationTestStatus(),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 12,
                    physicalAttack: 5,
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
            )
        )
        service.clear()

        #expect(service.notifications.isEmpty)
    }

    @Test
    func equipmentStatusNotificationsReplacePreviousOperation() {
        let service = EquipmentStatusNotificationService()

        service.publish(
            before: equipmentStatusNotificationTestStatus(),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 20,
                    physicalAttack: 3,
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
            )
        )
        service.publish(
            before: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 20,
                    physicalAttack: 3,
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
            ),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 8,
                    physicalAttack: 3,
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
            )
        )

        #expect(service.notifications.map(\.displayText) == [
            "最大HP 8（-12）"
        ])
    }

}

// MARK: - Test Fixtures and Helpers

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

private func equipmentStatusNotificationTestStatus(
    baseStats: CharacterBaseStats = CharacterBaseStats(
        vitality: 0,
        strength: 0,
        mind: 0,
        intelligence: 0,
        agility: 0,
        luck: 0
    ),
    battleStats: CharacterBattleStats = CharacterBattleStats(
        maxHP: 10,
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
    battleDerivedStats: CharacterBattleDerivedStats = .baseline
) -> CharacterStatus {
    CharacterStatus(
        baseStats: baseStats,
        battleStats: battleStats,
        battleDerivedStats: battleDerivedStats,
        skillIds: [],
        spellIds: [],
        interruptKinds: [],
        canUseBreath: false,
        isUnarmed: false,
        hasMeleeWeapon: false,
        hasRangedWeapon: false,
        weaponRangeClass: .none,
        spellDamageMultipliersBySpellID: [:],
        spellResistanceMultipliersBySpellID: [:],
        rewardMultipliersByTarget: [:],
        partyModifiersByTarget: [:],
        onHitAilmentChanceByStatusID: [:],
        contactAilmentChanceByStatusID: [:],
        titleRollCountModifier: 0,
        equipmentCapacityModifier: 0,
        normalDropJewelizeChance: 0,
        multiHitFalloffModifier: 1.0,
        hitRateFloor: 0,
        defenseRuleValuesByTarget: [:],
        recoveryRuleValuesByTarget: [:],
        actionRuleValuesByTarget: [:],
        reviveRuleValuesByTarget: [:],
        combatRuleValuesByTarget: [:],
        rewardRuleValuesByTarget: [:],
        specialRuleValuesByTarget: [:]
    )
}

private func generatedMasterDataURL() -> URL {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot = testsDirectory.deletingLastPathComponent()
    return repositoryRoot.appending(path: "Generator/Output/masterdata.json")
}

@MainActor
private func unlockLabyrinth(
    named labyrinthName: String,
    in coreDataStore: GuildCoreDataStore,
    masterData: MasterData
) throws {
    let labyrinthId = try #require(masterData.labyrinths.first(where: { $0.name == labyrinthName })?.id)
    let defaultDifficultyTitleId = try #require(masterData.defaultExplorationDifficultyTitle?.id)

    var snapshot = try coreDataStore.loadRosterSnapshot()
    snapshot.labyrinthProgressRecords.removeAll { $0.labyrinthId == labyrinthId }
    snapshot.labyrinthProgressRecords.append(
        LabyrinthProgressRecord(
            labyrinthId: labyrinthId,
            highestUnlockedDifficultyTitleId: defaultDifficultyTitleId
        )
    )
    try coreDataStore.saveRosterSnapshot(snapshot)
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
private func itemId(for category: ItemCategory, in masterData: MasterData) throws -> Int {
    try #require(masterData.items.first(where: { $0.category == category })?.id)
}

private func shopCatalogTestMasterData() -> MasterData {
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
                basePrice: 1_000,
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
                basePrice: 800,
                nativeBaseStats: baseStats,
                nativeBattleStats: battleStats,
                skillIds: [],
                rangeClass: .none,
                normalDropTier: 1
            ),
            MasterData.Item(
                id: 3,
                name: "高額テスト宝石",
                category: .jewel,
                rarity: .godfiend,
                basePrice: 100_000_000,
                nativeBaseStats: baseStats,
                nativeBattleStats: battleStats,
                skillIds: [],
                rangeClass: .none,
                normalDropTier: 0
            )
        ],
        titles: [
            MasterData.Title(
                id: 1,
                key: "test",
                name: "テスト",
                positiveMultiplier: 1.5,
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
    attackMagicMultiplier: Double = 1.0,
    healingMultiplier: Double = 1.0,
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
        attackMagicMultiplier: attackMagicMultiplier,
        healingMultiplier: healingMultiplier,
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
    hasMeleeWeapon: Bool? = nil,
    hasRangedWeapon: Bool? = nil,
    weaponRangeClass: ItemRangeClass = .melee,
    spellDamageMultipliersBySpellID: [Int: Double] = [:],
    spellResistanceMultipliersBySpellID: [Int: Double] = [:],
    recoveryRuleValuesByTarget: [String: [Double]] = [:],
    actionRuleValuesByTarget: [String: [Double]] = [:],
    reviveRuleValuesByTarget: [String: [Double]] = [:],
    combatRuleValuesByTarget: [String: [Double]] = [:],
    specialRuleValuesByTarget: [String: [Double]] = [:]
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
        hasMeleeWeapon: hasMeleeWeapon ?? (weaponRangeClass == .melee),
        hasRangedWeapon: hasRangedWeapon ?? (weaponRangeClass == .ranged),
        weaponRangeClass: weaponRangeClass,
        spellDamageMultipliersBySpellID: spellDamageMultipliersBySpellID,
        spellResistanceMultipliersBySpellID: spellResistanceMultipliersBySpellID,
        rewardMultipliersByTarget: [:],
        partyModifiersByTarget: [:],
        onHitAilmentChanceByStatusID: [:],
        contactAilmentChanceByStatusID: [:],
        titleRollCountModifier: 0,
        equipmentCapacityModifier: 0,
        normalDropJewelizeChance: 0,
        multiHitFalloffModifier: 0.5,
        hitRateFloor: 0.10,
        defenseRuleValuesByTarget: [:],
        recoveryRuleValuesByTarget: recoveryRuleValuesByTarget,
        actionRuleValuesByTarget: actionRuleValuesByTarget,
        reviveRuleValuesByTarget: reviveRuleValuesByTarget,
        combatRuleValuesByTarget: combatRuleValuesByTarget,
        rewardRuleValuesByTarget: [:],
        specialRuleValuesByTarget: specialRuleValuesByTarget
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
        portraitAssetID: "job_test-job_male",
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
    jobPassiveSkillIds: [Int] = [],
    jobLevelSkillIds: [Int] = [],
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
                key: "test-race",
                name: "テスト種族",
                levelCap: 99,
                baseHirePrice: 1,
                baseStats: allyBaseStats,
                passiveSkillIds: allyRaceSkillIds,
                levelSkillIds: []
            )
        ],
        jobs: [
            MasterData.Job(
                id: 1,
                key: "test-job",
                name: "テスト職",
                hirePriceMultiplier: 1.0,
                coefficients: coefficients,
                passiveSkillIds: jobPassiveSkillIds,
                levelSkillIds: jobLevelSkillIds,
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
    jobPassiveSkillIds: [Int] = [],
    jobLevelSkillIds: [Int] = [],
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
                key: "test-race",
                name: "テスト種族",
                levelCap: 99,
                baseHirePrice: 1,
                baseStats: allyBaseStats,
                passiveSkillIds: allyRaceSkillIds,
                levelSkillIds: []
            )
        ],
        jobs: [
            MasterData.Job(
                id: 1,
                key: "test-job",
                name: "テスト職",
                hirePriceMultiplier: 1.0,
                coefficients: coefficients,
                passiveSkillIds: jobPassiveSkillIds,
                levelSkillIds: jobLevelSkillIds,
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

private func expectedAttackSpellTargetIndex(
    rootSeed: UInt64,
    actorID: String,
    spellID: Int,
    candidateCount: Int,
    actionNumber: Int
) -> Int {
    let roll = deterministicBattleUniform(
        rootSeed: rootSeed,
        floorNumber: 1,
        battleNumber: 1,
        turnNumber: 1,
        actionNumber: actionNumber,
        subactionNumber: 1,
        rollNumber: 1,
        purpose: "attackSpellTargets.\(actorID).spell.\(spellID)"
    )
    return min(Int((roll * Double(candidateCount)).rounded(.down)), candidateCount - 1)
}

private func deterministicBattleUniform(
    rootSeed: UInt64,
    floorNumber: Int,
    battleNumber: Int,
    turnNumber: Int,
    actionNumber: Int,
    subactionNumber: Int,
    rollNumber: Int,
    purpose: String
) -> Double {
    var state = rootSeed
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(floorNumber)))
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(battleNumber)))
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(turnNumber)))
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(actionNumber)))
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(subactionNumber)))
    state = mixedBattleRandomState(state ^ UInt64(bitPattern: Int64(rollNumber)))
    state = mixedBattleRandomState(state ^ battlePurposeHash(purpose))
    return Double(state >> 11) / Double(1 << 53)
}

private func mixedBattleRandomState(_ value: UInt64) -> UInt64 {
    var z = value &+ 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

private func battlePurposeHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return hash
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
        progressIntervalMultiplier: 1,
        goldMultiplier: 1,
        rareDropMultiplier: 1,
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
