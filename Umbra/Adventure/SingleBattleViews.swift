// Presents scenario selection and renders the resolved log for a single battle preview.

import SwiftUI

struct SingleBattleSelectionView: View {
    let party: PartyRecord
    let masterData: MasterData
    let guildStore: GuildStore

    var body: some View {
        List {
            if scenarios.isEmpty {
                ContentUnavailableView(
                    "戦闘シナリオがありません",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                ForEach(scenarios) { scenario in
                    NavigationLink {
                        SingleBattleLogView(
                            party: party,
                            scenario: scenario,
                            masterData: masterData,
                            guildStore: guildStore
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scenario.name)
                                .font(.headline)
                            Text(enemySummary(for: scenario))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("単体戦闘")
    }

    private var scenarios: [SingleBattleScenario] {
        SingleBattleScenario.catalog(masterData: masterData)
    }

    private func enemySummary(for scenario: SingleBattleScenario) -> String {
        scenario.enemies.compactMap { seed in
            guard let enemy = masterData.enemies.first(where: { $0.id == seed.enemyId }) else {
                return nil
            }
            return "\(enemy.name) Lv.\(seed.level)"
        }
        .joined(separator: " / ")
    }
}

private struct SingleBattleLogView: View {
    let party: PartyRecord
    let scenario: SingleBattleScenario
    let masterData: MasterData
    let guildStore: GuildStore

    @State private var result: SingleBattleResult?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let result {
                List {
                    Section("結果") {
                        Text(resultText(for: result.result))
                            .font(.headline)

                        ForEach(result.combatants.filter { $0.side == .ally }.sorted {
                            $0.formationIndex < $1.formationIndex
                        }) { combatant in
                            LabeledContent(combatant.name, value: "\(combatant.remainingHP)/\(combatant.maxHP)")
                        }
                    }

                    ForEach(result.battleRecord.turns, id: \.turnNumber) { turn in
                        Section("ターン \(turn.turnNumber)") {
                            if turn.actions.isEmpty {
                                Text("行動なし")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(turn.actions.enumerated()), id: \.offset) { _, action in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(actionTitle(action, result: result))
                                            .font(.headline)
                                        if !action.results.isEmpty {
                                            Text(actionResultText(action, result: result))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "戦闘を開始できません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("戦闘を解決中")
            }
        }
        .navigationTitle(scenario.name)
        .task {
            await loadResultIfNeeded()
        }
    }

    private func loadResultIfNeeded() async {
        guard result == nil, errorMessage == nil else {
            return
        }

        do {
            result = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: "single-battle-\(party.partyId)-\(scenario.id)",
                    rootSeed: scenario.seed(for: party.partyId),
                    floorNumber: scenario.floorNumber,
                    battleNumber: scenario.battleNumber
                ),
                partyMembers: party.memberCharacterIds.compactMap { guildStore.charactersById[$0] },
                enemies: scenario.enemies,
                masterData: masterData
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func resultText(for result: BattleOutcome) -> String {
        switch result {
        case .victory:
            "勝利"
        case .draw:
            "引き分け"
        case .defeat:
            "敗北"
        }
    }

    private func actionTitle(_ action: BattleActionRecord, result: SingleBattleResult) -> String {
        let actorName = result.combatants.first(where: { $0.id == action.actorId })?.name ?? action.actorId.rawValue
        let actionName: String

        switch action.actionKind {
        case .breath:
            actionName = "ブレス"
        case .attack:
            actionName = "攻撃"
        case .recoverySpell:
            actionName = spellName(for: action.actionRef) ?? "回復魔法"
        case .attackSpell:
            actionName = spellName(for: action.actionRef) ?? "攻撃魔法"
        case .defend:
            actionName = "防御"
        case .rescue:
            actionName = "救出"
        case .counter:
            actionName = "反撃"
        case .extraAttack:
            actionName = "再攻撃"
        case .pursuit:
            actionName = "追撃"
        }

        if action.actionFlags.contains(.critical) {
            return "\(actorName)の\(actionName)（必殺）"
        }
        return "\(actorName)の\(actionName)"
    }

    private func actionResultText(_ action: BattleActionRecord, result: SingleBattleResult) -> String {
        action.results.map { targetResult in
            let targetName = result.combatants.first(where: { $0.id == targetResult.targetId })?.name
                ?? targetResult.targetId.rawValue
            let suffix: String

            switch targetResult.resultKind {
            case .damage:
                suffix = "\(targetName)に\(targetResult.value ?? 0)ダメージ"
            case .heal:
                suffix = "\(targetName)が\(targetResult.value ?? 0)回復"
            case .miss:
                suffix = "\(targetName)に回避された"
            case .modifierApplied:
                suffix = "\(targetName)へ効果付与"
            case .ailmentRemoved:
                suffix = "\(targetName)の状態異常回復"
            }

            let flags = targetResult.flags.map { flagText(for: $0) }.joined(separator: " / ")
            if flags.isEmpty {
                return suffix
            }
            return "\(suffix)（\(flags)）"
        }
        .joined(separator: "、")
    }

    private func spellName(for spellId: Int?) -> String? {
        guard let spellId else {
            return nil
        }
        return masterData.spells.first(where: { $0.id == spellId })?.name
    }

    private func flagText(for flag: BattleTargetResultFlag) -> String {
        switch flag {
        case .defeated:
            "戦闘不能"
        case .revived:
            "蘇生"
        case .guarded:
            "防御中"
        }
    }
}

private struct SingleBattleScenario: Identifiable, Equatable {
    let id: String
    let name: String
    let floorNumber: Int
    let battleNumber: Int
    let enemies: [BattleEnemySeed]

    static func catalog(masterData: MasterData) -> [SingleBattleScenario] {
        var scenarios: [SingleBattleScenario] = []

        for labyrinth in masterData.labyrinths {
            for floor in labyrinth.floors {
                var battleNumber = 1

                for encounter in floor.encounters {
                    scenarios.append(
                        SingleBattleScenario(
                            id: "encounter-\(labyrinth.id)-\(floor.floorNumber)-\(battleNumber)-\(encounter.enemyId)",
                            name: "\(labyrinth.name) \(floor.floorNumber)F 通常戦闘",
                            floorNumber: floor.floorNumber,
                            battleNumber: battleNumber,
                            enemies: [BattleEnemySeed(enemyId: encounter.enemyId, level: encounter.level)]
                        )
                    )
                    battleNumber += 1
                }

                if let fixedBattle = floor.fixedBattle, !fixedBattle.isEmpty {
                    scenarios.append(
                        SingleBattleScenario(
                            id: "fixed-\(labyrinth.id)-\(floor.floorNumber)-\(battleNumber)",
                            name: "\(labyrinth.name) \(floor.floorNumber)F 確定戦闘",
                            floorNumber: floor.floorNumber,
                            battleNumber: battleNumber,
                            enemies: fixedBattle.map { BattleEnemySeed(enemyId: $0.enemyId, level: $0.level) }
                        )
                    )
                }
            }
        }

        return scenarios
    }

    func seed(for partyId: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(partyId):\(id)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
