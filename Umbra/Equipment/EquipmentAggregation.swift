// Aggregates equipped composite items into stat and skill inputs for runtime battle resolution.

import Foundation

nonisolated enum EquipmentAggregationError: LocalizedError, Equatable {
    case invalidJewelItem(Int)

    var errorDescription: String? {
        switch self {
        case .invalidJewelItem(let itemId):
            "宝石ではないアイテムが宝石枠に設定されています: \(itemId)"
        }
    }
}

nonisolated struct EquipmentAggregation: Equatable, Sendable {
    let baseStats: CharacterBaseStats
    let battleStats: CharacterBattleStats
    let itemSkillIDs: [Int]
    let isUnarmed: Bool
    let hasMeleeWeapon: Bool
    let hasRangedWeapon: Bool
    let weaponRangeClass: ItemRangeClass
}

nonisolated struct EquipmentAggregator {
    private let itemsByID: [Int: MasterData.Item]
    private let titlesByID: [Int: MasterData.Title]
    private let superRaresByID: [Int: MasterData.SuperRare]

    init(masterData: MasterData) {
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        titlesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0) })
        superRaresByID = Dictionary(uniqueKeysWithValues: masterData.superRares.map { ($0.id, $0) })
    }

    func aggregate(equippedItemStacks: [CompositeItemStack]) throws -> EquipmentAggregation {
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
        var itemSkillIDs: [Int] = []
        var seenSkillIDs = Set<Int>()
        var hasMeleeWeapon = false
        var hasRangedWeapon = false
        var totalWeaponAttack = 0

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
                itemSkillIDs: &itemSkillIDs,
                seenSkillIDs: &seenSkillIDs,
                hasMeleeWeapon: &hasMeleeWeapon,
                hasRangedWeapon: &hasRangedWeapon,
                totalWeaponAttack: &totalWeaponAttack
            )

            if stack.itemID.jewelItemId > 0 {
                let jewelContribution = try resolveContribution(
                    itemId: stack.itemID.jewelItemId,
                    titleId: stack.itemID.jewelTitleId,
                    superRareId: stack.itemID.jewelSuperRareId,
                    includeSuperRareSkills: false
                )
                apply(
                    contribution: jewelContribution,
                    count: stack.count,
                    baseStats: &baseStats,
                    battleStats: &battleStats,
                    itemSkillIDs: &itemSkillIDs,
                    seenSkillIDs: &seenSkillIDs,
                    hasMeleeWeapon: &hasMeleeWeapon,
                    hasRangedWeapon: &hasRangedWeapon,
                    totalWeaponAttack: &totalWeaponAttack
                )
            }
        }

        return EquipmentAggregation(
            baseStats: baseStats,
            battleStats: battleStats,
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
            throw EquipmentAggregationError.invalidJewelItem(itemId)
        }

        let title = titleId > 0 ? titlesByID[titleId] : nil
        let superRare = includeSuperRareSkills && superRareId > 0 ? superRaresByID[superRareId] : nil

        return ResolvedItemContribution(
            baseStats: scaledBaseStats(item.nativeBaseStats, title: title),
            battleStats: scaledBattleStats(item.nativeBattleStats, title: title),
            skillIDs: item.skillIds + (superRare?.skillIds ?? []),
            rangeClass: item.rangeClass
        )
    }

    private func apply(
        contribution: ResolvedItemContribution,
        count: Int,
        baseStats: inout CharacterBaseStats,
        battleStats: inout CharacterBattleStats,
        itemSkillIDs: inout [Int],
        seenSkillIDs: inout Set<Int>,
        hasMeleeWeapon: inout Bool,
        hasRangedWeapon: inout Bool,
        totalWeaponAttack: inout Int
    ) {
        baseStats.vitality += contribution.baseStats.vitality * count
        baseStats.strength += contribution.baseStats.strength * count
        baseStats.mind += contribution.baseStats.mind * count
        baseStats.intelligence += contribution.baseStats.intelligence * count
        baseStats.agility += contribution.baseStats.agility * count
        baseStats.luck += contribution.baseStats.luck * count

        battleStats.maxHP += contribution.battleStats.maxHP * count
        battleStats.physicalAttack += contribution.battleStats.physicalAttack * count
        battleStats.physicalDefense += contribution.battleStats.physicalDefense * count
        battleStats.magic += contribution.battleStats.magic * count
        battleStats.magicDefense += contribution.battleStats.magicDefense * count
        battleStats.healing += contribution.battleStats.healing * count
        battleStats.accuracy += contribution.battleStats.accuracy * count
        battleStats.evasion += contribution.battleStats.evasion * count
        battleStats.attackCount += contribution.battleStats.attackCount * count
        battleStats.criticalRate += contribution.battleStats.criticalRate * count
        battleStats.breathPower += contribution.battleStats.breathPower * count

        totalWeaponAttack += contribution.battleStats.physicalAttack * count

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

    private func scaledBaseStats(
        _ stats: MasterData.BaseStats,
        title: MasterData.Title?
    ) -> CharacterBaseStats {
        CharacterBaseStats(
            vitality: scaled(stats.vitality, title: title),
            strength: scaled(stats.strength, title: title),
            mind: scaled(stats.mind, title: title),
            intelligence: scaled(stats.intelligence, title: title),
            agility: scaled(stats.agility, title: title),
            luck: scaled(stats.luck, title: title)
        )
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
    let rangeClass: ItemRangeClass
}
