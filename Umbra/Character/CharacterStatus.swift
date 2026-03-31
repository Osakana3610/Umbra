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
    let weaponRangeClass: ItemRangeClass
    let spellDamageMultipliersBySpellID: [Int: Double]
    let spellResistanceMultipliersBySpellID: [Int: Double]

    var maxHP: Int {
        battleStats.maxHP
    }

    func spellDamageMultiplier(for spellID: Int) -> Double {
        spellDamageMultipliersBySpellID[spellID] ?? 1.0
    }

    func magicResistanceMultiplier(for spellID: Int) -> Double {
        spellResistanceMultipliersBySpellID[spellID] ?? 1.0
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
    let magicDamageMultiplier: Double
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
        magicDamageMultiplier: 1.0,
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
