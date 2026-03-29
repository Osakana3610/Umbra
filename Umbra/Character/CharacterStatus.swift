// Represents a character's fully derived runtime status and combat capabilities.

struct CharacterStatus: Equatable, Sendable {
    let baseStats: CharacterBaseStats
    let battleStats: CharacterBattleStats
    let battleDerivedStats: CharacterBattleDerivedStats
    let skillIds: [Int]
    let spellIds: [Int]
    let interruptKinds: [InterruptKind]
    let canUseBreath: Bool
    let isUnarmed: Bool
    let weaponRangeClass: ItemRangeClass

    var maxHP: Int {
        battleStats.maxHP
    }
}

struct CharacterBaseStats: Equatable, Sendable {
    let vitality: Int
    let strength: Int
    let mind: Int
    let intelligence: Int
    let agility: Int
    let luck: Int
}

struct CharacterBattleStats: Equatable, Sendable {
    let maxHP: Int
    let physicalAttack: Int
    let physicalDefense: Int
    let magic: Int
    let magicDefense: Int
    let healing: Int
    let accuracy: Int
    let evasion: Int
    let attackCount: Int
    let criticalRate: Int
    let breathPower: Int
}

struct CharacterBattleDerivedStats: Equatable, Sendable {
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
