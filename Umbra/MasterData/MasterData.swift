// Defines the runtime schema loaded from the generated master-data bundle.

import Foundation

nonisolated struct MasterData: Decodable, Sendable {
    let metadata: Metadata
    let races: [Race]
    let jobs: [Job]
    let aptitudes: [Aptitude]
    let items: [Item]
    let titles: [Title]
    let superRares: [SuperRare]
    let skills: [Skill]
    let spells: [Spell]
    let recruitNames: RecruitNames
    let enemies: [Enemy]
    let labyrinths: [Labyrinth]
}

extension MasterData {
    struct Metadata: Decodable, Sendable {
        let generator: String
    }

    struct BaseStats: Decodable, Sendable {
        let vitality: Int
        let strength: Int
        let mind: Int
        let intelligence: Int
        let agility: Int
        let luck: Int
    }

    struct BattleStats: Decodable, Sendable {
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

    struct BattleStatCoefficients: Decodable, Sendable {
        let maxHP: Double
        let physicalAttack: Double
        let physicalDefense: Double
        let magic: Double
        let magicDefense: Double
        let healing: Double
        let accuracy: Double
        let evasion: Double
        let attackCount: Double
        let criticalRate: Double
        let breathPower: Double
    }

    struct Race: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let levelCap: Int
        let baseHirePrice: Int
        let baseStats: BaseStats
        let skillIds: [Int]
    }

    struct Job: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let hirePriceMultiplier: Double
        let coefficients: BattleStatCoefficients
        let skillIds: [Int]
    }

    struct Aptitude: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
    }

    struct Item: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let category: ItemCategory
        let rarity: ItemRarity
        let basePrice: Int
        let nativeBaseStats: BaseStats
        let nativeBattleStats: BattleStats
        let skillIds: [Int]
        let rangeClass: ItemRangeClass
        let normalDropTier: Int
    }

    struct Title: Identifiable, Decodable, Sendable {
        let id: Int
        let key: String
        let name: String
        let positiveMultiplier: Double
        let negativeMultiplier: Double
        let dropWeight: Int
    }

    struct SuperRare: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let skillIds: [Int]
    }

    struct Skill: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let description: String
        let effects: [SkillEffect]
    }

    struct SkillEffect: Decodable, Sendable {
        let kind: SkillEffectKind
        let target: String?
        let operation: String?
        let value: Double?
        let spellIds: [Int]
        let condition: SkillEffectCondition?
        let interruptKind: InterruptKind?
    }

    struct Spell: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let category: SpellCategory
        let kind: SpellKind
        let targetSide: TargetSide
        let targetCount: Int
        let multiplier: Double?
        let effectTarget: String?
    }

    struct RecruitNames: Decodable, Sendable {
        let male: [String]
        let female: [String]
        let unisex: [String]
    }

    struct Enemy: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let enemyRace: EnemyRace
        let jobId: Int
        let baseStats: BaseStats
        let goldBaseValue: Int
        let experienceBaseValue: Int
        let skillIds: [Int]
        let rareDropItemIds: [Int]
        let actionRates: ActionRates
        let actionPriority: [BattleActionKind]
    }

    struct ActionRates: Decodable, Sendable {
        let breath: Int
        let attack: Int
        let recoverySpell: Int
        let attackSpell: Int
    }

    struct Labyrinth: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let enemyCountCap: Int
        let progressIntervalSeconds: Int
        let floors: [Floor]
    }

    struct Floor: Identifiable, Decodable, Sendable {
        let id: Int
        let floorNumber: Int
        let battleCount: Int
        let encounters: [Encounter]
        let fixedBattle: [FixedBattle]?
    }

    struct Encounter: Decodable, Sendable {
        let enemyId: Int
        let level: Int
        let weight: Int
    }

    struct FixedBattle: Decodable, Sendable {
        let enemyId: Int
        let level: Int
    }
}

nonisolated enum ItemCategory: String, Decodable, Sendable {
    case sword
    case katana
    case bow
    case wand
    case rod
    case armor
    case shield
    case robe
    case gauntlet
    case jewel
    case misc
}

nonisolated enum ItemRarity: String, Decodable, Sendable {
    case normal
    case uncommon
    case rare
    case mythic
    case godfiend
}

nonisolated enum ItemRangeClass: String, Decodable, Sendable {
    case none
    case melee
    case ranged
}

nonisolated enum SkillEffectKind: String, Decodable, Sendable {
    case battleStatModifier
    case battleDerivedModifier
    case allBattleStatMultiplier
    case rewardMultiplier
    case magicAccess
    case breathAccess
    case interruptGrant
}

nonisolated enum SkillEffectCondition: String, Decodable, Sendable {
    case unarmed
}

nonisolated enum InterruptKind: String, Decodable, Sendable {
    case rescue
    case counter
    case extraAttack
    case pursuit
}

nonisolated enum SpellCategory: String, Decodable, Sendable {
    case attack
    case recovery
}

nonisolated enum SpellKind: String, Decodable, Sendable {
    case damage
    case buff
    case heal
    case cleanse
    case barrier
    case fullHeal
}

nonisolated enum TargetSide: String, Decodable, Sendable {
    case ally
    case enemy
    case both
}

nonisolated enum EnemyRace: String, Decodable, Sendable {
    case dragon
    case monster
    case zombie
    case godfiend
}

nonisolated enum BattleActionKind: String, Decodable, Sendable {
    case breath
    case attack
    case recoverySpell
    case attackSpell
}
