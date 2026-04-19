// Verifies foundational data and calculation behavior shared across the app.
// This suite keeps master-data availability, item filtering, and derived-stat expectations
// together so core data-model regressions are caught before higher-level feature tests fail.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraCatalogAndStatsTests {
    @Test
    func generatedMasterDataIsAvailable() {
        let masterData = currentMasterData()

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "草原")
    }

    @Test
    func appUsesGeneratedMasterData() {
        let masterData = MasterData.current

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "草原")
    }

    @Test
    func recruitNamesAreGroupedByGender() {
        let masterData = currentMasterData()

        #expect(!masterData.recruitNames.male.isEmpty)
        #expect(!masterData.recruitNames.female.isEmpty)
        #expect(!masterData.recruitNames.unisex.isEmpty)
    }

    @Test
    func itemBrowserFilterCatalogCollectsVisibleCategoriesAndTitles() throws {
        let masterData = currentMasterData()
        let roughTitleID = try #require(masterData.titles.first(where: { $0.key == "rough" })?.id)
        let untitledTitle = try #require(masterData.titles.first(where: { $0.key == "untitled" }))
        let swordID = try itemId(for: .sword, in: masterData)
        let armorID = try itemId(for: .armor, in: masterData)
        let jewelID = try itemId(for: .jewel, in: masterData)
        let catalog = ItemBrowserFilterOptions(
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
        let masterData = currentMasterData()
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
    func guildCoreDataRepositoryCreatesInitialPlayerState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)

        let snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        let parties = try guildCoreDataRepository.loadParties()

        #expect(snapshot.playerState == .initial)
        #expect(snapshot.playerState.catTicketCount == 10)
        #expect(snapshot.characters.isEmpty)
        #expect(parties == [PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [])])
    }

    @Test
    func playerBackgroundTimestampAndPartyPendingRunsPersist() throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let backgroundedAt = Date(timeIntervalSinceReferenceDate: 12_345)
        let pendingStartedAt = Date(timeIntervalSinceReferenceDate: 12_346)

        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.lastBackgroundedAt = backgroundedAt
        try guildCoreDataRepository.saveRosterSnapshot(snapshot)

        var parties = try guildCoreDataRepository.loadParties()
        parties[0].pendingAutomaticRunCount = 2
        parties[0].pendingAutomaticRunStartedAt = pendingStartedAt
        try guildCoreDataRepository.saveParties(parties)

        let reloadedSnapshot = try guildCoreDataRepository.loadFreshRosterSnapshot()
        let reloadedParties = try guildCoreDataRepository.loadParties()

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
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()

        let result = try guildServices.roster.hireCharacter(
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

        let reloadedSnapshot = try guildCoreDataRepository.loadRosterSnapshot()
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
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
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
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.gold = 120_000_000
        let parties = (1...7).map { partyId in
            PartyRecord(
                partyId: partyId,
                name: PartyRecord.defaultName(for: partyId),
                memberCharacterIds: []
            )
        }
        let cappedJewel = CompositeItemID.baseItem(itemId: 1)

        try guildCoreDataRepository.saveRosterState(
            snapshot,
            parties: parties,
            inventoryStacks: [CompositeItemStack(itemID: cappedJewel, count: 1)]
        )

        let updatedParties = try guildServices.parties.unlockParty(
            consuming: EconomicCapJewelSelection(
                itemID: cappedJewel,
                characterId: nil
            ),
            masterData: masterData
        )
        let reloadedSnapshot = try guildCoreDataRepository.loadRosterSnapshot()
        let reloadedInventory = try guildCoreDataRepository.loadInventoryStacks()

        #expect(updatedParties.count == 8)
        #expect(reloadedSnapshot.playerState.gold == 20_000_001)
        #expect(reloadedInventory.isEmpty)
    }

    @Test
    func completeStatusCalculationBuildsBattleStatsAndCapabilities() throws {
        let masterData = currentMasterData()
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
            physicalAttack: 50,
            physicalDefense: 35,
            magic: 32,
            magicDefense: 29,
            healing: 26,
            accuracy: 9,
            evasion: 5,
            attackCount: 1,
            criticalRate: 1,
            breathPower: 42
        ))
        #expect(status.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            attackMagicMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.0,
            meleeDamageMultiplier: 1.0,
            rangedDamageMultiplier: 1.0,
            actionSpeedMultiplier: 1.0,
            physicalResistanceMultiplier: 0.8,
            magicResistanceMultiplier: 0.94,
            breathResistanceMultiplier: 1.0
        ))
        #expect(status.canUseBreath == false)
        #expect(status.spellIds.isEmpty)
        #expect(status.interruptKinds.isEmpty)
        #expect(status.skillIds.count == Set(status.skillIds).count)
    }

    @Test
    func completeStatusCalculationCollectsDerivedEffectsAndSpells() throws {
        let masterData = currentMasterData()
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
        #expect(spellcastingStatus.battleStats.magic == 149)
        #expect(spellcastingStatus.skillIds.count == Set(spellcastingStatus.skillIds).count)

        #expect(breathStatus.canUseBreath)
        #expect(breathStatus.interruptKinds == [.counter])
        #expect(breathStatus.battleStats.breathPower == 60)
        #expect(breathStatus.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            attackMagicMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.1,
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
        let masterData = currentMasterData()
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
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [attackSpell.id], condition: nil)
            ]
        )
        let revokeSkill = MasterData.Skill(
            id: 2,
            name: "火球忘却",
            description: "火球を忘却する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .revoke, spellIds: [attackSpell.id], condition: nil)
            ]
        )
        let allStatSkill = MasterData.Skill(
            id: 3,
            name: "全能力強化",
            description: "全戦闘能力値が上昇する。",
            effects: [
                MasterData.SkillEffect.allBattleStatMultiplier(value: 1.5)
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
                MasterData.SkillEffect.battleStatModifier(target: .physicalAttack, operation: .pctAdd, value: 1.0, condition: .unarmed)
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
                MasterData.SkillEffect.battleStatModifier(target: .physicalAttack, operation: .flatAdd, value: 5, condition: nil)
            ]
        )
        let levelSkill = MasterData.Skill(
            id: 2,
            name: "職レベル魔力補正",
            description: "魔力を固定値強化する。",
            effects: [
                MasterData.SkillEffect.battleStatModifier(target: .magic, operation: .flatAdd, value: 7, condition: nil)
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
    func equipmentResolutionKeepsBothWeaponRangesWhenMixed() throws {
        let masterData = currentMasterData()
        let meleeItemID = try #require(masterData.items.first(where: { $0.rangeClass == .melee })?.id)
        let rangedItemID = try #require(masterData.items.first(where: { $0.rangeClass == .ranged })?.id)
        let resolution = try EquipmentResolver(masterData: masterData).resolve(
            equippedItemStacks: [
                CompositeItemStack(itemID: .baseItem(itemId: meleeItemID), count: 1),
                CompositeItemStack(itemID: .baseItem(itemId: rangedItemID), count: 1)
            ]
        )

        #expect(resolution.hasMeleeWeapon)
        #expect(resolution.hasRangedWeapon)
    }

    @Test
    func equipmentResolutionRejectsUnknownItemReference() throws {
        let masterData = currentMasterData()

        #expect(throws: EquipmentResolverError.unknownItem(99_999)) {
            _ = try EquipmentResolver(masterData: masterData).resolve(
                equippedItemStacks: [CompositeItemStack(itemID: .baseItem(itemId: 99_999), count: 1)]
            )
        }
    }

    @Test
    func equipmentResolutionAppliesTitleMultiplierOnlyToBattleStats() throws {
        let masterData = MasterData(
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
                    nativeBaseStats: battleBaseStats(vitality: 10, strength: -4, agility: 3),
                    nativeBattleStats: MasterData.BattleStats(
                        maxHP: 12,
                        physicalAttack: -8,
                        physicalDefense: 0,
                        magic: 0,
                        magicDefense: 0,
                        healing: 0,
                        accuracy: 5,
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
                    key: "test",
                    name: "テスト",
                    positiveMultiplier: 1.5,
                    negativeMultiplier: 1.0,
                    dropWeight: 1
                )
            ],
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
        let titledItemID = CompositeItemID.baseItem(itemId: 1, titleId: 1)

        let resolution = try EquipmentResolver(masterData: masterData).resolve(
            equippedItemStacks: [CompositeItemStack(itemID: titledItemID, count: 1)]
        )

        #expect(resolution.baseStats == CharacterBaseStats(
            vitality: 10,
            strength: -4,
            mind: 0,
            intelligence: 0,
            agility: 3,
            luck: 0
        ))
        #expect(resolution.battleStats == CharacterBattleStats(
            maxHP: 18,
            physicalAttack: -8,
            physicalDefense: 0,
            magic: 0,
            magicDefense: 0,
            healing: 0,
            accuracy: 8,
            evasion: 0,
            attackCount: 0,
            criticalRate: 0,
            breathPower: 0
        ))
    }

    @Test
    func armorEquipmentFlatMultiplierScalesArmorBattleStats() throws {
        let armorSkill = MasterData.Skill(
            id: 1,
            name: "鎧固定値+50%",
            description: "鎧カテゴリ装備の固定値を強化する。",
            effects: [
                MasterData.SkillEffect.equipmentRule(target: .armorEquipmentBattleStatFlatMultiplier, value: 1.5, condition: nil)
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
                MasterData.SkillEffect.equipmentRule(target: .swordEquipmentBattleStatFlatMultiplier, value: 1.4, condition: nil)
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
                MasterData.SkillEffect.equipmentRule(target: .defenseEquipmentBattleStatFlatMultiplier, value: 1.35, condition: nil)
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
                MasterData.SkillEffect.equipmentRule(target: .magicDefenseEquipmentFlatMultiplier, value: 1.5, condition: nil)
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

}
