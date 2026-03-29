// Presents the adventure tab's party cards, sortie actions, and exploration summaries.

import SwiftUI

struct AdventureHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    var body: some View {
        List {
            if rosterStore.playerState != nil {
                ForEach(partyStore.parties) { party in
                    let status = explorationStore.status(for: party.partyId)
                    let presentation = AdventurePartyPresentation(
                        party: party,
                        status: status,
                        charactersById: rosterStore.charactersById,
                        masterData: masterData,
                        canStartRun: canStartRun(for: party)
                    )

                    Section {
                        AdventurePartyHeaderRow(
                            party: party,
                            presentation: presentation,
                            onStartRun: {
                                startRun(for: party)
                            }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))

                        NavigationLink {
                            PartyDetailView(
                                partyId: party.partyId,
                                masterData: masterData,
                                rosterStore: rosterStore,
                                partyStore: partyStore,
                                equipmentStore: equipmentStore,
                                explorationStore: explorationStore
                            )
                        } label: {
                            PartyMembersView(
                                memberCharacterIds: party.memberCharacterIds,
                                charactersById: rosterStore.charactersById,
                                displayedHPs: status.activeRun?.currentPartyHPs
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(party.name)のメンバーを見る")
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))

                        if let run = status.activeRun ?? status.latestCompletedRun {
                            NavigationLink {
                                RunSessionDetailView(
                                    partyId: run.partyId,
                                    partyRunId: run.partyRunId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    equipmentStore: equipmentStore,
                                    explorationStore: explorationStore
                                )
                            } label: {
                                AdventurePartyLogRow(presentation: presentation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(party.name)の探索記録を見る")
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        } else {
                            AdventurePartyLogRow(presentation: presentation)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    }
                }

                Section {
                    Button {
                        partyStore.unlockParty()
                        rosterStore.reload()
                    } label: {
                        Text("パーティ枠を追加")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(canUnlockParty ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUnlockParty)
                } footer: {
                    Text("1Gで新しいパーティ枠を追加できます。 \(partyStore.parties.count)/\(PartyRecord.maxPartyCount)")
                }

                if let error = explorationStore.lastOperationError ?? partyStore.lastOperationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("冒険")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("一括出撃") {
                    startAllRuns()
                }
                .disabled(bulkStartableRuns.isEmpty || explorationStore.isMutating)
            }
        }
        .task {
            await explorationStore.loadIfNeeded()
        }
        .task(id: nextProgressDate) {
            await waitUntilNextProgress()
        }
        .refreshable {
            await refreshProgress()
        }
    }

    private var bulkStartableRuns: [ConfiguredRunStart] {
        partyStore.parties.compactMap { party in
            guard canStartRun(for: party),
                  let labyrinthId = configuredLabyrinthId(for: party) else {
                return nil
            }

            return ConfiguredRunStart(partyId: party.partyId, labyrinthId: labyrinthId)
        }
    }

    private var canUnlockParty: Bool {
        guard let playerState = rosterStore.playerState else {
            return false
        }

        return !partyStore.isMutating
            && partyStore.parties.count < PartyRecord.maxPartyCount
            && playerState.gold >= PartyRecord.unlockCost
    }

    private var nextProgressDate: Date? {
        explorationStore.runs
            .compactMap(nextProgressDate(for:))
            .min()
    }

    private func configuredLabyrinthId(for party: PartyRecord) -> Int? {
        guard let selectedLabyrinthId = party.selectedLabyrinthId,
              masterData.labyrinths.contains(where: { $0.id == selectedLabyrinthId }) else {
            return nil
        }

        return selectedLabyrinthId
    }

    private func canStartRun(for party: PartyRecord) -> Bool {
        guard configuredLabyrinthId(for: party) != nil,
              !explorationStore.hasActiveRun(for: party.partyId),
              !party.memberCharacterIds.isEmpty else {
            return false
        }

        return party.memberCharacterIds.allSatisfy { characterId in
            (rosterStore.charactersById[characterId]?.currentHP ?? 0) > 0
        }
    }

    private func waitUntilNextProgress() async {
        guard let nextProgressDate else {
            return
        }

        let delay = max(nextProgressDate.timeIntervalSinceNow, 0)
        if delay > 0 {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }

        guard Task.isCancelled == false else {
            return
        }

        await refreshProgress()
    }

    private func refreshProgress() async {
        let refreshResult = await explorationStore.refreshProgress(at: Date(), masterData: masterData)
        guard refreshResult.didApplyRewards else {
            return
        }

        equipmentStore.applyInventoryGains(
            refreshResult.appliedInventoryCounts,
            masterData: masterData
        )
        rosterStore.reload()
        partyStore.reload()
    }

    private func startRun(for party: PartyRecord) {
        guard let labyrinthId = configuredLabyrinthId(for: party) else {
            return
        }

        Task {
            await explorationStore.startRun(
                partyId: party.partyId,
                labyrinthId: labyrinthId,
                startedAt: Date(),
                masterData: masterData
            )
        }
    }

    private func startAllRuns() {
        Task {
            await explorationStore.startConfiguredRuns(
                bulkStartableRuns,
                startedAt: Date(),
                masterData: masterData
            )
        }
    }

    private func nextProgressDate(for run: RunSessionRecord) -> Date? {
        guard run.completion == nil,
              let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }) else {
            return nil
        }

        return run.startedAt.addingTimeInterval(
            Double(labyrinth.progressIntervalSeconds * (run.completedBattleCount + 1))
        )
    }
}

private struct AdventurePartyHeaderRow: View {
    let party: PartyRecord
    let presentation: AdventurePartyPresentation
    let onStartRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        metricText("平均Lv", value: presentation.averageLevelText)
                        metricText("生存", value: presentation.aliveMemberText)
                        metricText("総HP", value: presentation.totalHPText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 12) {
                            metricText("平均Lv", value: presentation.averageLevelText)
                            metricText("生存", value: presentation.aliveMemberText)
                        }

                        metricText("総HP", value: presentation.totalHPText)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(presentation.actionTitle, action: onStartRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation.actionDisabled)
            }

            Text(party.name)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func metricText(_ label: String, value: String) -> some View {
        Text("\(label) \(value)")
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct AdventurePartyLogRow: View {
    let presentation: AdventurePartyPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let logHeaderText = presentation.logHeaderText {
                Text(logHeaderText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.logText)
                .font(.body)
                .foregroundStyle(presentation.logPrimaryStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AdventurePartyPresentation {
    let logHeaderText: String?
    let logText: String
    let actionTitle: String
    let actionDisabled: Bool
    let logPrimaryStyle: HierarchicalShapeStyle
    let averageLevelText: String
    let aliveMemberText: String
    let totalHPText: String

    init(
        party: PartyRecord,
        status: ExplorationPartyStatus,
        charactersById: [Int: CharacterRecord],
        masterData: MasterData,
        canStartRun: Bool
    ) {
        let members = party.memberCharacterIds.compactMap { charactersById[$0] }
        let displayedCurrentHPs: [Int]
        if let runHPs = status.activeRun?.currentPartyHPs, runHPs.count == members.count {
            displayedCurrentHPs = runHPs
        } else {
            displayedCurrentHPs = members.map(\.currentHP)
        }

        if members.isEmpty {
            averageLevelText = "--"
        } else {
            let averageLevel = Double(members.reduce(0) { $0 + $1.level }) / Double(members.count)
            averageLevelText = averageLevel.formatted(.number.precision(.fractionLength(1)))
        }

        aliveMemberText = "\(displayedCurrentHPs.filter { $0 > 0 }.count)/\(party.memberCharacterIds.count)"
        totalHPText = displayedCurrentHPs.reduce(0, +).formatted()

        if let activeRun = status.activeRun {
            let labyrinthName = masterData.labyrinths.first(where: { $0.id == activeRun.labyrinthId })?.name ?? "不明な迷宮"
            let latestBattleText = activeRun.latestBattleOutcome.map(Self.battleText(for:)) ?? "探索開始"
            logHeaderText = Self.estimatedReturnText(for: activeRun, masterData: masterData)
            logText = "\(labyrinthName)：\(latestBattleText)"
            actionTitle = "探索中"
            actionDisabled = true
            logPrimaryStyle = .primary
            return
        }

        if let latestCompletedRun = status.latestCompletedRun,
           let completion = latestCompletedRun.completion {
            let labyrinthName = masterData.labyrinths.first(where: { $0.id == latestCompletedRun.labyrinthId })?.name ?? "不明な迷宮"
            let returnedAt = completion.completedAt.formatted(
                Date.FormatStyle(date: .numeric, time: .standard)
                    .locale(Locale(identifier: "ja_JP"))
            )
            logHeaderText = "帰還時刻 \(returnedAt)"
            logText = "\(labyrinthName)：\(Self.completionText(for: completion.reason)) / \(completion.gold) G / アイテム \(completion.dropRewards.count) 件"
            actionTitle = "出撃"
            actionDisabled = !canStartRun
            logPrimaryStyle = .primary
            return
        }

        if let labyrinthId = party.selectedLabyrinthId,
           let labyrinth = masterData.labyrinths.first(where: { $0.id == labyrinthId }) {
            logHeaderText = "出撃先迷宮"
            if party.memberCharacterIds.isEmpty {
                logText = "\(labyrinth.name)：メンバーを編成すると出撃できます。"
                actionTitle = "出撃"
                actionDisabled = true
                logPrimaryStyle = .secondary
            } else if displayedCurrentHPs.contains(0) {
                logText = "\(labyrinth.name)：HPが0のメンバーを含むため出撃できません。"
                actionTitle = "出撃"
                actionDisabled = true
                logPrimaryStyle = .secondary
            } else {
                logText = "\(labyrinth.name)：探索ログはまだありません。"
                actionTitle = "出撃"
                actionDisabled = !canStartRun
                logPrimaryStyle = .secondary
            }
            return
        }

        logHeaderText = nil
        logText = "出撃先の迷宮を選択してください。"
        actionTitle = "出撃"
        actionDisabled = true
        logPrimaryStyle = .secondary
    }

    private static func estimatedReturnText(
        for run: RunSessionRecord,
        masterData: MasterData
    ) -> String {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }) else {
            return "帰還予定時刻 --:--:--"
        }

        let totalBattleCount = labyrinth.floors
            .filter { $0.floorNumber <= run.targetFloorNumber }
            .reduce(into: 0) { partialResult, floor in
                partialResult += floor.battleCount
            }
        guard totalBattleCount > 0 else {
            return "帰還予定時刻 --:--:--"
        }

        let returnAt = run.startedAt.addingTimeInterval(
            Double(totalBattleCount * labyrinth.progressIntervalSeconds)
        )
        return "帰還予定時刻 \(returnAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "ja_JP"))))"
    }

    private static func battleText(for outcome: BattleOutcome) -> String {
        switch outcome {
        case .victory:
            "勝利"
        case .draw:
            "引き分け"
        case .defeat:
            "敗北"
        }
    }

    private static func completionText(for reason: RunCompletionReason) -> String {
        switch reason {
        case .cleared:
            "踏破"
        case .defeated:
            "全滅"
        case .draw:
            "引き分け"
        }
    }
}
