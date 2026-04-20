// Defines the shared builders, current-master-data accessors, and helper assertions used by the
// split Umbra test suites.
// Keeping these fixtures in one file lets behavior-focused suites stay short while still exercising
// the same canonical test data and service setup paths.

import CoreData
import Foundation
import Testing
@testable import Umbra

@MainActor
func matchesRecruitNamePool(character: CharacterRecord, masterData: MasterData) -> Bool {
    switch character.portraitGender {
    case .male:
        masterData.recruitNames.male.contains(character.name)
    case .female:
        masterData.recruitNames.female.contains(character.name)
    case .unisex:
        masterData.recruitNames.unisex.contains(character.name)
    }
}

@MainActor
func makeGuildServices(
    container: NSPersistentContainer,
    coreDataRepository: GuildCoreDataRepository? = nil,
    explorationCoreDataRepository: ExplorationCoreDataRepository? = nil
) -> GuildServices {
    GuildServices(
        coreDataRepository: coreDataRepository ?? GuildCoreDataRepository(container: container),
        explorationCoreDataRepository: explorationCoreDataRepository ?? ExplorationCoreDataRepository(container: container)
    )
}

@MainActor
func currentMasterData() -> MasterData {
    MasterData.current
}

func itemDropNotificationTestMasterData() -> MasterData {
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

func equipmentStatusNotificationTestStatus(
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
        equipmentRuleValuesByTarget: [:],
        explorationRuleValuesByTarget: [:],
        hitRuleValuesByTarget: [:]
    )
}

@MainActor
func unlockLabyrinth(
    named labyrinthName: String,
    in coreDataRepository: GuildCoreDataRepository,
    masterData: MasterData
) throws {
    let labyrinthId = try #require(masterData.labyrinths.first(where: { $0.name == labyrinthName })?.id)
    let defaultDifficultyTitleId = try #require(masterData.defaultExplorationDifficultyTitle?.id)

    var snapshot = try coreDataRepository.loadRosterSnapshot()
    snapshot.labyrinthProgressRecords.removeAll { $0.labyrinthId == labyrinthId }
    snapshot.labyrinthProgressRecords.append(
        LabyrinthProgressRecord(
            labyrinthId: labyrinthId,
            highestUnlockedDifficultyTitleId: defaultDifficultyTitleId
        )
    )
    try coreDataRepository.saveRosterSnapshot(snapshot)
}

@MainActor
func promoteCharacter(
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
func setCurrentHP(
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
func raceId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.races.first(where: { $0.name == name })?.id)
}

@MainActor
func jobId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.jobs.first(where: { $0.name == name })?.id)
}

@MainActor
func skillId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.skills.first(where: { $0.name == name })?.id)
}

@MainActor
func itemId(for category: ItemCategory, in masterData: MasterData) throws -> Int {
    try #require(masterData.items.first(where: { $0.category == category })?.id)
}

func shopCatalogTestMasterData() -> MasterData {
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
func spellIds(named names: [String], in masterData: MasterData) throws -> [Int] {
    try names.map { name in
        try #require(masterData.spells.first(where: { $0.name == name })?.id)
    }
}

func battleBaseStats(
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

func battleCharacterBaseStats(
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

func makeBattleDerivedStats(
    physicalDamageMultiplier: Double = 1.0,
    attackMagicMultiplier: Double = 1.0,
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

func makeBattleTestStatus(
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
    recoveryRuleValuesByTarget: [RecoveryRuleTarget: [Double]] = [:],
    actionRuleValuesByTarget: [ActionRuleTarget: [Double]] = [:],
    reviveRuleValuesByTarget: [ReviveRuleTarget: [Double]] = [:],
    combatRuleValuesByTarget: [CombatRuleTarget: [Double]] = [:],
    equipmentRuleValuesByTarget: [EquipmentRuleTarget: [Double]] = [:],
    explorationRuleValuesByTarget: [ExplorationRuleTarget: [Double]] = [:],
    hitRuleValuesByTarget: [HitRuleTarget: [Double]] = [:]
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
        equipmentRuleValuesByTarget: equipmentRuleValuesByTarget,
        explorationRuleValuesByTarget: explorationRuleValuesByTarget,
        hitRuleValuesByTarget: hitRuleValuesByTarget
    )
}

func makeAutoBattleSettings(
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

func makePartyBattleMember(
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

func makeBattleTestCharacter(
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

func makeBattleTestMasterData(
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
                imageAssetName: nil,
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

func makeExplorationBattleTestMasterData(
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
                imageAssetName: nil,
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

func firstResolvedBattle(
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

func firstDamageValue(
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

func expectedPhysicalDamage(
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

func expectedAttackSpellTargetIndex(
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

func deterministicBattleUniform(
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

func mixedBattleRandomState(_ value: UInt64) -> UInt64 {
    var z = value &+ 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

func battlePurposeHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return hash
}

func makeCompletedRunRecord(
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
        totalBattleCount: 0,
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

func debugItemGenerationMasterData() -> MasterData {
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
