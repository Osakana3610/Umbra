// Represents a character's fully derived runtime status and combat capabilities.

nonisolated struct CharacterStatus: Equatable, Sendable {
    let baseStats: CharacterBaseStats
    let battleStats: CharacterBattleStats
    let battleDerivedStats: CharacterBattleDerivedStats
    let skillIds: [Int]
    let spellIds: [Int]
    let interruptKinds: [InterruptKind]
    let canUseBreath: Bool
    let isUnarmed: Bool
    let hasMeleeWeapon: Bool
    let hasRangedWeapon: Bool
    let weaponRangeClass: ItemRangeClass
    let spellDamageMultipliersBySpellID: [Int: Double]
    let spellResistanceMultipliersBySpellID: [Int: Double]
    let rewardMultipliersByTarget: [String: Double]
    let partyModifiersByTarget: [String: Double]
    let onHitAilmentChanceByStatusID: [Int: Double]
    let contactAilmentChanceByStatusID: [Int: Double]
    let titleRollCountModifier: Int
    let equipmentCapacityModifier: Int
    let normalDropJewelizeChance: Double
    let multiHitFalloffModifier: Double
    let hitRateFloor: Double
    let defenseRuleValuesByTarget: [String: [Double]]
    let recoveryRuleValuesByTarget: [String: [Double]]
    let actionRuleValuesByTarget: [String: [Double]]
    let reviveRuleValuesByTarget: [String: [Double]]
    let combatRuleValuesByTarget: [String: [Double]]
    let rewardRuleValuesByTarget: [String: [Double]]
    let specialRuleValuesByTarget: [String: [Double]]

    var maxHP: Int {
        battleStats.maxHP
    }

    func spellDamageMultiplier(for spellID: Int) -> Double {
        spellDamageMultipliersBySpellID[spellID] ?? 1.0
    }

    func magicResistanceMultiplier(for spellID: Int) -> Double {
        spellResistanceMultipliersBySpellID[spellID] ?? 1.0
    }

    func rewardMultiplier(for target: String) -> Double {
        rewardMultipliersByTarget[target] ?? 1.0
    }

    func partyModifier(for target: String) -> Double {
        partyModifiersByTarget[target] ?? 1.0
    }

    func defenseRuleValues(for target: String) -> [Double] {
        defenseRuleValuesByTarget[target] ?? []
    }

    func defenseRuleMaxValue(for target: String) -> Double? {
        defenseRuleValues(for: target).max()
    }

    func defenseRuleProduct(for target: String) -> Double {
        defenseRuleValues(for: target).reduce(1.0, *)
    }

    func recoveryRuleValues(for target: String) -> [Double] {
        recoveryRuleValuesByTarget[target] ?? []
    }

    func recoveryRuleMaxValue(for target: String) -> Double? {
        recoveryRuleValues(for: target).max()
    }

    func recoveryRuleProduct(for target: String) -> Double {
        recoveryRuleValues(for: target).reduce(1.0, *)
    }

    func actionRuleValues(for target: String) -> [Double] {
        actionRuleValuesByTarget[target] ?? []
    }

    func actionRuleMaxValue(for target: String) -> Double? {
        actionRuleValues(for: target).max()
    }

    func actionRuleProduct(for target: String) -> Double {
        actionRuleValues(for: target).reduce(1.0, *)
    }

    func reviveRuleValues(for target: String) -> [Double] {
        reviveRuleValuesByTarget[target] ?? []
    }

    func reviveRuleMaxValue(for target: String) -> Double? {
        reviveRuleValues(for: target).max()
    }

    func combatRuleValues(for target: String) -> [Double] {
        combatRuleValuesByTarget[target] ?? []
    }

    func combatRuleMaxValue(for target: String) -> Double? {
        combatRuleValues(for: target).max()
    }

    func combatRuleProduct(for target: String) -> Double {
        combatRuleValues(for: target).reduce(1.0, *)
    }

    func rewardRuleValues(for target: String) -> [Double] {
        rewardRuleValuesByTarget[target] ?? []
    }

    func rewardRuleMaxValue(for target: String) -> Double? {
        rewardRuleValues(for: target).max()
    }

    func specialRuleValues(for target: String) -> [Double] {
        specialRuleValuesByTarget[target] ?? []
    }

    func specialRuleMaxValue(for target: String) -> Double? {
        specialRuleValues(for: target).max()
    }

    func specialRuleProduct(for target: String) -> Double {
        specialRuleValues(for: target).reduce(1.0, *)
    }
}

nonisolated struct CharacterBaseStats: Equatable, Sendable {
    var vitality: Int
    var strength: Int
    var mind: Int
    var intelligence: Int
    var agility: Int
    var luck: Int
}

nonisolated struct CharacterBattleStats: Equatable, Sendable {
    var maxHP: Int
    var physicalAttack: Int
    var physicalDefense: Int
    var magic: Int
    var magicDefense: Int
    var healing: Int
    var accuracy: Int
    var evasion: Int
    var attackCount: Int
    var criticalRate: Int
    var breathPower: Int
}

nonisolated struct CharacterBattleDerivedStats: Equatable, Sendable {
    let physicalDamageMultiplier: Double
    let attackMagicMultiplier: Double
    let healingMultiplier: Double
    let spellDamageMultiplier: Double
    let criticalDamageMultiplier: Double
    let meleeDamageMultiplier: Double
    let rangedDamageMultiplier: Double
    let actionSpeedMultiplier: Double
    let physicalResistanceMultiplier: Double
    let magicResistanceMultiplier: Double
    let breathResistanceMultiplier: Double

    static let baseline = CharacterBattleDerivedStats(
        physicalDamageMultiplier: 1.0,
        attackMagicMultiplier: 1.0,
        healingMultiplier: 1.0,
        spellDamageMultiplier: 1.0,
        criticalDamageMultiplier: 1.0,
        meleeDamageMultiplier: 1.0,
        rangedDamageMultiplier: 1.0,
        actionSpeedMultiplier: 1.0,
        physicalResistanceMultiplier: 1.0,
        magicResistanceMultiplier: 1.0,
        breathResistanceMultiplier: 1.0
    )
}
