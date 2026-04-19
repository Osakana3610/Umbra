// Defines the persisted guild character record and the default auto-battle settings attached to it.
// This model is the canonical save representation for a hired character, so it keeps only durable
// values and derives transient combat state elsewhere from master data and equipment.

import Foundation

nonisolated struct CharacterRecord: Identifiable, Equatable, Sendable {
    let characterId: Int
    var name: String
    let raceId: Int
    var previousJobId: Int
    var currentJobId: Int
    let aptitudeId: Int
    let portraitGender: PortraitGender
    var portraitAssetID: String
    var experience: Int
    var level: Int
    var currentHP: Int
    var equippedItemStacks: [CompositeItemStack] = []
    var autoBattleSettings: CharacterAutoBattleSettings

    var id: Int { characterId }

    var orderedEquippedItemStacks: [CompositeItemStack] {
        // Persisted stack order is not meaningful, so views and mutation code read a deterministic
        // ordering when they need stable presentation or comparison.
        equippedItemStacks.sorted { $0.itemID.isOrdered(before: $1.itemID) }
    }

    var baseMaximumEquippedItemCount: Int {
        // Equip capacity scales with level in rounded 20-level steps on top of the base 3 slots.
        3 + Int((Double(level) / 20).rounded())
    }

    func maximumEquippedItemCount(masterData: MasterData) -> Int {
        // Equip capacity is a base progression rule plus any derived equipment-capacity modifiers.
        let modifier = CharacterDerivedStatsCalculator
            .status(for: self, masterData: masterData)?
            .equipmentCapacityModifier ?? 0
        return max(baseMaximumEquippedItemCount + modifier, 0)
    }

    var equippedItemCount: Int {
        equippedItemStacks.reduce(into: 0) { partialResult, stack in
            partialResult += stack.count
        }
    }
}

nonisolated enum PortraitGender: Int, CaseIterable, Sendable {
    case male = 1
    case female = 2
    case unisex = 3

    var assetKey: String {
        switch self {
        case .male:
            "male"
        case .female:
            "female"
        case .unisex:
            "unisex"
        }
    }
}

nonisolated struct CharacterAutoBattleSettings: Equatable, Sendable {
    var rates: CharacterActionRates
    var priority: [BattleActionKind]

    static let `default` = CharacterAutoBattleSettings(
        // Defaults favor non-basic actions first so freshly hired characters still exercise spells
        // and breath attacks when they have them.
        rates: .default,
        priority: [.breath, .recoverySpell, .attackSpell, .attack]
    )
}

nonisolated struct CharacterActionRates: Equatable, Sendable {
    var breath: Int
    var attack: Int
    var recoverySpell: Int
    var attackSpell: Int

    static let `default` = CharacterActionRates(
        breath: 50,
        attack: 50,
        recoverySpell: 50,
        attackSpell: 50
    )
}
