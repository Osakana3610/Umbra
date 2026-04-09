// Shows a reusable detail sheet for one composite equipment item and its stat contributions.

import SwiftUI

struct ItemDetailView: View {
    let itemID: CompositeItemID
    let masterData: MasterData

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        itemID: CompositeItemID,
        masterData: MasterData
    ) {
        self.itemID = itemID
        self.masterData = masterData
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.displayName)
                        .font(.title3.weight(.semibold))

                    Text(snapshot.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !snapshot.identityLines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(snapshot.identityLines, id: \.self) { line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("基本能力値") {
                if snapshot.baseStatLines.isEmpty {
                    Text("補正なし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.baseStatLines, id: \.label) { line in
                        HStack(spacing: 12) {
                            Text(line.label)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            Text(line.valueText)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("戦闘能力値") {
                if snapshot.battleStatLines.isEmpty {
                    Text("補正なし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.battleStatLines, id: \.label) { line in
                        HStack(spacing: 12) {
                            Text(line.label)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            Text(line.valueText)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("スキル") {
                if snapshot.skills.isEmpty {
                    Text("スキルなし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.skills, id: \.id) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.body.weight(.semibold))

                            if !skill.description.isEmpty {
                                Text(skill.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("アイテム詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var snapshot: ItemDetailSnapshot {
        ItemDetailSnapshot(
            itemID: itemID,
            masterData: masterData,
            nameResolver: nameResolver
        )
    }
}

private struct ItemDetailSnapshot {
    struct StatLine {
        let label: String
        let valueText: String
    }

    let displayName: String
    let summaryText: String
    let identityLines: [String]
    let baseStatLines: [StatLine]
    let battleStatLines: [StatLine]
    let skills: [MasterData.Skill]

    init(
        itemID: CompositeItemID,
        masterData: MasterData,
        nameResolver: EquipmentDisplayNameResolver
    ) {
        let itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        let titlesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0) })
        let superRaresByID = Dictionary(uniqueKeysWithValues: masterData.superRares.map { ($0.id, $0) })
        let skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        let aggregation = try? EquipmentAggregator(masterData: masterData).aggregate(
            equippedItemStacks: [CompositeItemStack(itemID: itemID, count: 1)]
        )

        let baseItem = itemsByID[itemID.baseItemId]
        displayName = nameResolver.displayName(for: itemID)
        summaryText = [
            baseItem?.category.displayName,
            baseItem?.rarity.displayName,
            baseItem?.rangeClass.displayName,
        ]
        .compactMap { $0 }
        .joined(separator: " / ")

        var identityLines: [String] = []
        if let superRareName = superRaresByID[itemID.baseSuperRareId]?.name, !superRareName.isEmpty {
            identityLines.append("超レア: \(superRareName)")
        }
        if itemID.jewelItemId > 0, let jewelItem = itemsByID[itemID.jewelItemId] {
            var jewelText = "宝石: \(jewelItem.name)"
            if let jewelTitleName = titlesByID[itemID.jewelTitleId]?.name, !jewelTitleName.isEmpty {
                jewelText += " / \(jewelTitleName)"
            }
            identityLines.append(jewelText)
        }
        self.identityLines = identityLines

        var baseLines: [StatLine] = []
        var battleLines: [StatLine] = []
        if let aggregation {
            Self.appendBaseStatLines(from: aggregation.baseStats, to: &baseLines)
            Self.appendBattleStatLines(from: aggregation.battleStats, to: &battleLines)
            skills = aggregation.itemSkillIDs.compactMap { skillsByID[$0] }
        } else {
            skills = []
        }
        baseStatLines = baseLines
        battleStatLines = battleLines
    }

    private static func appendBaseStatLines(
        from stats: CharacterBaseStats,
        to lines: inout [StatLine]
    ) {
        let values: [(String, Int)] = [
            ("体力", stats.vitality),
            ("腕力", stats.strength),
            ("精神", stats.mind),
            ("知略", stats.intelligence),
            ("俊敏", stats.agility),
            ("運", stats.luck),
        ]
        for (label, value) in values where value != 0 {
            lines.append(StatLine(label: label, valueText: signedText(for: value)))
        }
    }

    private static func appendBattleStatLines(
        from stats: CharacterBattleStats,
        to lines: inout [StatLine]
    ) {
        let values: [(String, Int)] = [
            ("最大HP", stats.maxHP),
            ("物理攻撃", stats.physicalAttack),
            ("物理防御", stats.physicalDefense),
            ("魔法", stats.magic),
            ("魔法防御", stats.magicDefense),
            ("回復", stats.healing),
            ("命中", stats.accuracy),
            ("回避", stats.evasion),
            ("攻撃回数", stats.attackCount),
            ("必殺率", stats.criticalRate),
            ("ブレス威力", stats.breathPower),
        ]
        for (label, value) in values where value != 0 {
            lines.append(StatLine(label: label, valueText: signedText(for: value)))
        }
    }

    private static func signedText(for value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private extension ItemRangeClass {
    var displayName: String {
        switch self {
        case .none:
            "補助"
        case .melee:
            "近距離"
        case .ranged:
            "遠距離"
        }
    }
}
