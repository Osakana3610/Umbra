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
    private let defenseRuleMaxValuesByTarget: [DefenseRuleTarget: Double]
    private let defenseRuleProductsByTarget: [DefenseRuleTarget: Double]
    private let recoveryRuleMaxValuesByTarget: [RecoveryRuleTarget: Double]
    private let recoveryRuleProductsByTarget: [RecoveryRuleTarget: Double]
    private let actionRuleMaxValuesByTarget: [ActionRuleTarget: Double]
    private let reviveRuleMaxValuesByTarget: [ReviveRuleTarget: Double]
    private let combatRuleMaxValuesByTarget: [CombatRuleTarget: Double]
    private let combatRuleProductsByTarget: [CombatRuleTarget: Double]
    private let equipmentRuleProductsByTarget: [EquipmentRuleTarget: Double]
    private let explorationRuleProductsByTarget: [ExplorationRuleTarget: Double]
    private let hitRuleMaxValuesByTarget: [HitRuleTarget: Double]

    init(
        baseStats: CharacterBaseStats,
        battleStats: CharacterBattleStats,
        battleDerivedStats: CharacterBattleDerivedStats,
        skillIds: [Int],
        spellIds: [Int],
        interruptKinds: [InterruptKind],
        canUseBreath: Bool,
        isUnarmed: Bool,
        hasMeleeWeapon: Bool,
        hasRangedWeapon: Bool,
        weaponRangeClass: ItemRangeClass,
        spellDamageMultipliersBySpellID: [Int: Double],
        spellResistanceMultipliersBySpellID: [Int: Double],
        rewardMultipliersByTarget: [RewardMultiplierTarget: Double],
        partyModifiersByTarget: [PartyModifierTarget: Double],
        onHitAilmentChanceByStatusID: [Int: Double],
        contactAilmentChanceByStatusID: [Int: Double],
        titleRollCountModifier: Int,
        equipmentCapacityModifier: Int,
        normalDropJewelizeChance: Double,
        multiHitFalloffModifier: Double,
        hitRateFloor: Double,
        defenseRuleValuesByTarget: [DefenseRuleTarget: [Double]],
        recoveryRuleValuesByTarget: [RecoveryRuleTarget: [Double]],
        actionRuleValuesByTarget: [ActionRuleTarget: [Double]],
        reviveRuleValuesByTarget: [ReviveRuleTarget: [Double]],
        combatRuleValuesByTarget: [CombatRuleTarget: [Double]],
        rewardRuleValuesByTarget: [RewardRuleTarget: [Double]],
        equipmentRuleValuesByTarget: [EquipmentRuleTarget: [Double]],
        explorationRuleValuesByTarget: [ExplorationRuleTarget: [Double]],
        hitRuleValuesByTarget: [HitRuleTarget: [Double]]
    ) {
        self.baseStats = baseStats
        self.battleStats = battleStats
        self.battleDerivedStats = battleDerivedStats
        self.skillIds = skillIds
        self.spellIds = spellIds
        self.interruptKinds = interruptKinds
        self.canUseBreath = canUseBreath
        self.isUnarmed = isUnarmed
        self.hasMeleeWeapon = hasMeleeWeapon
        self.hasRangedWeapon = hasRangedWeapon
        self.weaponRangeClass = weaponRangeClass
        self.spellDamageMultipliersBySpellID = spellDamageMultipliersBySpellID
        self.spellResistanceMultipliersBySpellID = spellResistanceMultipliersBySpellID
        self.rewardMultipliersByTarget = rewardMultipliersByTarget
        self.partyModifiersByTarget = partyModifiersByTarget
        self.onHitAilmentChanceByStatusID = onHitAilmentChanceByStatusID
        self.contactAilmentChanceByStatusID = contactAilmentChanceByStatusID
        self.titleRollCountModifier = titleRollCountModifier
        self.equipmentCapacityModifier = equipmentCapacityModifier
        self.normalDropJewelizeChance = normalDropJewelizeChance
        self.multiHitFalloffModifier = multiHitFalloffModifier
        self.hitRateFloor = hitRateFloor
        self.defenseRuleValuesByTarget = defenseRuleValuesByTarget
        self.recoveryRuleValuesByTarget = recoveryRuleValuesByTarget
        self.actionRuleValuesByTarget = actionRuleValuesByTarget
        self.reviveRuleValuesByTarget = reviveRuleValuesByTarget
        self.combatRuleValuesByTarget = combatRuleValuesByTarget
        self.rewardRuleValuesByTarget = rewardRuleValuesByTarget
        self.equipmentRuleValuesByTarget = equipmentRuleValuesByTarget
        self.explorationRuleValuesByTarget = explorationRuleValuesByTarget
        self.hitRuleValuesByTarget = hitRuleValuesByTarget
        self.defenseRuleMaxValuesByTarget = ruleMaximums(for: defenseRuleValuesByTarget)
        self.defenseRuleProductsByTarget = ruleProducts(for: defenseRuleValuesByTarget)
        self.recoveryRuleMaxValuesByTarget = ruleMaximums(for: recoveryRuleValuesByTarget)
        self.recoveryRuleProductsByTarget = ruleProducts(for: recoveryRuleValuesByTarget)
        self.actionRuleMaxValuesByTarget = ruleMaximums(for: actionRuleValuesByTarget)
        self.reviveRuleMaxValuesByTarget = ruleMaximums(for: reviveRuleValuesByTarget)
        self.combatRuleMaxValuesByTarget = ruleMaximums(for: combatRuleValuesByTarget)
        self.combatRuleProductsByTarget = ruleProducts(for: combatRuleValuesByTarget)
        self.equipmentRuleProductsByTarget = ruleProducts(for: equipmentRuleValuesByTarget)
        self.explorationRuleProductsByTarget = ruleProducts(for: explorationRuleValuesByTarget)
        self.hitRuleMaxValuesByTarget = ruleMaximums(for: hitRuleValuesByTarget)
    }

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
        defenseRuleMaxValuesByTarget[target]
    }

    func defenseRuleProduct(for target: DefenseRuleTarget) -> Double {
        defenseRuleProductsByTarget[target] ?? 1.0
    }

    func recoveryRuleValues(for target: RecoveryRuleTarget) -> [Double] {
        recoveryRuleValuesByTarget[target] ?? []
    }

    func recoveryRuleMaxValue(for target: RecoveryRuleTarget) -> Double? {
        recoveryRuleMaxValuesByTarget[target]
    }

    func recoveryRuleProduct(for target: RecoveryRuleTarget) -> Double {
        recoveryRuleProductsByTarget[target] ?? 1.0
    }

    func actionRuleValues(for target: ActionRuleTarget) -> [Double] {
        actionRuleValuesByTarget[target] ?? []
    }

    func actionRuleMaxValue(for target: ActionRuleTarget) -> Double? {
        actionRuleMaxValuesByTarget[target]
    }

    func reviveRuleValues(for target: ReviveRuleTarget) -> [Double] {
        reviveRuleValuesByTarget[target] ?? []
    }

    func reviveRuleMaxValue(for target: ReviveRuleTarget) -> Double? {
        reviveRuleMaxValuesByTarget[target]
    }

    func combatRuleValues(for target: CombatRuleTarget) -> [Double] {
        combatRuleValuesByTarget[target] ?? []
    }

    func combatRuleMaxValue(for target: CombatRuleTarget) -> Double? {
        combatRuleMaxValuesByTarget[target]
    }

    func combatRuleProduct(for target: CombatRuleTarget) -> Double {
        combatRuleProductsByTarget[target] ?? 1.0
    }

    func rewardRuleValues(for target: RewardRuleTarget) -> [Double] {
        rewardRuleValuesByTarget[target] ?? []
    }

    func equipmentRuleValues(for target: EquipmentRuleTarget) -> [Double] {
        equipmentRuleValuesByTarget[target] ?? []
    }

    func equipmentRuleProduct(for target: EquipmentRuleTarget) -> Double {
        equipmentRuleProductsByTarget[target] ?? 1.0
    }

    func explorationRuleValues(for target: ExplorationRuleTarget) -> [Double] {
        explorationRuleValuesByTarget[target] ?? []
    }

    func explorationRuleProduct(for target: ExplorationRuleTarget) -> Double {
        explorationRuleProductsByTarget[target] ?? 1.0
    }

    func hitRuleValues(for target: HitRuleTarget) -> [Double] {
        hitRuleValuesByTarget[target] ?? []
    }

    func hitRuleMaxValue(for target: HitRuleTarget) -> Double? {
        hitRuleMaxValuesByTarget[target]
    }

}

nonisolated private func ruleMaximums<Key: Hashable>(
    for valuesByTarget: [Key: [Double]]
) -> [Key: Double] {
    valuesByTarget.reduce(into: [:]) { partialResult, entry in
        partialResult[entry.key] = entry.value.max()
    }
}

nonisolated private func ruleProducts<Key: Hashable>(
    for valuesByTarget: [Key: [Double]]
) -> [Key: Double] {
    valuesByTarget.reduce(into: [:]) { partialResult, entry in
        partialResult[entry.key] = entry.value.reduce(1.0, *)
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
