// Represents a character's fully derived combat and rule state after job, level, and equipment
// resolution have been applied.
// Call sites read this as an immutable snapshot during battle, exploration, and UI calculations so
// repeated lookups do not need to recompute modifiers from master data.

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
    let rewardMultipliersByTarget: [RewardMultiplierTarget: Double]
    let partyModifiersByTarget: [PartyModifierTarget: Double]
    let onHitAilmentChanceByStatusID: [Int: Double]
    let contactAilmentChanceByStatusID: [Int: Double]
    let titleRollCountModifier: Int
    let equipmentCapacityModifier: Int
    let normalDropJewelizeChance: Double
    let multiHitFalloffModifier: Double
    let hitRateFloor: Double
    let defenseRuleValuesByTarget: [DefenseRuleTarget: [Double]]
    let recoveryRuleValuesByTarget: [RecoveryRuleTarget: [Double]]
    let actionRuleValuesByTarget: [ActionRuleTarget: [Double]]
    let reviveRuleValuesByTarget: [ReviveRuleTarget: [Double]]
    let combatRuleValuesByTarget: [CombatRuleTarget: [Double]]
    let rewardRuleValuesByTarget: [RewardRuleTarget: [Double]]
    let equipmentRuleValuesByTarget: [EquipmentRuleTarget: [Double]]
    let explorationRuleValuesByTarget: [ExplorationRuleTarget: [Double]]
    let hitRuleValuesByTarget: [HitRuleTarget: [Double]]

    var maxHP: Int {
        battleStats.maxHP
    }

    func spellDamageMultiplier(for spellID: Int) -> Double {
        spellDamageMultipliersBySpellID[spellID] ?? 1.0
    }

    func magicResistanceMultiplier(for spellID: Int) -> Double {
        spellResistanceMultipliersBySpellID[spellID] ?? 1.0
    }

    func rewardMultiplier(for target: RewardMultiplierTarget) -> Double {
        rewardMultipliersByTarget[target] ?? 1.0
    }

    func partyModifier(for target: PartyModifierTarget) -> Double {
        partyModifiersByTarget[target] ?? 1.0
    }

    // Rule dictionaries retain every applicable contribution for a target so callers can apply the
    // rule-specific reduction they need, such as max-only or multiplicative stacking.
    func defenseRuleValues(for target: DefenseRuleTarget) -> [Double] {
        defenseRuleValuesByTarget[target] ?? []
    }

    func defenseRuleMaxValue(for target: DefenseRuleTarget) -> Double? {
        defenseRuleValues(for: target).max()
    }

    func defenseRuleProduct(for target: DefenseRuleTarget) -> Double {
        defenseRuleValues(for: target).reduce(1.0, *)
    }

    func recoveryRuleValues(for target: RecoveryRuleTarget) -> [Double] {
        recoveryRuleValuesByTarget[target] ?? []
    }

    func recoveryRuleMaxValue(for target: RecoveryRuleTarget) -> Double? {
        recoveryRuleValues(for: target).max()
    }

    func recoveryRuleProduct(for target: RecoveryRuleTarget) -> Double {
        recoveryRuleValues(for: target).reduce(1.0, *)
    }

    func actionRuleValues(for target: ActionRuleTarget) -> [Double] {
        actionRuleValuesByTarget[target] ?? []
    }

    func actionRuleMaxValue(for target: ActionRuleTarget) -> Double? {
        actionRuleValues(for: target).max()
    }

    func reviveRuleValues(for target: ReviveRuleTarget) -> [Double] {
        reviveRuleValuesByTarget[target] ?? []
    }

    func reviveRuleMaxValue(for target: ReviveRuleTarget) -> Double? {
        reviveRuleValues(for: target).max()
    }

    func combatRuleValues(for target: CombatRuleTarget) -> [Double] {
        combatRuleValuesByTarget[target] ?? []
    }

    func combatRuleMaxValue(for target: CombatRuleTarget) -> Double? {
        combatRuleValues(for: target).max()
    }

    func combatRuleProduct(for target: CombatRuleTarget) -> Double {
        combatRuleValues(for: target).reduce(1.0, *)
    }

    func rewardRuleValues(for target: RewardRuleTarget) -> [Double] {
        rewardRuleValuesByTarget[target] ?? []
    }

    func equipmentRuleValues(for target: EquipmentRuleTarget) -> [Double] {
        equipmentRuleValuesByTarget[target] ?? []
    }

    func equipmentRuleProduct(for target: EquipmentRuleTarget) -> Double {
        equipmentRuleValues(for: target).reduce(1.0, *)
    }

    func explorationRuleValues(for target: ExplorationRuleTarget) -> [Double] {
        explorationRuleValuesByTarget[target] ?? []
    }

    func explorationRuleProduct(for target: ExplorationRuleTarget) -> Double {
        explorationRuleValues(for: target).reduce(1.0, *)
    }

    func hitRuleValues(for target: HitRuleTarget) -> [Double] {
        hitRuleValuesByTarget[target] ?? []
    }

    func hitRuleMaxValue(for target: HitRuleTarget) -> Double? {
        hitRuleValues(for: target).max()
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
    let spellDamageMultiplier: Double
    let criticalDamageMultiplier: Double
    let meleeDamageMultiplier: Double
    let rangedDamageMultiplier: Double
    let actionSpeedMultiplier: Double
    let physicalResistanceMultiplier: Double
    let magicResistanceMultiplier: Double
    let breathResistanceMultiplier: Double

    // The baseline represents an actor with no derived modifiers from skills, equipment, or rules.
    static let baseline = CharacterBattleDerivedStats(
        physicalDamageMultiplier: 1.0,
        attackMagicMultiplier: 1.0,
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
