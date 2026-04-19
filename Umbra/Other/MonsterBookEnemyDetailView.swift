// Presents read-only enemy details using a character-detail style layout.
// The screen resolves enemy stats at a selectable level and links related master-data entities so
// monster-book browsing can answer most questions without leaving the detail flow.

import SwiftUI

struct MonsterBookEnemyDetailView: View {
    let appearance: MonsterBookEnemyAppearance
    let masterData: MasterData

    @State private var selectedLevel: Int
    @State private var presentedSheet: MonsterEnemyDetailSheet?

    private let resolver: MasterDataDetailContentResolver
    private let jobsByID: [Int: MasterData.Job]
    private let itemsByID: [Int: MasterData.Item]
    private let skillsByID: [Int: MasterData.Skill]
    private let spellsByID: [Int: MasterData.Spell]

    init(
        appearance: MonsterBookEnemyAppearance,
        masterData: MasterData
    ) {
        self.appearance = appearance
        self.masterData = masterData
        _selectedLevel = State(initialValue: appearance.maximumLevel)
        resolver = MasterDataDetailContentResolver(masterData: masterData)
        jobsByID = Dictionary(uniqueKeysWithValues: masterData.jobs.map { ($0.id, $0) })
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        spellsByID = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let enemy {
                List {
                    Section {
                        MonsterEnemyHeaderView(
                            enemy: enemy,
                            jobName: jobsByID[enemy.jobId]?.name ?? "不明",
                            selectedLevel: selectedLevel,
                            levelText: appearance.levelText,
                            labyrinthName: appearance.labyrinthName
                        )
                    }

                    MonsterEnemyBasicInfoSectionView(
                        enemy: enemy,
                        appearance: appearance,
                        job: jobsByID[enemy.jobId],
                        selectedLevel: $selectedLevel,
                        onShowJobDetail: {
                            if let job = jobsByID[enemy.jobId] {
                                presentedSheet = .job(job)
                            }
                        }
                    )

                    if let status {
                        MonsterEnemyStatusSectionsView(
                            status: status,
                            skillsByID: skillsByID,
                            spellsByID: spellsByID
                        )
                    } else {
                        Section("能力値") {
                            Text("ステータスを計算できません。")
                                .foregroundStyle(.red)
                        }
                    }

                    MonsterEnemyActionSectionView(actionRates: enemy.actionRates)

                    Section("レアドロップ") {
                        if enemy.rareDropItemIds.isEmpty {
                            Text("なし")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(enemy.rareDropItemIds, id: \.self) { itemID in
                                if let item = itemsByID[itemID] {
                                    HStack(spacing: 8) {
                                        Text(item.name)

                                        Spacer(minLength: 12)

                                        Button {
                                            presentedSheet = .item(.baseItem(itemId: item.id))
                                        } label: {
                                            Image(systemName: "info.circle")
                                                .foregroundStyle(.tint)
                                                .frame(width: 28, height: 28)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(item.name)の詳細")
                                    }
                                } else {
                                    Text("不明なアイテム")
                                }
                            }
                        }
                    }

                    MasterDataSkillSectionView(
                        title: "所持スキル",
                        skillIDs: enemy.skillIds,
                        resolver: resolver
                    )
                }
                .listStyle(.insetGrouped)
                .navigationTitle("敵詳細")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $presentedSheet) { sheet in
                    NavigationStack {
                        sheetDestination(for: sheet)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") {
                                    presentedSheet = nil
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "敵が見つかりません",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private var enemy: MasterData.Enemy? {
        masterData.enemies.first(where: { $0.id == appearance.enemyId })
    }

    private var status: CharacterStatus? {
        guard let enemy else {
            return nil
        }

        // Enemy status is derived live from the selected level so the same detail screen can inspect
        // the full appearance range without precomputing every level.
        return CharacterDerivedStatsCalculator.status(
            for: enemy,
            level: selectedLevel,
            masterData: masterData
        )
    }

    @ViewBuilder
    private func sheetDestination(for sheet: MonsterEnemyDetailSheet) -> some View {
        switch sheet {
        case .job(let job):
            JobDetailView(job: job, masterData: masterData)
        case .item(let itemID):
            // Reuse the same item detail sheet shown elsewhere so enemy drops and inventory items are
            // described consistently.
            ItemDetailView(itemID: itemID, masterData: masterData)
        }
    }
}

private enum MonsterEnemyDetailSheet: Identifiable {
    case job(MasterData.Job)
    case item(CompositeItemID)

    var id: String {
        switch self {
        case .job(let job):
            "job-\(job.id)"
        case .item(let itemID):
            "item-\(itemID.stableKey)"
        }
    }
}

private struct MonsterEnemyHeaderView: View {
    let enemy: MasterData.Enemy
    let jobName: String
    let selectedLevel: Int
    let levelText: String
    let labyrinthName: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            MonsterEnemyThumbnailView(
                imageAssetName: enemy.imageAssetName,
                fallbackSystemName: enemy.enemyRace.symbolName,
                size: 96,
                cornerRadius: 16
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(enemy.name)
                    .font(.title3.weight(.semibold))

                Text("\(enemy.enemyRace.displayName) / \(jobName)")
                Text("表示レベル Lv\(selectedLevel)  出現帯 \(levelText)")
                Text("出現迷宮 \(labyrinthName)")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct MonsterEnemyBasicInfoSectionView: View {
    let enemy: MasterData.Enemy
    let appearance: MonsterBookEnemyAppearance
    let job: MasterData.Job?
    @Binding var selectedLevel: Int
    let onShowJobDetail: () -> Void

    var body: some View {
        Section("基本情報") {
            LabeledContent("種別", value: enemy.enemyRace.displayName)

            LabeledContent("職業") {
                HStack(spacing: 8) {
                    Text(job?.name ?? "不明")

                    if job != nil {
                        Button(action: onShowJobDetail) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(job?.name ?? "職業")の詳細")
                    }
                }
            }

            if appearance.minimumLevel == appearance.maximumLevel {
                LabeledContent("レベル", value: "Lv\(appearance.minimumLevel)")
            } else {
                Picker("表示レベル", selection: $selectedLevel) {
                    ForEach(appearance.selectableLevels, id: \.self) { level in
                        Text("Lv\(level)").tag(level)
                    }
                }
            }

            LabeledContent("出現階層", value: appearance.floorText)
            LabeledContent("獲得金額基準", value: "\(enemy.goldBaseValue)")
            LabeledContent("経験値基準", value: "\(enemy.experienceBaseValue)")
        }
    }
}

private struct MonsterEnemyStatusSectionsView: View {
    let status: CharacterStatus
    let skillsByID: [Int: MasterData.Skill]
    let spellsByID: [Int: MasterData.Spell]

    var body: some View {
        Section("基本能力値") {
            ForEach(baseStatRows, id: \.title) { row in
                MonsterEnemyStatRowView(title: row.title, value: row.value)
            }
        }

        Section("戦闘能力値") {
            ForEach(battleStatRows, id: \.title) { row in
                MonsterEnemyStatRowView(title: row.title, value: row.value)
            }
        }

        Section("戦闘中補正") {
            ForEach(derivedStatRows, id: \.title) { row in
                MonsterEnemyStatRowView(title: row.title, value: row.value)
            }
        }

        Section("使用可能魔法") {
            if status.spellIds.isEmpty {
                Text("なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.spellIds.sorted(), id: \.self) { spellID in
                    Text(spellsByID[spellID]?.name ?? "不明な魔法")
                }
            }
        }

        Section("実戦スキル") {
            if status.skillIds.isEmpty {
                Text("なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.skillIds.sorted(), id: \.self) { skillID in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skillsByID[skillID]?.name ?? "不明なスキル")
                        if let description = skillsByID[skillID]?.description,
                           !description.isEmpty {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var baseStatRows: [(title: String, value: String)] {
        [
            ("体力", "\(status.baseStats.vitality)"),
            ("腕力", "\(status.baseStats.strength)"),
            ("精神", "\(status.baseStats.mind)"),
            ("知略", "\(status.baseStats.intelligence)"),
            ("俊敏", "\(status.baseStats.agility)"),
            ("運", "\(status.baseStats.luck)")
        ]
    }

    private var battleStatRows: [(title: String, value: String)] {
        [
            ("最大HP", "\(status.battleStats.maxHP)"),
            ("物理攻撃", "\(status.battleStats.physicalAttack)"),
            ("物理防御", "\(status.battleStats.physicalDefense)"),
            ("魔法攻撃", "\(status.battleStats.magic)"),
            ("魔法防御", "\(status.battleStats.magicDefense)"),
            ("回復", "\(status.battleStats.healing)"),
            ("命中", "\(status.battleStats.accuracy)"),
            ("回避", "\(status.battleStats.evasion)"),
            ("攻撃回数", "\(status.battleStats.attackCount)"),
            ("必殺率", "\(status.battleStats.criticalRate)"),
            ("ブレス威力", "\(status.battleStats.breathPower)")
        ]
    }

    private var derivedStatRows: [(title: String, value: String)] {
        [
            ("物理威力倍率", percentageText(status.battleDerivedStats.physicalDamageMultiplier)),
            ("攻撃魔法威力倍率", percentageText(status.battleDerivedStats.attackMagicMultiplier)),
            ("個別魔法威力倍率", percentageText(status.battleDerivedStats.spellDamageMultiplier)),
            ("必殺時威力倍率", percentageText(status.battleDerivedStats.criticalDamageMultiplier)),
            ("近接威力倍率", percentageText(status.battleDerivedStats.meleeDamageMultiplier)),
            ("遠距離威力倍率", percentageText(status.battleDerivedStats.rangedDamageMultiplier)),
            ("行動速度倍率", percentageText(status.battleDerivedStats.actionSpeedMultiplier)),
            ("物理被ダメージ倍率", percentageText(status.battleDerivedStats.physicalResistanceMultiplier)),
            ("魔法被ダメージ倍率", percentageText(status.battleDerivedStats.magicResistanceMultiplier)),
            ("ブレス被ダメージ倍率", percentageText(status.battleDerivedStats.breathResistanceMultiplier))
        ]
    }

    private func percentageText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct MonsterEnemyActionSectionView: View {
    let actionRates: MasterData.ActionRates

    var body: some View {
        Section("行動率") {
            MonsterEnemyStatRowView(title: "通常攻撃", value: "\(actionRates.attack)%")
            MonsterEnemyStatRowView(title: "攻撃魔法", value: "\(actionRates.attackSpell)%")
            MonsterEnemyStatRowView(title: "回復魔法", value: "\(actionRates.recoverySpell)%")
            MonsterEnemyStatRowView(title: "ブレス", value: "\(actionRates.breath)%")
        }
    }
}

private struct MonsterEnemyStatRowView: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}

private extension EnemyRace {
    var displayName: String {
        switch self {
        case .dragon:
            "ドラゴン"
        case .monster:
            "モンスター"
        case .zombie:
            "アンデッド"
        case .godfiend:
            "神魔"
        }
    }

    var symbolName: String {
        switch self {
        case .dragon:
            "flame.fill"
        case .monster:
            "shield.lefthalf.filled"
        case .zombie:
            "bolt.horizontal.circle.fill"
        case .godfiend:
            "sparkles"
        }
    }
}
