// Shows one exploration session's summary and routes battle logs to a dedicated detail view.

import SwiftUI

struct RunSessionDetailView: View {
    let partyId: Int
    let partyRunId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    private let itemsByID: [Int: MasterData.Item]
    private let nameResolver: EquipmentDisplayNameResolver
    @State private var runDetail: RunSessionRecord?
    @State private var itemFilter = ItemBrowserFilter()

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
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        Group {
            if let run {
                let dropRewardCatalog = dropRewardCatalog(for: detailedRun?.completion)

                List {
                    Section("探索結果") {
                        Text(explorationResultText(for: run))
                    }

                    if let detailedRun {
                        if displayedBattleLogs(from: detailedRun).isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "戦闘ログがありません",
                                    systemImage: "text.page.slash",
                                    description: Text("この探索ではまだ保存済みの戦闘がありません。")
                                )
                            }
                        } else {
                            Section("戦闘一覧") {
                                ForEach(displayedBattleLogs(from: detailedRun)) { log in
                                    NavigationLink {
                                        RunSessionBattleLogDetailView(
                                            log: log,
                                            masterData: masterData
                                        )
                                    } label: {
                                        BattleLogSummaryRow(
                                            titleText: "\(log.battleRecord.floorNumber)F / 戦闘 \(log.battleRecord.battleNumber)",
                                            resultText: completionText(for: log.battleRecord.result),
                                            turnCount: log.battleRecord.turns.count,
                                            footerText: defeatedPartyMemberText(for: log)
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        Section {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    if let completion = detailedRun?.completion {
                        Section("入手ゴールド") {
                            Text("\(completion.gold) G")
                                .monospacedDigit()
                        }

                        Section("獲得経験値") {
                            if completion.experienceRewards.isEmpty {
                                Text("経験値なし")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(completion.experienceRewards) { reward in
                                    let characterName = rosterStore.charactersById[reward.characterId]?.name ?? "character:\(reward.characterId)"
                                    Text("\(characterName)：\(reward.experience) EXP")
                                        .monospacedDigit()
                                }
                            }
                        }

                        Section("ドロップアイテム") {
                            let displayedDropRewards = displayedDropRewards(from: completion)

                            if completion.dropRewards.isEmpty {
                                Text("アイテムなし")
                                    .foregroundStyle(.secondary)
                            } else if displayedDropRewards.isEmpty {
                                Text("フィルター条件に一致するアイテムはありません。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(displayedDropRewards) { reward in
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
                }
                .listStyle(.insetGrouped)
                .navigationTitle("\(partyName)の探索ログ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if detailedRun?.completion?.dropRewards.isEmpty == false {
                        ToolbarItem(placement: .topBarTrailing) {
                            ItemBrowserFilterButton(
                                catalog: dropRewardCatalog,
                                filter: $itemFilter
                            )
                        }
                    }
                }
                .task {
                    await explorationStore.loadIfNeeded(masterData: masterData)
                    await loadRunDetail()
                }
                .task(id: progressKey(for: runSummary)) {
                    guard runSummary != nil else {
                        return
                    }

                    await loadRunDetail()
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
        runDetail ?? explorationStore.runs.first {
            $0.partyId == partyId && $0.partyRunId == partyRunId
        }
    }

    private var runSummary: RunSessionRecord? {
        explorationStore.runs.first {
            $0.partyId == partyId && $0.partyRunId == partyRunId
        }
    }

    private var detailedRun: RunSessionRecord? {
        runDetail
    }

    private var partyName: String {
        partyStore.partiesById[partyId]?.name ?? "パーティ\(partyId)"
    }

    private func loadRunDetail() async {
        runDetail = await explorationStore.loadRunDetail(
            partyId: partyId,
            partyRunId: partyRunId
        )
    }

    private func progressKey(for run: RunSessionRecord?) -> String {
        guard let run else {
            return "missing"
        }

        // The detail view reloads only when the public progress summary changes, which is enough
        // to detect newly revealed logs and completion payloads.
        let completionKey = run.completion?.completedAt.timeIntervalSinceReferenceDate ?? -1
        return "\(run.completedBattleCount)-\(completionKey)"
    }

    private func labyrinthName(for run: RunSessionRecord) -> String {
        masterData.labyrinths.first(where: { $0.id == run.labyrinthId }).map { labyrinth in
            masterData.explorationLabyrinthDisplayName(
                labyrinthName: labyrinth.name,
                difficultyTitleId: run.selectedDifficultyTitleId
            )
        } ?? "不明な迷宮"
    }

    private func nextProgressDate(for run: RunSessionRecord) -> Date? {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }),
              run.completion == nil else {
            return nil
        }

        return run.startedAt.addingTimeInterval(
            run.progressIntervalSeconds(baseIntervalSeconds: labyrinth.progressIntervalSeconds)
                * Double(run.completedBattleCount + 1)
        )
    }

    private func displayedBattleLogs(from run: RunSessionRecord) -> [ExplorationBattleLog] {
        // Only battles that have actually been completed are displayed, newest first.
        Array(run.battleLogs.prefix(run.completedBattleCount).reversed())
    }

    private func displayedDropRewards(
        from completion: RunCompletionRecord
    ) -> [ExplorationDropReward] {
        return completion.dropRewards.filter { reward in
            guard let category = itemsByID[reward.itemID.baseItemId]?.category else {
                return false
            }
            return itemFilter.matches(
                itemID: reward.itemID,
                category: category
            )
        }
    }

    private func dropRewardCatalog(
        for completion: RunCompletionRecord?
    ) -> ItemBrowserFilterCatalog {
        ItemBrowserFilterCatalog(
            itemIDs: completion?.dropRewards.map(\.itemID) ?? [],
            masterData: masterData
        )
    }

    private func defeatedPartyMemberText(for log: ExplorationBattleLog) -> String? {
        // A party member is listed once if they were defeated at any point during the battle, even
        // if later actions in the same log changed HP again.
        let defeatedTargets = Set(
            log.battleRecord.turns
                .flatMap(\.actions)
                .flatMap(\.results)
                .filter { $0.flags.contains(.defeated) }
                .map(\.targetId)
        )

        let defeatedNames = log.combatants
            .filter { $0.side == .ally && defeatedTargets.contains($0.id) }
            .sorted { $0.formationIndex < $1.formationIndex }
            .map(\.name)

        guard !defeatedNames.isEmpty else {
            return nil
        }

        return "死亡：\(defeatedNames.joined(separator: "、"))"
    }

    private func explorationResultText(for run: RunSessionRecord) -> String {
        let labyrinthName = labyrinthName(for: run)

        if let completion = run.completion {
            return "\(labyrinthName)：\(completionSummaryText(for: completion.reason))。"
        }

        // Active runs summarize the next deterministic progress tick rather than wall-clock elapsed
        // time so the message matches the underlying progression model.
        if let nextProgressDate = nextProgressDate(for: run) {
            return "\(labyrinthName)：探索中です。現在\(run.completedBattleCount)戦完了、次の進行は\(nextProgressDate.formatted(date: .omitted, time: .standard))です。"
        }

        return "\(labyrinthName)：探索中です。"
    }

    private func completionSummaryText(for reason: RunCompletionReason) -> String {
        switch reason {
        case .cleared:
            "迷宮を踏破しました"
        case .defeated:
            "全滅しました"
        case .draw:
            "引き分けで帰還しました"
        }
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

}

private struct BattleLogSummaryRow: View {
    let titleText: String
    let resultText: String
    let turnCount: Int
    let footerText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.headline)

            Text("\(resultText) / \(turnCount)ターン")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let footerText {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
