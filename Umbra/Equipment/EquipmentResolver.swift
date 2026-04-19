// Resolves equipped composite items into derived stat and skill inputs for runtime battle logic.

import Foundation

nonisolated enum EquipmentResolverError: LocalizedError, Equatable {
    case invalidJewelItem(Int)

    var errorDescription: String? {
        switch self {
        case .invalidJewelItem(let itemId):
            "宝石ではないアイテムが宝石枠に設定されています: \(itemId)"
        }
    }
}

nonisolated struct EquipmentResolution: Equatable, Sendable {
    let baseStats: CharacterBaseStats
    let battleStats: CharacterBattleStats
    let armorBattleStats: CharacterBattleStats
    let categoryBattleStats: [ItemCategory: CharacterBattleStats]
    let itemSkillIDs: [Int]
    let isUnarmed: Bool
    let hasMeleeWeapon: Bool
    let hasRangedWeapon: Bool
    let weaponRangeClass: ItemRangeClass
}

nonisolated struct EquipmentResolver {
    private let itemsByID: [Int: MasterData.Item]
    private let titlesByID: [Int: MasterData.Title]
    private let superRaresByID: [Int: MasterData.SuperRare]

    init(masterData: MasterData) {
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        titlesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0) })
        superRaresByID = Dictionary(uniqueKeysWithValues: masterData.superRares.map { ($0.id, $0) })
    }

    func resolve(equippedItemStacks: [CompositeItemStack]) throws -> EquipmentResolution {
        var baseStats = CharacterBaseStats(
            vitality: 0,
            strength: 0,
            mind: 0,
            intelligence: 0,
            agility: 0,
            luck: 0
        )
        var battleStats = CharacterBattleStats(
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
        var armorBattleStats = CharacterBattleStats(
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
        var categoryBattleStats: [ItemCategory: CharacterBattleStats] = [:]
        var itemSkillIDs: [Int] = []
        var seenSkillIDs = Set<Int>()
        var hasMeleeWeapon = false
        var hasRangedWeapon = false
        var totalWeaponAttack = 0

        // Equipment is normalized first so duplicate stack keys are merged before any stat or
        // skill contribution is counted.
        for stack in equippedItemStacks.normalizedCompositeItemStacks() {
            let baseContribution = try resolveContribution(
                itemId: stack.itemID.baseItemId,
                titleId: stack.itemID.baseTitleId,
                superRareId: stack.itemID.baseSuperRareId,
                includeSuperRareSkills: true
            )
            apply(
                contribution: baseContribution,
                count: stack.count,
                baseStats: &baseStats,
                battleStats: &battleStats,
                armorBattleStats: &armorBattleStats,
                categoryBattleStats: &categoryBattleStats,
                itemSkillIDs: &itemSkillIDs,
                seenSkillIDs: &seenSkillIDs,
                hasMeleeWeapon: &hasMeleeWeapon,
                hasRangedWeapon: &hasRangedWeapon,
                totalWeaponAttack: &totalWeaponAttack
            )

            if stack.itemID.jewelItemId > 0 {
                // Jewel affixes reuse the same aggregation pipeline, but they never inherit
                // super-rare granted skills from the jewel branch.
                let jewelContribution = try resolveContribution(
                    itemId: stack.itemID.jewelItemId,
                    titleId: stack.itemID.jewelTitleId,
                    superRareId: stack.itemID.jewelSuperRareId,
                    includeSuperRareSkills: false
                )
                apply(
                    contribution: jewelContribution,
                    count: stack.count,
                    statDivisor: 2,
                    baseStats: &baseStats,
                    battleStats: &battleStats,
                    armorBattleStats: &armorBattleStats,
                    categoryBattleStats: &categoryBattleStats,
                    itemSkillIDs: &itemSkillIDs,
                    seenSkillIDs: &seenSkillIDs,
                    hasMeleeWeapon: &hasMeleeWeapon,
                    hasRangedWeapon: &hasRangedWeapon,
                    totalWeaponAttack: &totalWeaponAttack
                )
            }
        }

        return EquipmentResolution(
            baseStats: baseStats,
            battleStats: battleStats,
            armorBattleStats: armorBattleStats,
            categoryBattleStats: categoryBattleStats,
            itemSkillIDs: itemSkillIDs,
            isUnarmed: totalWeaponAttack <= 0,
            hasMeleeWeapon: hasMeleeWeapon,
            hasRangedWeapon: hasRangedWeapon,
            weaponRangeClass: resolvedWeaponRangeClass(
                hasMeleeWeapon: hasMeleeWeapon,
                hasRangedWeapon: hasRangedWeapon
            )
        )
    }

    private func resolveContribution(
        itemId: Int,
        titleId: Int,
        superRareId: Int,
        includeSuperRareSkills: Bool
    ) throws -> ResolvedItemContribution {
        let item = itemsByID[itemId]!
        if !includeSuperRareSkills && item.category != .jewel {
            throw EquipmentResolverError.invalidJewelItem(itemId)
        }

        // Titles scale only battle stats, while super-rares contribute only extra skills and
        // never alter the numeric stat payload directly.
        let title = titleId > 0 ? titlesByID[titleId] : nil
        let superRare = includeSuperRareSkills && superRareId > 0 ? superRaresByID[superRareId] : nil

        return ResolvedItemContribution(
            baseStats: CharacterBaseStats(
                vitality: item.nativeBaseStats.vitality,
                strength: item.nativeBaseStats.strength,
                mind: item.nativeBaseStats.mind,
                intelligence: item.nativeBaseStats.intelligence,
                agility: item.nativeBaseStats.agility,
                luck: item.nativeBaseStats.luck
            ),
            battleStats: scaledBattleStats(item.nativeBattleStats, title: title),
            skillIDs: item.skillIds + (superRare?.skillIds ?? []),
            itemCategory: item.category,
            rangeClass: item.rangeClass
        )
    }

    private func apply(
        contribution: ResolvedItemContribution,
        count: Int,
        statDivisor: Int = 1,
        baseStats: inout CharacterBaseStats,
        battleStats: inout CharacterBattleStats,
        armorBattleStats: inout CharacterBattleStats,
        categoryBattleStats: inout [ItemCategory: CharacterBattleStats],
        itemSkillIDs: inout [Int],
        seenSkillIDs: inout Set<Int>,
        hasMeleeWeapon: inout Bool,
        hasRangedWeapon: inout Bool,
        totalWeaponAttack: inout Int
    ) {
        // Stack count multiplies the full contribution because repeated equipped entries represent
        // multiple copies of the same composite item.
        baseStats.vitality += (contribution.baseStats.vitality / statDivisor) * count
        baseStats.strength += (contribution.baseStats.strength / statDivisor) * count
        baseStats.mind += (contribution.baseStats.mind / statDivisor) * count
        baseStats.intelligence += (contribution.baseStats.intelligence / statDivisor) * count
        baseStats.agility += (contribution.baseStats.agility / statDivisor) * count
        baseStats.luck += (contribution.baseStats.luck / statDivisor) * count

        applyBattleStats(
            contribution.battleStats,
            count: count,
            statDivisor: statDivisor,
            to: &battleStats
        )

        if contribution.itemCategory == .armor {
            applyBattleStats(
                contribution.battleStats,
                count: count,
                statDivisor: statDivisor,
                to: &armorBattleStats
            )
        }

        var aggregatedCategoryBattleStats = categoryBattleStats[contribution.itemCategory]
            ?? CharacterBattleStats(
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
        applyBattleStats(
            contribution.battleStats,
            count: count,
            statDivisor: statDivisor,
            to: &aggregatedCategoryBattleStats
        )
        categoryBattleStats[contribution.itemCategory] = aggregatedCategoryBattleStats

        totalWeaponAttack += (contribution.battleStats.physicalAttack / statDivisor) * count

        // Skill IDs preserve first-seen order while still removing duplicates across item, title,
        // and super-rare sources.
        for skillID in contribution.skillIDs where seenSkillIDs.insert(skillID).inserted {
            itemSkillIDs.append(skillID)
        }

        switch contribution.rangeClass {
        case .none:
            break
        case .melee:
            hasMeleeWeapon = true
        case .ranged:
            hasRangedWeapon = true
        }
    }

    private func applyBattleStats(
        _ contribution: CharacterBattleStats,
        count: Int,
        statDivisor: Int,
        to totals: inout CharacterBattleStats
    ) {
        totals.maxHP += (contribution.maxHP / statDivisor) * count
        totals.physicalAttack += (contribution.physicalAttack / statDivisor) * count
        totals.physicalDefense += (contribution.physicalDefense / statDivisor) * count
        totals.magic += (contribution.magic / statDivisor) * count
        totals.magicDefense += (contribution.magicDefense / statDivisor) * count
        totals.healing += (contribution.healing / statDivisor) * count
        totals.accuracy += (contribution.accuracy / statDivisor) * count
        totals.evasion += (contribution.evasion / statDivisor) * count
        totals.attackCount += (contribution.attackCount / statDivisor) * count
        totals.criticalRate += (contribution.criticalRate / statDivisor) * count
        totals.breathPower += (contribution.breathPower / statDivisor) * count
    }

    private func scaledBattleStats(
        _ stats: MasterData.BattleStats,
        title: MasterData.Title?
    ) -> CharacterBattleStats {
        CharacterBattleStats(
            maxHP: scaled(stats.maxHP, title: title),
            physicalAttack: scaled(stats.physicalAttack, title: title),
            physicalDefense: scaled(stats.physicalDefense, title: title),
            magic: scaled(stats.magic, title: title),
            magicDefense: scaled(stats.magicDefense, title: title),
            healing: scaled(stats.healing, title: title),
            accuracy: scaled(stats.accuracy, title: title),
            evasion: scaled(stats.evasion, title: title),
            attackCount: scaled(stats.attackCount, title: title),
            criticalRate: scaled(stats.criticalRate, title: title),
            breathPower: scaled(stats.breathPower, title: title)
        )
    }

    private func scaled(
        _ value: Int,
        title: MasterData.Title?
    ) -> Int {
        guard let title else {
            return value
        }
        // Positive stats use the title's positive multiplier, while penalties use the negative
        // multiplier so cursed-style downsides can scale independently.
        if value > 0 {
            return Int((Double(value) * title.positiveMultiplier).rounded())
        }
        if value < 0 {
            return Int((Double(value) * title.negativeMultiplier).rounded())
        }
        return 0
    }

    private func resolvedWeaponRangeClass(
        hasMeleeWeapon: Bool,
        hasRangedWeapon: Bool
    ) -> ItemRangeClass {
        // Mixed loadouts resolve to ranged because the battle layer treats any ranged option as
        // enabling back-row ranged behavior.
        switch (hasMeleeWeapon, hasRangedWeapon) {
        case (true, true):
            .ranged
        case (false, true):
            .ranged
        case (true, false):
            .melee
        case (false, false):
            .none
        }
    }
}

nonisolated private struct ResolvedItemContribution {
    let baseStats: CharacterBaseStats
    let battleStats: CharacterBattleStats
    let skillIDs: [Int]
    let itemCategory: ItemCategory
    let rangeClass: ItemRangeClass
}
