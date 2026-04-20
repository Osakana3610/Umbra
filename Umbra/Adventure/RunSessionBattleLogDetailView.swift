// Renders one stored battle log with turn-start participant state and per-action HP changes.

import SwiftUI

struct RunSessionBattleLogDetailView: View {
    let indexEntry: ExplorationBattleLog.IndexEntry
    let explorationStore: ExplorationStore

    private let masterData: MasterData
    private let spellsByID: [Int: MasterData.Spell]
    @State private var log: ExplorationBattleLog?
    @State private var hasLoaded = false

    init(
        indexEntry: ExplorationBattleLog.IndexEntry,
        masterData: MasterData,
        explorationStore: ExplorationStore
    ) {
        self.indexEntry = indexEntry
        self.masterData = masterData
        self.explorationStore = explorationStore
        spellsByID = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let log {
                List {
                    Section("戦闘結果") {
                        LabeledContent("結果") {
                            Text(outcomeText(for: log.battleRecord.result))
                        }

                        LabeledContent("ターン数") {
                            Text("\(log.battleRecord.turns.count)")
                                .monospacedDigit()
                        }
                    }

                    ForEach(turnSummaries) { summary in
                        RunSessionBattleTurnSectionView(summary: summary)
                    }
                }
            } else if hasLoaded {
                ContentUnavailableView(
                    "戦闘ログが見つかりません",
                    systemImage: "text.page.slash"
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .playerStatusContentInsetAware()
        .navigationTitle("\(indexEntry.floorNumber)F / 戦闘 \(indexEntry.battleNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBattleLog()
        }
    }

    private var combatantsByID: [BattleCombatantID: BattleCombatantSnapshot] {
        Dictionary(uniqueKeysWithValues: (log?.combatants ?? []).map { ($0.id, $0) })
    }

    private var turnSummaries: [RunSessionBattleTurnSummary] {
        guard let log else {
            return []
        }

        var states = Dictionary(
            uniqueKeysWithValues: log.combatants.map {
                ($0.id, RunSessionBattleParticipantState(snapshot: $0, masterData: masterData))
            }
        )
        var previousTurnStartStates = states
        var summaries: [RunSessionBattleTurnSummary] = []

        for turn in log.battleRecord.turns {
            let turnStartStates = states
            // Each turn section shows the HP at the start of that turn, while action rows mutate a
            // separate running copy to render per-result HP deltas below.
            let displayedStates = turnStartStates.mapValues { state in
                var copy = state
                copy.previousTurnStartHP = previousTurnStartStates[state.id]?.currentHP ?? state.currentHP
                return copy
            }

            let actions = turn.actions.enumerated().map { offset, action in
                makeActionPresentation(
                    id: turn.turnNumber * 1000 + offset,
                    action: action,
                    states: &states
                )
            }

            summaries.append(
                RunSessionBattleTurnSummary(
                    id: turn.turnNumber,
                    turnNumber: turn.turnNumber,
                    allies: displayedStates.values
                        .filter { $0.side == .ally }
                        .sorted { $0.order < $1.order },
                    enemies: displayedStates.values
                        .filter { $0.side == .enemy }
                        .sorted { $0.order < $1.order },
                    actions: actions
                )
            )
            previousTurnStartStates = turnStartStates
        }

        return summaries
    }

    private func loadBattleLog() async {
        log = await explorationStore.loadBattleLog(
            partyId: indexEntry.partyId,
            partyRunId: indexEntry.partyRunId,
            battleIndex: indexEntry.battleIndex
        )
        hasLoaded = true
    }

    private func makeActionPresentation(
        id: Int,
        action: BattleActionRecord,
        states: inout [BattleCombatantID: RunSessionBattleParticipantState]
    ) -> RunSessionBattleActionPresentation {
        let actor = combatantsByID[action.actorId].map { snapshot in
            RunSessionBattleParticipantState(
                snapshot: snapshot,
                masterData: masterData
            )
        }

        // Result messages are built while mutating the running HP state so later results in the
        // same turn can render against already-updated values.
        return RunSessionBattleActionPresentation(
            id: id,
            actor: actor,
            headline: actionHeadline(for: action),
            detailMessage: detailMessage(for: action, actor: actor),
            results: action.results.enumerated().map { offset, result in
                RunSessionBattleResultPresentation(
                    id: id * 100 + offset,
                    message: resultMessage(for: result),
                    tone: resultTone(for: result),
                    hpChange: applyHPChange(for: result, states: &states)
                )
            }
        )
    }

    private func detailMessage(
        for action: BattleActionRecord,
        actor: RunSessionBattleParticipantState?
    ) -> String? {
        guard action.actionKind == .defend,
              action.results.isEmpty,
              let actor else {
            return nil
        }

        return "\(actor.name)は身を守った"
    }

    private func actionHeadline(for action: BattleActionRecord) -> String {
        let suffix = action.actionFlags.contains(.critical) ? " [必殺]" : ""
        return actionName(for: action) + suffix
    }

    private func actionName(for action: BattleActionRecord) -> String {
        switch action.actionKind {
        case .breath:
            "ブレス"
        case .attack:
            "攻撃"
        case .unarmedRepeat:
            "格闘再攻撃"
        case .recoverySpell:
            spellName(for: action.actionRef, fallback: "回復魔法")
        case .attackSpell:
            spellName(for: action.actionRef, fallback: "攻撃魔法")
        case .defend:
            "防御"
        case .rescue:
            "救出"
        case .counter:
            "反撃"
        case .extraAttack:
            "再攻撃"
        case .pursuit:
            "追撃"
        }
    }

    private func spellName(for spellID: Int?, fallback: String) -> String {
        guard let spellID else {
            return fallback
        }

        return spellsByID[spellID]?.name ?? fallback
    }

    private func resultMessage(for result: BattleTargetResult) -> String {
        let targetName = combatantsByID[result.targetId]?.name ?? "\(result.targetId.rawValue)"
        let value = result.value ?? 0
        let baseText: String

        switch result.resultKind {
        case .damage:
            baseText = "\(targetName)に\(value)ダメージ"
        case .heal:
            baseText = "\(targetName)を\(value)回復"
        case .miss:
            baseText = "\(targetName)に命中せず"
        case .modifierApplied:
            if let ailmentName = ailmentName(for: result.statusId) {
                baseText = "\(targetName)を\(ailmentName)状態にした"
            } else {
                baseText = "\(targetName)へ効果を付与"
            }
        case .ailmentRemoved:
            if let ailmentName = ailmentName(for: result.statusId) {
                baseText = "\(targetName)の\(ailmentName)を回復"
            } else {
                baseText = "\(targetName)の状態異常を回復"
            }
        }

        let flags = result.flags.map(flagText(for:)).joined(separator: " / ")
        return flags.isEmpty ? baseText : "\(baseText) [\(flags)]"
    }

    private func applyHPChange(
        for result: BattleTargetResult,
        states: inout [BattleCombatantID: RunSessionBattleParticipantState]
    ) -> RunSessionBattleHPChange? {
        guard var state = states[result.targetId] else {
            return nil
        }

        let beforeHP = state.currentHP
        let value = result.value ?? 0
        let afterHP: Int

        switch result.resultKind {
        case .damage:
            afterHP = max(beforeHP - value, 0)
        case .heal:
            afterHP = min(beforeHP + value, state.maxHP)
        case .miss, .modifierApplied, .ailmentRemoved:
            return nil
        }

        // The stored logs only need HP transitions for damage and healing, so non-HP effects keep
        // the current participant state unchanged.
        state.currentHP = afterHP
        states[result.targetId] = state
        return RunSessionBattleHPChange(
            beforeHP: beforeHP,
            afterHP: afterHP,
            maxHP: state.maxHP
        )
    }

    private func resultTone(for result: BattleTargetResult) -> RunSessionBattleResultTone {
        result.resultKind == .damage ? .primary : .secondary
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

    private func ailmentName(for statusID: Int?) -> String? {
        switch statusID {
        case BattleAilment.sleep.rawValue:
            "眠り"
        case BattleAilment.curse.rawValue:
            "呪い"
        case BattleAilment.paralysis.rawValue:
            "麻痺"
        case BattleAilment.petrify.rawValue:
            "石化"
        case nil:
            nil
        case .some:
            "状態異常"
        }
    }

    private func outcomeText(for result: BattleOutcome) -> String {
        switch result {
        case .victory:
            "勝利"
        case .defeat:
            "敗北"
        case .draw:
            "引き分け"
        }
    }
}

private struct RunSessionBattleTurnSummary: Identifiable {
    let id: Int
    let turnNumber: Int
    let allies: [RunSessionBattleParticipantState]
    let enemies: [RunSessionBattleParticipantState]
    let actions: [RunSessionBattleActionPresentation]
}

private struct RunSessionBattleParticipantState: Identifiable {
    let id: BattleCombatantID
    let side: BattleSide
    let name: String
    let imageAssetName: String?
    let order: Int
    let level: Int
    let maxHP: Int
    var currentHP: Int
    var previousTurnStartHP: Int

    init(
        snapshot: BattleCombatantSnapshot,
        masterData: MasterData
    ) {
        id = snapshot.id
        side = snapshot.side
        name = snapshot.name
        imageAssetName = masterData.battleCombatantAssetName(for: snapshot.imageReference)
        order = snapshot.formationIndex
        level = snapshot.level
        maxHP = snapshot.maxHP
        currentHP = snapshot.initialHP
        previousTurnStartHP = snapshot.initialHP
    }
}

private struct RunSessionBattleActionPresentation: Identifiable {
    let id: Int
    let actor: RunSessionBattleParticipantState?
    let headline: String
    let detailMessage: String?
    let results: [RunSessionBattleResultPresentation]
}

private struct RunSessionBattleResultPresentation: Identifiable {
    let id: Int
    let message: String
    let tone: RunSessionBattleResultTone
    let hpChange: RunSessionBattleHPChange?
}

private struct RunSessionBattleHPChange {
    let beforeHP: Int
    let afterHP: Int
    let maxHP: Int
}

private enum RunSessionBattleResultTone: Equatable {
    case primary
    case secondary
}

private struct RunSessionBattleTurnSectionView: View {
    let summary: RunSessionBattleTurnSummary

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                RunSessionBattleParticipantSummaryView(
                    participants: summary.allies
                )

                if !summary.enemies.isEmpty {
                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    RunSessionBattleParticipantSummaryView(
                        participants: summary.enemies
                    )
                }
            }
            .padding(.vertical, 4)

            ForEach(summary.actions) { action in
                RunSessionBattleActionRowView(action: action)
            }
        } header: {
            Text("\(summary.turnNumber)ターン目")
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}

private struct RunSessionBattleParticipantSummaryView: View {
    let participants: [RunSessionBattleParticipantState]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if participants.isEmpty {
                Text("情報がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(participants) { participant in
                    HStack(spacing: 8) {
                        Text("\(participant.name) Lv.\(participant.level)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(minWidth: 88, alignment: .leading)

                        RunSessionBattleHPBarView(
                            currentHP: participant.currentHP,
                            previousHP: participant.previousTurnStartHP,
                            maxHP: participant.maxHP
                        )
                        .frame(maxWidth: 148)
                    }
                }
            }
        }
    }
}

private struct RunSessionBattleActionRowView: View {
    let action: RunSessionBattleActionPresentation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RunSessionBattleActorBadge(
                side: action.actor?.side ?? .ally,
                imageAssetName: action.actor?.imageAssetName
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                headerLine

                if let detailMessage = action.detailMessage {
                    Text(detailMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(action.results) { result in
                    RunSessionBattleResultLineView(result: result)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var headerLine: some View {
        ViewThatFits(in: .horizontal) {
            compactHeaderLine
            expandedHeaderLine
        }
    }

    private var compactHeaderLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            actorText
            Text(action.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var expandedHeaderLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            actorText
            Text(action.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actorText: some View {
        if let actor = action.actor {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(actor.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(highlightColor(for: actor.side))
                    }

                Text("Lv.\(actor.level)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func highlightColor(for side: BattleSide) -> Color {
        switch (side, colorScheme) {
        case (.ally, .dark):
            .teal.opacity(0.34)
        case (.ally, _):
            .teal.opacity(0.22)
        case (.enemy, .dark):
            .red.opacity(0.32)
        case (.enemy, _):
            .red.opacity(0.20)
        }
    }
}

private struct RunSessionBattleActorBadge: View {
    let side: BattleSide
    let imageAssetName: String?

    var body: some View {
        Group {
            if let imageAssetName {
                GameAssetImage(assetName: imageAssetName)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background)
                    .overlay {
                        Image(systemName: side == .ally ? "person.fill" : "pawprint.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct RunSessionBattleResultLineView: View {
    let result: RunSessionBattleResultPresentation

    var body: some View {
        Text(resultLineText)
            .font(.callout)
            .foregroundStyle(result.tone == .primary ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultLineText: String {
        guard let hpChange = result.hpChange else {
            return result.message
        }

        return "\(result.message)（\(hpChange.afterHP.formatted())/\(hpChange.maxHP.formatted())）"
    }
}

private struct RunSessionBattleHPBarView: View {
    let currentHP: Int
    let previousHP: Int
    let maxHP: Int

    @ScaledMetric(relativeTo: .caption2) private var barHeight = 14.0

    private var currentRatio: CGFloat {
        guard maxHP > 0 else { return 0 }
        return CGFloat(max(0, min(currentHP, maxHP))) / CGFloat(maxHP)
    }

    private var previousRatio: CGFloat {
        guard maxHP > 0 else { return 0 }
        return CGFloat(max(0, min(previousHP, maxHP))) / CGFloat(maxHP)
    }

    private var isDamage: Bool { currentHP < previousHP }
    private var isHeal: Bool { currentHP > previousHP }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Color(.systemGray5)

                // Damage highlights the lost segment in red, healing highlights the gained segment
                // in green, and the neutral gray bar shows the resulting HP after the change.
                if isDamage {
                    Rectangle()
                        .fill(Color(.systemRed).opacity(0.70))
                        .frame(width: width * previousRatio)

                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(width: width * currentRatio)
                } else if isHeal {
                    Rectangle()
                        .fill(Color(.systemGreen).opacity(0.70))
                        .frame(width: width * currentRatio)

                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(width: width * previousRatio)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(width: width * currentRatio)
                }

                Text("\(currentHP.formatted())/\(maxHP.formatted())")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .shadow(color: Color(.systemBackground), radius: 1, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .monospacedDigit()
            }
            .clipShape(RoundedRectangle(cornerRadius: barHeight / 2))
        }
        .frame(height: barHeight)
    }
}
