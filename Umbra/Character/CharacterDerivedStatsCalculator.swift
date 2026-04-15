// Calculates a character's complete runtime status from persisted state and master data.

import Foundation

nonisolated enum CharacterDerivedStatsCalculator {
    private static let levelExponent = 1.0
    private static let defaultEquipmentAggregation = EquipmentAggregation(
        baseStats: CharacterBaseStats(
            vitality: 0,
            strength: 0,
            mind: 0,
            intelligence: 0,
            agility: 0,
            luck: 0
        ),
        battleStats: CharacterBattleStats(
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
        armorBattleStats: CharacterBattleStats(
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
        categoryBattleStats: [:],
        itemSkillIDs: [],
        isUnarmed: true,
        hasMeleeWeapon: false,
        hasRangedWeapon: false,
        weaponRangeClass: .none
    )

    static func maxHP(
        raceId: Int,
        currentJobId: Int,
        aptitudeId: Int = 0,
        level: Int,
        masterData: MasterData
    ) -> Int? {
        status(
            raceId: raceId,
            previousJobId: 0,
            currentJobId: currentJobId,
            aptitudeId: aptitudeId,
            level: level,
            masterData: masterData
        )?.maxHP
    }

    static func status(for character: CharacterRecord, masterData: MasterData) -> CharacterStatus? {
        let equipmentAggregation = (try? EquipmentAggregator(masterData: masterData).aggregate(
            equippedItemStacks: character.equippedItemStacks
        )) ?? defaultEquipmentAggregation

        return status(
            raceId: character.raceId,
            previousJobId: character.previousJobId,
            currentJobId: character.currentJobId,
            aptitudeId: character.aptitudeId,
            level: character.level,
            masterData: masterData,
            equipmentAggregation: equipmentAggregation
        )
    }

    static func status(
        for enemy: MasterData.Enemy,
        level: Int,
        masterData: MasterData
    ) -> CharacterStatus? {
        guard let currentJob = masterData.jobs.first(where: { $0.id == enemy.jobId }) else {
            return nil
        }

        let activeSkillIds = activeSkillIds(
            racePassiveSkillIds: [],
            raceLevelSkillIds: [],
            previousJobPassiveSkillIds: [],
            currentJobPassiveSkillIds: currentJob.passiveSkillIds,
            currentJobLevelSkillIds: currentJob.levelSkillIds,
            aptitudePassiveSkillIds: [],
            level: level,
            additionalSkillIds: enemy.skillIds
        )

        return status(
            baseStats: CharacterBaseStats(
                vitality: enemy.baseStats.vitality,
                strength: enemy.baseStats.strength,
                mind: enemy.baseStats.mind,
                intelligence: enemy.baseStats.intelligence,
                agility: enemy.baseStats.agility,
                luck: enemy.baseStats.luck
            ),
            jobId: enemy.jobId,
            level: level,
            skillIds: activeSkillIds,
            masterData: masterData
        )
    }

    static func status(
        raceId: Int,
        previousJobId: Int,
        currentJobId: Int,
        aptitudeId: Int = 0,
        level: Int,
        masterData: MasterData,
        equipmentAggregation: EquipmentAggregation = defaultEquipmentAggregation
    ) -> CharacterStatus? {
        guard let race = masterData.races.first(where: { $0.id == raceId }),
              let currentJob = masterData.jobs.first(where: { $0.id == currentJobId }) else {
            return nil
        }

        let previousJob = previousJobId == 0
            ? nil
            : masterData.jobs.first(where: { $0.id == previousJobId })
        let aptitude = masterData.aptitudes.first(where: { $0.id == aptitudeId })

        // Equipment contributes directly to base stats and active skills before job coefficients
        // are applied, so derived battle values always reflect the fully equipped build.
        let effectiveBaseStats = CharacterBaseStats(
            vitality: race.baseStats.vitality + equipmentAggregation.baseStats.vitality,
            strength: race.baseStats.strength + equipmentAggregation.baseStats.strength,
            mind: race.baseStats.mind + equipmentAggregation.baseStats.mind,
            intelligence: race.baseStats.intelligence + equipmentAggregation.baseStats.intelligence,
            agility: race.baseStats.agility + equipmentAggregation.baseStats.agility,
            luck: race.baseStats.luck + equipmentAggregation.baseStats.luck
        )
        let activeSkillIds = activeSkillIds(
            racePassiveSkillIds: race.passiveSkillIds,
            raceLevelSkillIds: race.levelSkillIds,
            previousJobPassiveSkillIds: previousJob?.passiveSkillIds ?? [],
            currentJobPassiveSkillIds: currentJob.passiveSkillIds,
            currentJobLevelSkillIds: currentJob.levelSkillIds,
            aptitudePassiveSkillIds: aptitude?.passiveSkillIds ?? [],
            level: level,
            additionalSkillIds: equipmentAggregation.itemSkillIDs
        )

        return status(
            baseStats: effectiveBaseStats,
            jobId: currentJobId,
            level: level,
            skillIds: activeSkillIds,
            masterData: masterData,
            equipmentBattleStats: equipmentAggregation.battleStats,
            armorEquipmentBattleStats: equipmentAggregation.armorBattleStats,
            equipmentBattleStatsByCategory: equipmentAggregation.categoryBattleStats,
            isUnarmed: equipmentAggregation.isUnarmed,
            hasMeleeWeapon: equipmentAggregation.hasMeleeWeapon,
            hasRangedWeapon: equipmentAggregation.hasRangedWeapon,
            weaponRangeClass: equipmentAggregation.weaponRangeClass
        )
    }

    static func status(
        baseStats: CharacterBaseStats,
        jobId: Int,
        level: Int,
        skillIds: [Int],
        masterData: MasterData,
        equipmentBattleStats: CharacterBattleStats = defaultEquipmentAggregation.battleStats,
        armorEquipmentBattleStats: CharacterBattleStats = defaultEquipmentAggregation.armorBattleStats,
        equipmentBattleStatsByCategory: [ItemCategory: CharacterBattleStats] = defaultEquipmentAggregation.categoryBattleStats,
        isUnarmed: Bool = defaultEquipmentAggregation.isUnarmed,
        hasMeleeWeapon: Bool = defaultEquipmentAggregation.hasMeleeWeapon,
        hasRangedWeapon: Bool = defaultEquipmentAggregation.hasRangedWeapon,
        weaponRangeClass: ItemRangeClass = defaultEquipmentAggregation.weaponRangeClass
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
        let normalizedEquipmentBattleStatsByCategory = normalizedEquipmentBattleStatsByCategory(
            explicitCategoryBattleStats: equipmentBattleStatsByCategory,
            legacyArmorBattleStats: armorEquipmentBattleStats
        )
        let adjustedEquipmentBattleStats = adjustedEquipmentBattleStats(
            equipmentBattleStats: equipmentBattleStats,
            equipmentBattleStatsByCategory: normalizedEquipmentBattleStatsByCategory,
            skillAdjustments: skillAdjustments
        )

        let battleStats = CharacterBattleStats(
            maxHP: battleStatValue(
                target: "maxHP",
                baseInput: Double(baseStats.vitality),
                level: level,
                jobCoefficient: currentJob.coefficients.maxHP,
                statScale: 3.0,
                equipmentFlatBonus: adjustedEquipmentBattleStats.maxHP,
                skillAdjustments: skillAdjustments
            ),
            physicalAttack: battleStatValue(
                target: "physicalAttack",
                baseInput: Double(baseStats.strength),
                level: level,
                jobCoefficient: currentJob.coefficients.physicalAttack,
                statScale: 0.6,
                equipmentFlatBonus: adjustedEquipmentBattleStats.physicalAttack,
                skillAdjustments: skillAdjustments
            ),
            physicalDefense: battleStatValue(
                target: "physicalDefense",
                baseInput: average(baseStats.vitality, baseStats.strength),
                level: level,
                jobCoefficient: currentJob.coefficients.physicalDefense,
                statScale: 0.3,
                equipmentFlatBonus: adjustedEquipmentBattleStats.physicalDefense,
                skillAdjustments: skillAdjustments
            ),
            magic: battleStatValue(
                target: "magic",
                baseInput: Double(baseStats.intelligence),
                level: level,
                jobCoefficient: currentJob.coefficients.magic,
                statScale: 0.6,
                equipmentFlatBonus: adjustedEquipmentBattleStats.magic,
                skillAdjustments: skillAdjustments
            ),
            magicDefense: battleStatValue(
                target: "magicDefense",
                baseInput: average(baseStats.intelligence, baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.magicDefense,
                statScale: 0.3,
                equipmentFlatBonus: adjustedEquipmentBattleStats.magicDefense,
                skillAdjustments: skillAdjustments
            ),
            healing: battleStatValue(
                target: "healing",
                baseInput: Double(baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.healing,
                statScale: 0.45,
                equipmentFlatBonus: adjustedEquipmentBattleStats.healing,
                skillAdjustments: skillAdjustments
            ),
            accuracy: battleStatValue(
                target: "accuracy",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.accuracy,
                statScale: 0.10,
                equipmentFlatBonus: adjustedEquipmentBattleStats.accuracy,
                skillAdjustments: skillAdjustments
            ),
            evasion: battleStatValue(
                target: "evasion",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.evasion,
                statScale: 0.09,
                equipmentFlatBonus: adjustedEquipmentBattleStats.evasion,
                skillAdjustments: skillAdjustments
            ),
            attackCount: battleStatValue(
                target: "attackCount",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.attackCount,
                statScale: 0.003,
                equipmentFlatBonus: adjustedEquipmentBattleStats.attackCount,
                skillAdjustments: skillAdjustments
            ),
            criticalRate: battleStatValue(
                target: "criticalRate",
                baseInput: Double(baseStats.agility),
                level: level,
                jobCoefficient: currentJob.coefficients.criticalRate,
                statScale: 0.010,
                equipmentFlatBonus: adjustedEquipmentBattleStats.criticalRate,
                skillAdjustments: skillAdjustments
            ),
            breathPower: battleStatValue(
                target: "breathPower",
                baseInput: average(baseStats.vitality, baseStats.mind),
                level: level,
                jobCoefficient: currentJob.coefficients.breathPower,
                statScale: 0.6,
                equipmentFlatBonus: adjustedEquipmentBattleStats.breathPower,
                skillAdjustments: skillAdjustments
            )
        )

        let battleDerivedStats = CharacterBattleDerivedStats(
            physicalDamageMultiplier: battleDerivedValue(
                target: "physicalDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            attackMagicMultiplier: battleDerivedValue(
                target: "magicDamageMultiplier",
                skillAdjustments: skillAdjustments
            ),
            healingMultiplier: battleDerivedValue(
                target: "healingMultiplier",
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
        let spellDamageMultipliersBySpellID = spellSpecificBattleDerivedValues(
            target: "spellDamageMultiplier",
            skillAdjustments: skillAdjustments
        )
        let spellResistanceMultipliersBySpellID = spellSpecificBattleDerivedValues(
            target: "magicResistanceMultiplier",
            skillAdjustments: skillAdjustments
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
            hasMeleeWeapon: hasMeleeWeapon,
            hasRangedWeapon: hasRangedWeapon,
            weaponRangeClass: weaponRangeClass,
            spellDamageMultipliersBySpellID: spellDamageMultipliersBySpellID,
            spellResistanceMultipliersBySpellID: spellResistanceMultipliersBySpellID,
            rewardMultipliersByTarget: multiplierValues(
                pctAdds: skillAdjustments.rewardPctAdds,
                multipliers: skillAdjustments.rewardMultipliers
            ),
            partyModifiersByTarget: multiplierValues(
                pctAdds: skillAdjustments.partyModifierPctAdds,
                multipliers: skillAdjustments.partyModifierMultipliers
            ),
            onHitAilmentChanceByStatusID: skillAdjustments.onHitAilmentChanceByStatusID,
            contactAilmentChanceByStatusID: skillAdjustments.contactAilmentChanceByStatusID,
            titleRollCountModifier: skillAdjustments.titleRollCountModifier,
            equipmentCapacityModifier: skillAdjustments.equipmentCapacityModifier,
            normalDropJewelizeChance: skillAdjustments.normalDropJewelizeChance,
            multiHitFalloffModifier: skillAdjustments.multiHitFalloffModifier,
            hitRateFloor: skillAdjustments.hitRateFloor,
            defenseRuleValuesByTarget: skillAdjustments.defenseRuleValuesByTarget,
            recoveryRuleValuesByTarget: skillAdjustments.recoveryRuleValuesByTarget,
            actionRuleValuesByTarget: skillAdjustments.actionRuleValuesByTarget,
            reviveRuleValuesByTarget: skillAdjustments.reviveRuleValuesByTarget,
            combatRuleValuesByTarget: skillAdjustments.combatRuleValuesByTarget,
            rewardRuleValuesByTarget: skillAdjustments.rewardRuleValuesByTarget,
            specialRuleValuesByTarget: skillAdjustments.specialRuleValuesByTarget
        )
    }

    private static func adjustedEquipmentBattleStats(
        equipmentBattleStats: CharacterBattleStats,
        equipmentBattleStatsByCategory: [ItemCategory: CharacterBattleStats],
        skillAdjustments: SkillAdjustments
    ) -> CharacterBattleStats {
        let magicDefenseMultiplier = skillAdjustments.specialRuleProduct(
            for: "magicDefenseEquipmentFlatMultiplier"
        )
        let defenseEquipmentMultiplier = skillAdjustments.specialRuleProduct(
            for: "defenseEquipmentBattleStatFlatMultiplier"
        )
        let categorizedBattleStats = equipmentBattleStatsByCategory.values.reduce(
            initialBattleStats()
        ) { partialResult, battleStats in
            addBattleStats(partialResult, battleStats)
        }
        let uncategorizedBattleStats = subtractBattleStats(equipmentBattleStats, categorizedBattleStats)

        let subtotals = equipmentBattleStatsByCategory.reduce(
            (nonDefense: uncategorizedBattleStats, defense: initialBattleStats())
        ) { partialResult, entry in
            let scaledCategoryBattleStats = scaledBattleStats(
                entry.value,
                equipmentMultiplier: equipmentBattleStatFlatMultiplier(
                    for: entry.key,
                    skillAdjustments: skillAdjustments
                ),
                magicDefenseMultiplier: 1.0
            )
            if isDefenseEquipmentCategory(entry.key) {
                return (
                    nonDefense: partialResult.nonDefense,
                    defense: addBattleStats(partialResult.defense, scaledCategoryBattleStats)
                )
            }
            return (
                nonDefense: addBattleStats(partialResult.nonDefense, scaledCategoryBattleStats),
                defense: partialResult.defense
            )
        }

        let adjustedDefenseBattleStats = scaledBattleStats(
            subtotals.defense,
            equipmentMultiplier: defenseEquipmentMultiplier,
            magicDefenseMultiplier: 1.0
        )
        let totalBattleStats = addBattleStats(subtotals.nonDefense, adjustedDefenseBattleStats)
        return scaledBattleStats(
            totalBattleStats,
            equipmentMultiplier: 1.0,
            magicDefenseMultiplier: magicDefenseMultiplier
        )
    }

    private static func normalizedEquipmentBattleStatsByCategory(
        explicitCategoryBattleStats: [ItemCategory: CharacterBattleStats],
        legacyArmorBattleStats: CharacterBattleStats
    ) -> [ItemCategory: CharacterBattleStats] {
        if explicitCategoryBattleStats.isEmpty, legacyArmorBattleStats != initialBattleStats() {
            return [.armor: legacyArmorBattleStats]
        }
        return explicitCategoryBattleStats
    }

    private static func equipmentBattleStatFlatMultiplier(
        for category: ItemCategory,
        skillAdjustments: SkillAdjustments
    ) -> Double {
        let multiplier = skillAdjustments.specialRuleProduct(
            for: "\(category.rawValue)EquipmentBattleStatFlatMultiplier"
        )
        return multiplier
    }

    private static func scaledBattleStats(
        _ battleStats: CharacterBattleStats,
        equipmentMultiplier: Double,
        magicDefenseMultiplier: Double
    ) -> CharacterBattleStats {
        CharacterBattleStats(
            maxHP: Int((Double(battleStats.maxHP) * equipmentMultiplier).rounded()),
            physicalAttack: Int((Double(battleStats.physicalAttack) * equipmentMultiplier).rounded()),
            physicalDefense: Int((Double(battleStats.physicalDefense) * equipmentMultiplier).rounded()),
            magic: Int((Double(battleStats.magic) * equipmentMultiplier).rounded()),
            magicDefense: Int(
                (Double(battleStats.magicDefense) * equipmentMultiplier * magicDefenseMultiplier).rounded()
            ),
            healing: Int((Double(battleStats.healing) * equipmentMultiplier).rounded()),
            accuracy: Int((Double(battleStats.accuracy) * equipmentMultiplier).rounded()),
            evasion: Int((Double(battleStats.evasion) * equipmentMultiplier).rounded()),
            attackCount: Int((Double(battleStats.attackCount) * equipmentMultiplier).rounded()),
            criticalRate: Int((Double(battleStats.criticalRate) * equipmentMultiplier).rounded()),
            breathPower: Int((Double(battleStats.breathPower) * equipmentMultiplier).rounded())
        )
    }

    private static func initialBattleStats() -> CharacterBattleStats {
        CharacterBattleStats(
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
    }

    private static func addBattleStats(
        _ lhs: CharacterBattleStats,
        _ rhs: CharacterBattleStats
    ) -> CharacterBattleStats {
        CharacterBattleStats(
            maxHP: lhs.maxHP + rhs.maxHP,
            physicalAttack: lhs.physicalAttack + rhs.physicalAttack,
            physicalDefense: lhs.physicalDefense + rhs.physicalDefense,
            magic: lhs.magic + rhs.magic,
            magicDefense: lhs.magicDefense + rhs.magicDefense,
            healing: lhs.healing + rhs.healing,
            accuracy: lhs.accuracy + rhs.accuracy,
            evasion: lhs.evasion + rhs.evasion,
            attackCount: lhs.attackCount + rhs.attackCount,
            criticalRate: lhs.criticalRate + rhs.criticalRate,
            breathPower: lhs.breathPower + rhs.breathPower
        )
    }

    private static func subtractBattleStats(
        _ lhs: CharacterBattleStats,
        _ rhs: CharacterBattleStats
    ) -> CharacterBattleStats {
        CharacterBattleStats(
            maxHP: lhs.maxHP - rhs.maxHP,
            physicalAttack: lhs.physicalAttack - rhs.physicalAttack,
            physicalDefense: lhs.physicalDefense - rhs.physicalDefense,
            magic: lhs.magic - rhs.magic,
            magicDefense: lhs.magicDefense - rhs.magicDefense,
            healing: lhs.healing - rhs.healing,
            accuracy: lhs.accuracy - rhs.accuracy,
            evasion: lhs.evasion - rhs.evasion,
            attackCount: lhs.attackCount - rhs.attackCount,
            criticalRate: lhs.criticalRate - rhs.criticalRate,
            breathPower: lhs.breathPower - rhs.breathPower
        )
    }

    private static func isDefenseEquipmentCategory(_ category: ItemCategory) -> Bool {
        switch category {
        case .armor, .shield, .robe, .gauntlet:
            true
        default:
            false
        }
    }

    private static func activeSkillIds(
        racePassiveSkillIds: [Int],
        raceLevelSkillIds: [Int],
        previousJobPassiveSkillIds: [Int],
        currentJobPassiveSkillIds: [Int],
        currentJobLevelSkillIds: [Int],
        aptitudePassiveSkillIds: [Int],
        level: Int,
        additionalSkillIds: [Int]
    ) -> [Int] {
        let unlockedRaceLevelSkillIds = unlockedSkillIds(
            from: raceLevelSkillIds,
            level: level,
            unlockLevels: [50, 99]
        )
        let unlockedJobLevelSkillIds = unlockedSkillIds(
            from: currentJobLevelSkillIds,
            level: level,
            unlockLevels: [15, 30, 75]
        )
        return deduplicatedSkillIds(
            racePassiveSkillIds
            + unlockedRaceLevelSkillIds
            + previousJobPassiveSkillIds
            + currentJobPassiveSkillIds
            + unlockedJobLevelSkillIds
            + aptitudePassiveSkillIds
            + additionalSkillIds
        )
    }

    private static func unlockedSkillIds(
        from skillIds: [Int],
        level: Int,
        unlockLevels: [Int]
    ) -> [Int] {
        skillIds.enumerated().compactMap { index, skillId in
            guard unlockLevels.indices.contains(index), level >= unlockLevels[index] else {
                return nil
            }
            return skillId
        }
    }

    private static func deduplicatedSkillIds(_ skillIds: [Int]) -> [Int] {
        var seenSkillIds = Set<Int>()
        var deduplicatedSkillIds: [Int] = []

        // Keep first-seen ordering stable so downstream UI and battle logic resolve skills in a
        // deterministic order even when multiple sources grant the same skill.
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

        // Each effect is folded into one accumulator so mixed flat, percent, spell, and
        // interrupt modifiers can be applied in a single pass over the active skill list.
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
        equipmentFlatBonus: Int,
        skillAdjustments: SkillAdjustments
    ) -> Int {
        // Base-only multipliers apply before equipment and other skill adjustments so aptitude
        // effects only scale the intrinsic battle-stat baseline.
        let baseValue = Int(
            (
                baseInput
                * pow(Double(level), levelExponent)
                * jobCoefficient
                * statScale
            )
            .rounded()
        )
        let baseAdjusted = Double(baseValue) * skillAdjustments.baseBattleStatMultipliers[target, default: 1.0]
        let equipmentAdjusted = baseAdjusted + Double(equipmentFlatBonus)
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

    private static func spellSpecificBattleDerivedValues(
        target: String,
        skillAdjustments: SkillAdjustments
    ) -> [Int: Double] {
        let pctAdds = skillAdjustments.spellSpecificBattleDerivedPctAdds[target, default: [:]]
        let multipliers = skillAdjustments.spellSpecificBattleDerivedMultipliers[target, default: [:]]
        let spellIDs = Set(pctAdds.keys).union(multipliers.keys)

        // Spell-specific modifiers are stored separately from generic derived values so only the
        // listed spells inherit the adjustment while the base multiplier remains unchanged.
        return spellIDs.reduce(into: [:]) { partialResult, spellID in
            let rawValue = (1.0 + pctAdds[spellID, default: 0.0])
                * multipliers[spellID, default: 1.0]
            partialResult[spellID] = max(rawValue, 0.0)
        }
    }

    private static func multiplierValues(
        pctAdds: [String: Double],
        multipliers: [String: Double]
    ) -> [String: Double] {
        let targets = Set(pctAdds.keys).union(multipliers.keys)
        return targets.reduce(into: [:]) { partialResult, target in
            let rawValue = (1.0 + pctAdds[target, default: 0.0]) * multipliers[target, default: 1.0]
            partialResult[target] = max(rawValue, 0.0)
        }
    }

    static func ailmentStatusID(for key: String) -> Int? {
        switch key {
        case "sleep":
            1
        case "curse":
            2
        case "paralysis":
            3
        case "petrify":
            4
        default:
            nil
        }
    }

    private static func average(_ lhs: Int, _ rhs: Int) -> Double {
        Double(lhs + rhs) / 2.0
    }
}

nonisolated private struct SkillAdjustments {
    var baseBattleStatMultipliers: [String: Double] = [:]
    var battleStatFlatAdds: [String: Double] = [:]
    var battleStatPctAdds: [String: Double] = [:]
    var battleDerivedPctAdds: [String: Double] = [:]
    var battleDerivedMultipliers: [String: Double] = [:]
    var spellSpecificBattleDerivedPctAdds: [String: [Int: Double]] = [:]
    var spellSpecificBattleDerivedMultipliers: [String: [Int: Double]] = [:]
    var rewardPctAdds: [String: Double] = [:]
    var rewardMultipliers: [String: Double] = [:]
    var partyModifierPctAdds: [String: Double] = [:]
    var partyModifierMultipliers: [String: Double] = [:]
    var onHitAilmentChanceByStatusID: [Int: Double] = [:]
    var contactAilmentChanceByStatusID: [Int: Double] = [:]
    var titleRollCountModifier = 0
    var equipmentCapacityModifier = 0
    var normalDropJewelizeChance = 0.0
    var multiHitFalloffModifier = 0.5
    var hitRateFloor = 0.10
    var defenseRuleValuesByTarget: [String: [Double]] = [:]
    var recoveryRuleValuesByTarget: [String: [Double]] = [:]
    var actionRuleValuesByTarget: [String: [Double]] = [:]
    var reviveRuleValuesByTarget: [String: [Double]] = [:]
    var combatRuleValuesByTarget: [String: [Double]] = [:]
    var rewardRuleValuesByTarget: [String: [Double]] = [:]
    var specialRuleValuesByTarget: [String: [Double]] = [:]
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

            if !effect.spellIds.isEmpty {
                // Some effects only modify a whitelisted spell set, so they bypass the generic
                // derived-value buckets and accumulate into per-spell tables instead.
                for spellID in effect.spellIds {
                    switch operation {
                    case "pctAdd":
                        spellSpecificBattleDerivedPctAdds[target, default: [:]][spellID, default: 0.0] += value
                    case "mul":
                        spellSpecificBattleDerivedMultipliers[target, default: [:]][spellID, default: 1.0] *= value
                    default:
                        return
                    }
                }
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
        case .baseBattleStatMultiplier:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }

            switch effect.operation {
            case nil, "mul":
                baseBattleStatMultipliers[target, default: 1.0] *= value
            case "pctAdd":
                baseBattleStatMultipliers[target, default: 1.0] *= 1.0 + value
            default:
                return
            }
        case .rewardMultiplier:
            guard let target = effect.target,
                  let operation = effect.operation,
                  let value = effect.value else {
                return
            }

            switch operation {
            case "pctAdd":
                rewardPctAdds[target, default: 0.0] += value
            case "mul":
                rewardMultipliers[target, default: 1.0] *= value
            default:
                return
            }
        case .partyModifier:
            guard let target = effect.target,
                  let operation = effect.operation,
                  let value = effect.value else {
                return
            }

            switch operation {
            case "pctAdd":
                partyModifierPctAdds[target, default: 0.0] += value
            case "mul":
                partyModifierMultipliers[target, default: 1.0] *= value
            default:
                return
            }
        case .equipmentCapacityModifier:
            guard let value = effect.value else {
                return
            }
            equipmentCapacityModifier += Int(value.rounded())
        case .titleRollCountModifier:
            guard let value = effect.value else {
                return
            }
            titleRollCountModifier += Int(value.rounded())
        case .normalDropJewelize:
            guard let value = effect.value else {
                return
            }
            normalDropJewelizeChance = min(normalDropJewelizeChance + value, 1.0)
        case .onHitAilmentGrant:
            guard let target = effect.target,
                  let value = effect.value,
                  let statusID = CharacterDerivedStatsCalculator.ailmentStatusID(for: target) else {
                return
            }
            onHitAilmentChanceByStatusID[statusID, default: 0.0] = min(
                onHitAilmentChanceByStatusID[statusID, default: 0.0] + value,
                1.0
            )
        case .contactAilmentGrant:
            guard let target = effect.target,
                  let value = effect.value,
                  let statusID = CharacterDerivedStatsCalculator.ailmentStatusID(for: target) else {
                return
            }
            contactAilmentChanceByStatusID[statusID, default: 0.0] = min(
                contactAilmentChanceByStatusID[statusID, default: 0.0] + value,
                1.0
            )
        case .multiHitFalloffModifier:
            guard let value = effect.value else {
                return
            }
            multiHitFalloffModifier = min(multiHitFalloffModifier, value)
        case .hitRateFloorModifier:
            guard let value = effect.value else {
                return
            }
            hitRateFloor = max(hitRateFloor, value)
        case .defenseRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            defenseRuleValuesByTarget[target, default: []].append(value)
        case .recoveryRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            recoveryRuleValuesByTarget[target, default: []].append(value)
        case .actionRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            actionRuleValuesByTarget[target, default: []].append(value)
        case .reviveRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            reviveRuleValuesByTarget[target, default: []].append(value)
        case .combatRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            combatRuleValuesByTarget[target, default: []].append(value)
        case .rewardRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            rewardRuleValuesByTarget[target, default: []].append(value)
        case .specialRule:
            guard let target = effect.target,
                  let value = effect.value else {
                return
            }
            specialRuleValuesByTarget[target, default: []].append(value)
        }
    }

    func specialRuleValues(for target: String) -> [Double] {
        specialRuleValuesByTarget[target] ?? []
    }

    func specialRuleProduct(for target: String) -> Double {
        specialRuleValues(for: target).reduce(1.0, *)
    }
}
