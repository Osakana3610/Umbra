// Publishes overlay notifications for character status changes caused by equipping items.

import Foundation
import Observation

@MainActor
@Observable
final class EquipmentStatusNotificationService {
    struct StatusChangeNotification: Identifiable, Equatable, Sendable {
        let id: UUID
        let displayText: String
    }

    private typealias BaseStatDescriptor = (label: String, keyPath: KeyPath<CharacterBaseStats, Int>)
    private typealias BattleStatDescriptor = (label: String, keyPath: KeyPath<CharacterBattleStats, Int>)
    private typealias DerivedStatDescriptor = (label: String, keyPath: KeyPath<CharacterBattleDerivedStats, Double>)

    private static let baseStatDescriptors: [BaseStatDescriptor] = [
        ("体力", \.vitality),
        ("腕力", \.strength),
        ("精神", \.mind),
        ("知略", \.intelligence),
        ("俊敏", \.agility),
        ("運", \.luck)
    ]

    private static let battleStatDescriptors: [BattleStatDescriptor] = [
        ("最大HP", \.maxHP),
        ("物理攻撃", \.physicalAttack),
        ("物理防御", \.physicalDefense),
        ("魔法攻撃", \.magic),
        ("魔法防御", \.magicDefense),
        ("回復", \.healing),
        ("命中", \.accuracy),
        ("回避", \.evasion),
        ("攻撃回数", \.attackCount),
        ("必殺率", \.criticalRate),
        ("ブレス威力", \.breathPower)
    ]

    private static let derivedStatDescriptors: [DerivedStatDescriptor] = [
        ("物理威力倍率", \.physicalDamageMultiplier),
        ("攻撃魔法威力倍率", \.attackMagicMultiplier),
        ("回復魔法威力倍率", \.healingMultiplier),
        ("個別魔法威力倍率", \.spellDamageMultiplier),
        ("必殺時威力倍率", \.criticalDamageMultiplier),
        ("近接威力倍率", \.meleeDamageMultiplier),
        ("遠距離威力倍率", \.rangedDamageMultiplier),
        ("行動速度倍率", \.actionSpeedMultiplier),
        ("物理被ダメージ倍率", \.physicalResistanceMultiplier),
        ("魔法被ダメージ倍率", \.magicResistanceMultiplier),
        ("ブレス被ダメージ倍率", \.breathResistanceMultiplier)
    ]

    private(set) var notifications: [StatusChangeNotification] = []

    func publish(
        before beforeStatus: CharacterStatus?,
        after afterStatus: CharacterStatus?
    ) {
        let differenceLines = Self.differenceLines(
            before: beforeStatus,
            after: afterStatus
        )
        guard !differenceLines.isEmpty else {
            return
        }

        notifications = differenceLines.map {
            StatusChangeNotification(
                id: UUID(),
                displayText: $0
            )
        }
    }

    func clear() {
        notifications.removeAll()
    }

    private static func differenceLines(
        before beforeStatus: CharacterStatus?,
        after afterStatus: CharacterStatus?
    ) -> [String] {
        guard let beforeStatus,
              let afterStatus else {
            return []
        }

        var lines: [String] = []

        appendIntDifferences(
            from: beforeStatus.baseStats,
            to: afterStatus.baseStats,
            descriptors: baseStatDescriptors,
            into: &lines
        )
        appendIntDifferences(
            from: beforeStatus.battleStats,
            to: afterStatus.battleStats,
            descriptors: battleStatDescriptors,
            into: &lines
        )
        appendPercentageDifferences(
            from: beforeStatus.battleDerivedStats,
            to: afterStatus.battleDerivedStats,
            descriptors: derivedStatDescriptors,
            into: &lines
        )

        return lines
    }

    private static func appendIntDifferences<Stats>(
        from beforeStats: Stats,
        to afterStats: Stats,
        descriptors: [(label: String, keyPath: KeyPath<Stats, Int>)],
        into lines: inout [String]
    ) {
        for descriptor in descriptors {
            let afterValue = afterStats[keyPath: descriptor.keyPath]
            let delta = afterStats[keyPath: descriptor.keyPath] - beforeStats[keyPath: descriptor.keyPath]
            guard delta != 0 else {
                continue
            }

            lines.append("\(descriptor.label) \(afterValue)（\(signedText(for: delta))）")
        }
    }

    private static func appendPercentageDifferences<Stats>(
        from beforeStats: Stats,
        to afterStats: Stats,
        descriptors: [(label: String, keyPath: KeyPath<Stats, Double>)],
        into lines: inout [String]
    ) {
        for descriptor in descriptors {
            let beforeValue = Int((beforeStats[keyPath: descriptor.keyPath] * 100).rounded())
            let afterValue = Int((afterStats[keyPath: descriptor.keyPath] * 100).rounded())
            let delta = afterValue - beforeValue
            guard delta != 0 else {
                continue
            }

            lines.append("\(descriptor.label) \(afterValue)%（\(signedText(for: delta))%）")
        }
    }

    private static func signedText(for value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
