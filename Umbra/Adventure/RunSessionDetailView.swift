// Shows one exploration session's progress, completion summary, and stored battle logs.

import SwiftUI

struct RunSessionDetailView: View {
    let partyId: Int
    let partyRunId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        partyId: Int,
        partyRunId: Int,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        partyStore: PartyStore,
        equipmentStore: EquipmentInventoryStore,
        explorationStore: ExplorationStore
    ) {
        self.partyId = partyId
        self.partyRunId = partyRunId
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.partyStore = partyStore
        self.equipmentStore = equipmentStore
        self.explorationStore = explorationStore
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        Group {
            if let run {
                List {
                    Section("探索") {
                        LabeledContent("迷宮", value: labyrinthName(for: run))
                        LabeledContent("開始", value: run.startedAt.formatted(date: .omitted, time: .shortened))

                        if let completion = run.completion {
                            LabeledContent("帰還", value: completion.completedAt.formatted(date: .omitted, time: .shortened))
                            LabeledContent("結果", value: completionText(for: completion.reason))
                        } else if let nextProgressDate = nextProgressDate(for: run) {
                            LabeledContent("進行状況", value: "\(run.completedBattleCount)戦完了")
                            LabeledContent("次の進行", value: nextProgressDate.formatted(date: .omitted, time: .standard))
                        }
                    }

                    Section("パーティHP") {
                        ForEach(Array(run.memberCharacterIds.enumerated()), id: \.offset) { offset, characterId in
                            let characterName = rosterStore.charactersById[characterId]?.name ?? "character:\(characterId)"
                            LabeledContent(characterName, value: "\(run.currentPartyHPs[safe: offset] ?? 0)")
                        }
                    }

                    if let completion = run.completion {
                        Section("報酬") {
                            LabeledContent("ゴールド", value: "\(completion.gold) G")

                            if completion.experienceRewards.isEmpty {
                                Text("経験値なし")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(completion.experienceRewards) { reward in
                                    let characterName = rosterStore.charactersById[reward.characterId]?.name ?? "character:\(reward.characterId)"
                                    LabeledContent(characterName, value: "\(reward.experience) EXP")
                                }
                            }

                            if completion.dropRewards.isEmpty {
                                Text("アイテムなし")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(completion.dropRewards) { reward in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(nameResolver.displayName(for: reward.itemID))
                                        Text("\(reward.sourceFloorNumber)F / 戦闘 \(reward.sourceBattleNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    if run.battleLogs.isEmpty {
                        Section("戦闘ログ") {
                            Text("まだ解決済みの戦闘はありません。")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(run.battleLogs) { log in
                            Section("\(log.battleRecord.floorNumber)F / 戦闘 \(log.battleRecord.battleNumber)") {
                                Text(completionText(for: log.battleRecord.result))
                                    .font(.headline)

                                ForEach(log.battleRecord.turns, id: \.turnNumber) { turn in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("ターン \(turn.turnNumber)")
                                            .font(.subheadline.weight(.semibold))

                                        if turn.actions.isEmpty {
                                            Text("行動なし")
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(Array(turn.actions.enumerated()), id: \.offset) { _, action in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(actionTitle(action, log: log))
                                                        .font(.subheadline.weight(.medium))
                                                    if !action.results.isEmpty {
                                                        Text(actionResultText(action, log: log))
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("探索記録")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    explorationStore.loadIfNeeded()
                    await keepProgressFresh()
                }
                .refreshable {
                    refreshProgress()
                }
            } else {
                ContentUnavailableView(
                    "探索記録が見つかりません",
                    systemImage: "scroll"
                )
            }
        }
    }

    private var run: RunSessionRecord? {
        explorationStore.runs.first {
            $0.partyId == partyId && $0.partyRunId == partyRunId
        }
    }

    private func keepProgressFresh() async {
        refreshProgress()

        while !Task.isCancelled {
            guard run?.completion == nil else {
                return
            }

            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                return
            }
            refreshProgress()
        }
    }

    private func refreshProgress() {
        let didApplyRewards = explorationStore.refreshProgress(at: Date(), masterData: masterData)
        guard didApplyRewards else {
            return
        }

        rosterStore.reload()
        partyStore.reload()
        try? equipmentStore.reload(masterData: masterData)
    }

    private func labyrinthName(for run: RunSessionRecord) -> String {
        masterData.labyrinths.first(where: { $0.id == run.labyrinthId })?.name ?? "不明な迷宮"
    }

    private func nextProgressDate(for run: RunSessionRecord) -> Date? {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }),
              run.completion == nil else {
            return nil
        }

        return run.startedAt.addingTimeInterval(
            Double(labyrinth.progressIntervalSeconds * (run.completedBattleCount + 1))
        )
    }

    private func completionText(for reason: RunCompletionReason) -> String {
        switch reason {
        case .cleared:
            "踏破"
        case .defeated:
            "全滅"
        case .draw:
            "引き分け"
        }
    }

    private func completionText(for result: BattleOutcome) -> String {
        switch result {
        case .victory:
            "勝利"
        case .defeat:
            "敗北"
        case .draw:
            "引き分け"
        }
    }

    private func actionTitle(
        _ action: BattleActionRecord,
        log: ExplorationBattleLog
    ) -> String {
        let actorName = log.combatants.first(where: { $0.id == action.actorId })?.name ?? action.actorId.rawValue
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

    private func actionResultText(
        _ action: BattleActionRecord,
        log: ExplorationBattleLog
    ) -> String {
        action.results.map { targetResult in
            let targetName = log.combatants.first(where: { $0.id == targetResult.targetId })?.name
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

            let flags = targetResult.flags.map(flagText(for:)).joined(separator: " / ")
            return flags.isEmpty ? suffix : "\(suffix)（\(flags)）"
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
