// Calculates a character's complete runtime status from persisted state and master data.

import Foundation

enum CharacterDerivedStatsCalculator {
    private static let levelExponent = 1.0
    private static let isUnarmed = true
    private static let weaponRangeClass: ItemRangeClass = .none

    static func maxHP(
        raceId: Int,
        currentJobId: Int,
        level: Int,
        masterData: MasterData
    ) -> Int? {
        status(
            raceId: raceId,
            previousJobId: 0,
            currentJobId: currentJobId,
            level: level,
            masterData: masterData
        )?.maxHP
    }

    static func status(for character: CharacterRecord, masterData: MasterData) -> CharacterStatus? {
        status(
            raceId: character.raceId,
            previousJobId: character.previousJobId,
            currentJobId: character.currentJobId,
            level: character.level,
            masterData: masterData
        )
    }

    static func status(
        raceId: Int,
        previousJobId: Int,
        currentJobId: Int,
        level: Int,
        masterData: MasterData
    ) -> CharacterStatus? {
        guard let race = masterData.races.first(where: { $0.id == raceId }),
              let currentJob = masterData.jobs.first(where: { $0.id == currentJobId }) else {
            return nil
        }

        let previousJob = previousJobId == 0
            ? nil
            : masterData.jobs.first(where: { $0.id == previousJobId })

        let effectiveBaseStats = CharacterBaseStats(
            vitality: race.baseStats.vitality,
            strength: race.baseStats.strength,
            mind: race.baseStats.mind,
            intelligence: race.baseStats.intelligence,
            agility: race.baseStats.agility,
            luck: race.baseStats.luck
        )
        let activeSkillIds = activeSkillIds(
            raceSkillIds: race.skillIds,
            previousJobSkillIds: previousJob?.skillIds ?? [],
            currentJobSkillIds: currentJob.skillIds
        )

        return status(
            baseStats: effectiveBaseStats,
            jobId: currentJobId,
            level: level,
            skillIds: activeSkillIds,
            masterData: masterData,
            isUnarmed: isUnarmed,
            weaponRangeClass: weaponRangeClass
        )
    }

    static func status(
        baseStats: CharacterBaseStats,
        jobId: Int,
        level: Int,
        skillIds: [Int],
        masterData: MasterData,
        isUnarmed: Bool = isUnarmed,
        weaponRangeClass: ItemRangeClass = weaponRangeClass
    ) -> CharacterStatus? {
        guard let currentJob = masterData.jobs.first(where: { $0.id == jobId }) else {
            return nil
        }

        let activeSkillIds = deduplicatedSkillIds(skillIds)
        let skillLookup = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        let skillAdjustments = skillAdjustments(
            activeSkillIds: activeSkillIds,
            skillLookup: skillLookup,
            isUnarmed: isUnarmed
        )

        let battleStats = CharacterBattleStats(
            maxHP: battleStatValue(
                target: "maxHP",
                baseInput: Double(baseStats.vitality),
                level: level,
                jobCoefficient: currentJob.coefficients.maxHP,
                statScale: 3.0,
                skillAdjustments: skillAdjustments
            ),
            physicalAttack: battleStatValue(
                target: "physicalAttack",
                baseInput: Double(baseStats.strength),
                level: level,
                jobCoefficient: currentJob.coefficients.physicalAttack,
                statScale: 0.6,
                skillAdjustments: skillAdjustments
            ),
            physicalDefense: battleStatValue(
                target: "physicalDefense",
                baseInput: average(baseStats.vitality, baseStats.strength),
                level: level,
                jobCoefficient: currentJob.coefficients.physicalDefense,
                statScale: 0.3,
                skillAdjustments: skillAdjustments
            ),
            magic: battleStatValue(
                target: "magic",
                baseInput: Double(baseStats.intelligence),
                level: level,
                jobCoefficient: currentJob.coefficients.magic,
                statScale: 0.6,
                skillAdjustments: skillAdjustments
            ),
            magicDefense: battleStatValue(
                target: "magicDefense",
                baseInput: average(baseStats.intelligence, baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.magicDefense,
                statScale: 0.3,
                skillAdjustments: skillAdjustments
            ),
            healing: battleStatValue(
                target: "healing",
                baseInput: Double(baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.healing,
                statScale: 0.45,
                skillAdjustments: skillAdjustments
            ),
            accuracy: battleStatValue(
                target: "accuracy",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.accuracy,
                statScale: 0.10,
                skillAdjustments: skillAdjustments
            ),
            evasion: battleStatValue(
                target: "evasion",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.evasion,
                statScale: 0.09,
                skillAdjustments: skillAdjustments
            ),
            attackCount: battleStatValue(
                target: "attackCount",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.attackCount,
                statScale: 0.003,
                skillAdjustments: skillAdjustments
            ),
            criticalRate: battleStatValue(
                target: "criticalRate",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.criticalRate,
                statScale: 0.010,
                skillAdjustments: skillAdjustments
            ),
            breathPower: battleStatValue(
                target: "breathPower",
                baseInput: average(baseStats.vitality, baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.breathPower,
                statScale: 0.6,
                skillAdjustments: skillAdjustments
            )
        )

        let battleDerivedStats = CharacterBattleDerivedStats(
            physicalDamageMultiplier: battleDerivedValue(
                target: "physicalDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            magicDamageMultiplier: battleDerivedValue(
                target: "magicDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            spellDamageMultiplier: battleDerivedValue(
                target: "spellDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            criticalDamageMultiplier: battleDerivedValue(
                target: "criticalDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            meleeDamageMultiplier: battleDerivedValue(
                target: "meleeDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            rangedDamageMultiplier: battleDerivedValue(
                target: "rangedDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            actionSpeedMultiplier: battleDerivedValue(
                target: "actionSpeedMultiplier",
                skillAdjustments: skillAdjustments
            ),
            physicalResistanceMultiplier: battleDerivedValue(
                target: "physicalResistanceMultiplier",
                skillAdjustments: skillAdjustments
            ),
            magicResistanceMultiplier: battleDerivedValue(
                target: "magicResistanceMultiplier",
                skillAdjustments: skillAdjustments
            ),
            breathResistanceMultiplier: battleDerivedValue(
                target: "breathResistanceMultiplier",
                skillAdjustments: skillAdjustments
            )
        )

        return CharacterStatus(
            baseStats: baseStats,
            battleStats: battleStats,
            battleDerivedStats: battleDerivedStats,
            skillIds: activeSkillIds,
            spellIds: Array(skillAdjustments.grantedSpellIds.subtracting(skillAdjustments.revokedSpellIds))
                .sorted(),
            interruptKinds: skillAdjustments.interruptKinds.sorted { $0.rawValue < $1.rawValue },
            canUseBreath: skillAdjustments.canUseBreath,
            isUnarmed: isUnarmed,
            weaponRangeClass: weaponRangeClass
        )
    }

    private static func activeSkillIds(
        raceSkillIds: [Int],
        previousJobSkillIds: [Int],
        currentJobSkillIds: [Int]
    ) -> [Int] {
        deduplicatedSkillIds(raceSkillIds + previousJobSkillIds + currentJobSkillIds)
    }

    private static func deduplicatedSkillIds(_ skillIds: [Int]) -> [Int] {
        var seenSkillIds = Set<Int>()
        var deduplicatedSkillIds: [Int] = []

        for skillId in skillIds {
            guard seenSkillIds.insert(skillId).inserted else {
                continue
            }

            deduplicatedSkillIds.append(skillId)
        }

        return deduplicatedSkillIds
    }

    private static func skillAdjustments(
        activeSkillIds: [Int],
        skillLookup: [Int: MasterData.Skill],
        isUnarmed: Bool
    ) -> SkillAdjustments {
        var adjustments = SkillAdjustments()

        for skillId in activeSkillIds {
            guard let skill = skillLookup[skillId] else {
                continue
            }

            for effect in skill.effects where isEffectActive(effect, isUnarmed: isUnarmed) {
                adjustments.apply(effect)
            }
        }

        return adjustments
    }

    private static func isEffectActive(
        _ effect: MasterData.SkillEffect,
        isUnarmed: Bool
    ) -> Bool {
        switch effect.condition {
        case nil:
            true
        case .unarmed:
            isUnarmed
        }
    }

    private static func battleStatValue(
        target: String,
        baseInput: Double,
        level: Int,
        jobCoefficient: Double,
        statScale: Double,
        skillAdjustments: SkillAdjustments
    ) -> Int {
        let baseValue = Int(
            (
                baseInput
                * pow(Double(level), levelExponent)
                * jobCoefficient
                * statScale
            )
            .rounded()
        )
        let equipmentAdjusted = Double(baseValue)
        let flatAdjusted = equipmentAdjusted + skillAdjustments.battleStatFlatAdds[target, default: 0.0]
        let percentAdjusted = flatAdjusted * (1.0 + skillAdjustments.battleStatPctAdds[target, default: 0.0])
        let finalValue = Int((percentAdjusted * skillAdjustments.allBattleStatMultiplier).rounded())
        return clampedBattleStatValue(finalValue, target: target)
    }

    private static func clampedBattleStatValue(_ value: Int, target: String) -> Int {
        switch target {
        case "attackCount":
            max(value, 1)
        case "criticalRate":
            min(value, 75)
        default:
            value
        }
    }

    private static func battleDerivedValue(
        target: String,
        skillAdjustments: SkillAdjustments
    ) -> Double {
        let rawValue = (1.0 + skillAdjustments.battleDerivedPctAdds[target, default: 0.0])
            * skillAdjustments.battleDerivedMultipliers[target, default: 1.0]
        return max(rawValue, 0.0)
    }

    private static func average(_ lhs: Int, _ rhs: Int) -> Double {
        Double(lhs + rhs) / 2.0
    }
}

private struct SkillAdjustments {
    var battleStatFlatAdds: [String: Double] = [:]
    var battleStatPctAdds: [String: Double] = [:]
    var battleDerivedPctAdds: [String: Double] = [:]
    var battleDerivedMultipliers: [String: Double] = [:]
    var grantedSpellIds = Set<Int>()
    var revokedSpellIds = Set<Int>()
    var interruptKinds = Set<InterruptKind>()
    var canUseBreath = false
    var allBattleStatMultiplier = 1.0

    mutating func apply(_ effect: MasterData.SkillEffect) {
        switch effect.kind {
        case .battleStatModifier:
            guard let target = effect.target,
                  let operation = effect.operation,
                  let value = effect.value else {
                return
            }

            switch operation {
            case "flatAdd":
                battleStatFlatAdds[target, default: 0.0] += value
            case "pctAdd":
                battleStatPctAdds[target, default: 0.0] += value
            default:
                return
            }
        case .battleDerivedModifier:
            guard let target = effect.target,
                  let operation = effect.operation,
                  let value = effect.value else {
                return
            }

            switch operation {
            case "pctAdd":
                battleDerivedPctAdds[target, default: 0.0] += value
            case "mul":
                battleDerivedMultipliers[target, default: 1.0] *= value
            default:
                return
            }
        case .allBattleStatMultiplier:
            guard let value = effect.value else {
                return
            }

            switch effect.operation {
            case nil, "mul":
                allBattleStatMultiplier *= value
            case "pctAdd":
                allBattleStatMultiplier *= 1.0 + value
            default:
                return
            }
        case .magicAccess:
            guard let operation = effect.operation else {
                return
            }

            switch operation {
            case "grant":
                grantedSpellIds.formUnion(effect.spellIds)
            case "revoke":
                revokedSpellIds.formUnion(effect.spellIds)
            default:
                return
            }
        case .breathAccess:
            canUseBreath = true
        case .interruptGrant:
            guard let interruptKind = effect.interruptKind else {
                return
            }

            interruptKinds.insert(interruptKind)
        case .rewardMultiplier:
            return
        }
    }
}
