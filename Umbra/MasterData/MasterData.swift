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
    nonisolated struct Metadata: Decodable, Sendable {
        let generator: String
    }

    nonisolated struct BaseStats: Decodable, Sendable {
        let vitality: Int
        let strength: Int
        let mind: Int
        let intelligence: Int
        let agility: Int
        let luck: Int
    }

    nonisolated struct BattleStats: Decodable, Sendable {
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

    nonisolated struct BattleStatCoefficients: Decodable, Sendable {
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

    nonisolated struct Race: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let levelCap: Int
        let baseHirePrice: Int
        let baseStats: BaseStats
        let skillIds: [Int]
    }

    nonisolated struct Job: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let hirePriceMultiplier: Double
        let coefficients: BattleStatCoefficients
        let passiveSkillIds: [Int]
        let levelSkillIds: [Int]
        let jobChangeRequirement: JobChangeRequirement?
    }

    nonisolated struct JobChangeRequirement: Decodable, Sendable {
        let requiredCurrentJobId: Int
        let requiredLevel: Int
    }

    nonisolated struct Aptitude: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
    }

    nonisolated struct Item: Identifiable, Decodable, Sendable {
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

    nonisolated struct Title: Identifiable, Decodable, Sendable {
        let id: Int
        let key: String
        let name: String
        let positiveMultiplier: Double
        let negativeMultiplier: Double
        let dropWeight: Int
    }

    nonisolated struct SuperRare: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let skillIds: [Int]
    }

    nonisolated struct Skill: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let description: String
        let effects: [SkillEffect]
    }

    nonisolated struct SkillEffect: Decodable, Sendable {
        let kind: SkillEffectKind
        let target: String?
        let operation: String?
        let value: Double?
        let spellIds: [Int]
        let condition: SkillEffectCondition?
        let interruptKind: InterruptKind?
    }

    nonisolated struct Spell: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let category: SpellCategory
        let kind: SpellKind
        let targetSide: TargetSide
        let targetCount: Int
        let multiplier: Double?
        let effectTarget: String?
        let statusId: Int?
        let statusChance: Double?

        init(
            id: Int,
            name: String,
            category: SpellCategory,
            kind: SpellKind,
            targetSide: TargetSide,
            targetCount: Int,
            multiplier: Double? = nil,
            effectTarget: String? = nil,
            statusId: Int? = nil,
            statusChance: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.kind = kind
            self.targetSide = targetSide
            self.targetCount = targetCount
            self.multiplier = multiplier
            self.effectTarget = effectTarget
            self.statusId = statusId
            self.statusChance = statusChance
        }
    }

    nonisolated struct RecruitNames: Decodable, Sendable {
        let male: [String]
        let female: [String]
        let unisex: [String]
    }

    nonisolated struct Enemy: Identifiable, Decodable, Sendable {
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

    nonisolated struct ActionRates: Decodable, Sendable {
        let breath: Int
        let attack: Int
        let recoverySpell: Int
        let attackSpell: Int
    }

    nonisolated struct Labyrinth: Identifiable, Decodable, Sendable {
        let id: Int
        let name: String
        let enemyCountCap: Int
        let progressIntervalSeconds: Int
        let floors: [Floor]
    }

    nonisolated struct Floor: Identifiable, Decodable, Sendable {
        let id: Int
        let floorNumber: Int
        let battleCount: Int
        let encounters: [Encounter]
        let fixedBattle: [FixedBattle]?
    }

    nonisolated struct Encounter: Decodable, Sendable {
        let enemyId: Int
        let level: Int
        let weight: Int
    }

    nonisolated struct FixedBattle: Decodable, Sendable {
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

extension MasterData {
    nonisolated var explorationDifficultyTitles: [Title] {
        let sortedTitles = titles.sorted { lhs, rhs in
            if lhs.positiveMultiplier != rhs.positiveMultiplier {
                return lhs.positiveMultiplier < rhs.positiveMultiplier
            }
            return lhs.id < rhs.id
        }
        guard let untitledTitle = titles.first(where: { $0.key == "untitled" }) else {
            return Array(sortedTitles.prefix(4))
        }

        let higherTitles = sortedTitles
            .filter { $0.positiveMultiplier > untitledTitle.positiveMultiplier }
        return [untitledTitle] + Array(higherTitles.prefix(3))
    }

    nonisolated var defaultExplorationDifficultyTitle: Title? {
        explorationDifficultyTitles.first
    }

    nonisolated func explorationDifficultyTitle(id: Int?) -> Title? {
        guard let id else {
            return defaultExplorationDifficultyTitle
        }

        return explorationDifficultyTitles.first(where: { $0.id == id }) ?? defaultExplorationDifficultyTitle
    }

    nonisolated func nextExplorationDifficultyTitleId(after titleId: Int) -> Int? {
        let titles = explorationDifficultyTitles
        guard let index = titles.firstIndex(where: { $0.id == titleId }),
              titles.indices.contains(index + 1) else {
            return nil
        }

        return titles[index + 1].id
    }

    nonisolated func explorationDifficultyDisplayName(for titleId: Int?) -> String {
        guard let title = explorationDifficultyTitle(id: titleId) else {
            return "不明な難易度"
        }

        return title.name.isEmpty ? "無称号" : title.name
    }

    nonisolated func explorationLabyrinthDisplayName(
        labyrinthName: String,
        difficultyTitleId: Int?
    ) -> String {
        guard let title = explorationDifficultyTitle(id: difficultyTitleId),
              !title.name.isEmpty else {
            return labyrinthName
        }

        return "\(title.name)\(labyrinthName)"
    }

    nonisolated func resolvedExplorationDifficultyTitleId(
        requestedTitleId: Int?,
        highestUnlockedTitleId: Int?
    ) -> Int {
        let titles = explorationDifficultyTitles
        guard let defaultTitle = defaultExplorationDifficultyTitle else {
            return requestedTitleId ?? highestUnlockedTitleId ?? 1
        }

        let highestUnlockedId = highestUnlockedTitleId ?? defaultTitle.id
        let unlockedIndex = titles.firstIndex(where: { $0.id == highestUnlockedId }) ?? 0
        let requestedIndex = requestedTitleId.flatMap { titleId in
            titles.firstIndex(where: { $0.id == titleId })
        } ?? 0
        return titles[min(requestedIndex, unlockedIndex)].id
    }
}
